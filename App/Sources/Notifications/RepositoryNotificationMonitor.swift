import Foundation
import GHOrchestratorCore

@MainActor
final class RepositoryNotificationMonitor {
    private let settingsStore: SettingsStore
    private let dataSource: any DashboardDataSource
    private let sleeper: any DashboardSleepProviding
    private let delivery: any LocalNotificationDelivering
    private let evaluator: RepositoryNotificationEventEvaluator

    private var authenticationState: GitHubAuthenticationState
    private var isMenuVisible = false
    private var baseline: RepositoryNotificationBaseline?
    private var pollingTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var settingsChangeHandlerID: UUID?

    init(
        settingsStore: SettingsStore,
        dataSource: any DashboardDataSource,
        sleeper: any DashboardSleepProviding,
        delivery: any LocalNotificationDelivering,
        evaluator: RepositoryNotificationEventEvaluator = RepositoryNotificationEventEvaluator(),
        authenticationState: GitHubAuthenticationState = .signedOut
    ) {
        self.settingsStore = settingsStore
        self.dataSource = dataSource
        self.sleeper = sleeper
        self.delivery = delivery
        self.evaluator = evaluator
        self.authenticationState = authenticationState

        self.settingsChangeHandlerID = settingsStore.addSettingsChangeHandler { [weak self] oldSettings, newSettings in
            Task { @MainActor in
                self?.settingsDidChange(from: oldSettings, to: newSettings)
            }
        }

        restartPolling(resetBaseline: true)
    }

    deinit {
        pollingTask?.cancel()
        refreshTask?.cancel()

        if let settingsChangeHandlerID {
            settingsStore.removeSettingsChangeHandler(id: settingsChangeHandlerID)
        }
    }

    func setMenuVisible(_ isVisible: Bool) {
        guard isMenuVisible != isVisible else {
            return
        }

        isMenuVisible = isVisible

        if isVisible {
            cancelPolling()
            cancelRefresh()
        } else {
            restartPolling(resetBaseline: false)
        }
    }

    func setAuthenticationState(_ authenticationState: GitHubAuthenticationState) {
        guard self.authenticationState != authenticationState else {
            return
        }

        self.authenticationState = authenticationState
        restartPolling(resetBaseline: true)
    }

    private func settingsDidChange(
        from oldSettings: AppSettings,
        to newSettings: AppSettings
    ) {
        let notificationDataShapeChanged =
            oldSettings.observedRepositories != newSettings.observedRepositories ||
            oldSettings.repositoryNotificationSettings != newSettings.repositoryNotificationSettings ||
            oldSettings.graphQLSearchResultLimit != newSettings.graphQLSearchResultLimit ||
            oldSettings.graphQLReviewThreadLimit != newSettings.graphQLReviewThreadLimit ||
            oldSettings.graphQLReviewThreadCommentLimit != newSettings.graphQLReviewThreadCommentLimit ||
            oldSettings.graphQLCheckContextLimit != newSettings.graphQLCheckContextLimit

        let pollingIntervalChanged = oldSettings.pollingIntervalSeconds != newSettings.pollingIntervalSeconds

        if notificationDataShapeChanged || pollingIntervalChanged {
            restartPolling(resetBaseline: notificationDataShapeChanged)
        }
    }

    private func restartPolling(resetBaseline: Bool) {
        cancelPolling()
        cancelRefresh()

        if resetBaseline {
            baseline = nil
        }

        guard canMonitorNotifications else {
            return
        }

        refresh()

        let intervalSeconds = settingsStore.settings.pollingIntervalSeconds
        pollingTask = Task { [sleeper] in
            while !Task.isCancelled {
                do {
                    try await sleeper.sleep(for: .seconds(intervalSeconds))
                } catch {
                    return
                }

                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    self.refreshFromPolling()
                }
            }
        }
    }

    private func refreshFromPolling() {
        guard refreshTask == nil else {
            return
        }

        refresh()
    }

    private func refresh() {
        guard canMonitorNotifications else {
            return
        }

        refreshTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        let settings = notificationSettingsSnapshot()
        let filter = DashboardFilter(pullRequestScope: .all, focusedRepositoryID: nil)

        refreshTask = Task { [dataSource] in
            do {
                let sections = try await dataSource.loadSections(
                    for: settings,
                    filter: filter
                )

                guard !Task.isCancelled else {
                    return
                }

                await self.applyLoadedSections(
                    sections,
                    settings: settings,
                    generation: generation
                )
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                await self.applyRefreshFailure(generation: generation)
            }
        }
    }

    private func applyLoadedSections(
        _ sections: [RepositorySection],
        settings: AppSettings,
        generation: Int
    ) async {
        guard generation == refreshGeneration else {
            return
        }

        let evaluation = evaluator.evaluate(
            previousBaseline: baseline,
            currentSections: sections,
            settings: settings
        )
        baseline = evaluation.baseline
        refreshTask = nil

        guard !evaluation.events.isEmpty else {
            return
        }

        let authorizationStatus = await delivery.authorizationStatus()
        guard authorizationStatus.allowsDelivery else {
            return
        }

        for event in evaluation.events {
            do {
                try await delivery.deliver(event)
            } catch {
                continue
            }
        }
    }

    private func applyRefreshFailure(generation: Int) async {
        guard generation == refreshGeneration else {
            return
        }

        refreshTask = nil
    }

    private var canMonitorNotifications: Bool {
        guard !isMenuVisible else {
            return false
        }

        guard case .authenticated = authenticationState else {
            return false
        }

        return notificationSettingsSnapshot().hasEnabledRepositoryNotifications
    }

    private func notificationSettingsSnapshot() -> AppSettings {
        let settings = settingsStore.settings
        let enabledRepositoryIDs = Set(
            settings.repositoryNotificationSettings
                .filter(\.enabled)
                .map(\.repositoryID)
        )
        let repositories = settings.observedRepositories.filter {
            enabledRepositoryIDs.contains($0.normalizedLookupKey)
        }

        return AppSettings(
            observedRepositories: repositories,
            pollingIntervalSeconds: settings.pollingIntervalSeconds,
            hideDockIcon: settings.hideDockIcon,
            graphQLSearchResultLimit: settings.graphQLSearchResultLimit,
            graphQLReviewThreadLimit: settings.graphQLReviewThreadLimit,
            graphQLReviewThreadCommentLimit: settings.graphQLReviewThreadCommentLimit,
            graphQLCheckContextLimit: settings.graphQLCheckContextLimit,
            repositoryNotificationSettings: settings.repositoryNotificationSettings
        )
    }

    private func cancelPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}
