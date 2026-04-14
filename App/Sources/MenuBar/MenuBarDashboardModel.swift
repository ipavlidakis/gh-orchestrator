import Foundation
import GHOrchestratorCore
import Observation

@MainActor
@Observable
final class MenuBarDashboardModel {
    enum State: Equatable {
        case idle
        case loading
        case empty
        case ghMissing
        case loggedOut
        case noRepositoriesConfigured
        case commandFailure(String)
        case loaded([RepositorySection])
    }

    let settingsStore: SettingsStore

    private let dataSource: any DashboardDataSource
    private let sleeper: any DashboardSleepProviding

    @ObservationIgnored
    private var refreshTask: Task<Void, Never>?

    @ObservationIgnored
    private var pollingTask: Task<Void, Never>?

    @ObservationIgnored
    private var refreshGeneration = 0

    @ObservationIgnored
    private var stateBeforeLoading: State = .idle

    var state: State = .idle
    var cliHealth: GitHubCLIHealth = .missing
    var isMenuVisible = false
    var expandedChecksPullRequestIDs = Set<String>()
    var expandedCommentPullRequestIDs = Set<String>()

    var isRefreshing: Bool {
        if case .loading = state {
            return true
        }

        return false
    }

    var contentState: State {
        guard case .loading = state else {
            return state
        }

        return stateBeforeLoading
    }

    init(
        settingsStore: SettingsStore = SettingsStore(),
        dataSource: any DashboardDataSource = LiveDashboardDataSource(),
        sleeper: any DashboardSleepProviding = TaskSleepProvider()
    ) {
        self.settingsStore = settingsStore
        self.dataSource = dataSource
        self.sleeper = sleeper

        self.settingsStore.onSettingsChange = { [weak self] oldSettings, newSettings in
            Task { @MainActor in
                guard let self else {
                    return
                }

                let repositoriesChanged = oldSettings.observedRepositories != newSettings.observedRepositories
                let pollingIntervalChanged = oldSettings.pollingIntervalSeconds != newSettings.pollingIntervalSeconds

                if !self.isMenuVisible, (repositoriesChanged || pollingIntervalChanged) {
                    self.refresh()
                    self.restartPolling()
                }
            }
        }
        refresh()
        restartPolling()
    }

    deinit {
        refreshTask?.cancel()
        pollingTask?.cancel()
    }

    func setMenuVisible(_ isVisible: Bool) {
        guard self.isMenuVisible != isVisible else {
            return
        }

        self.isMenuVisible = isVisible

        if isVisible {
            cancelPolling()
        } else {
            refresh()
            restartPolling()
        }
    }

    func refresh() {
        let settings = settingsStore.settings

        refreshTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration

        guard !settings.observedRepositories.isEmpty else {
            state = .noRepositoriesConfigured
            return
        }

        if case .loading = state {
            // Keep the previous stable state snapshot for restoration on cancellation.
        } else {
            stateBeforeLoading = state
        }
        state = .loading
        let health = dataSource.cliHealth()
        cliHealth = health

        switch health {
        case .missing:
            state = .ghMissing
            return
        case .loggedOut:
            state = .loggedOut
            return
        case .commandFailure(let message):
            state = .commandFailure(message)
            return
        case .authenticated:
            break
        }

        refreshTask = Task { [dataSource] in
            do {
                let sections = try await dataSource.loadSections(for: settings)
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    guard generation == self.refreshGeneration else {
                        return
                    }

                    self.applyLoadedSections(sections)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    guard generation == self.refreshGeneration else {
                        return
                    }

                    self.state = .commandFailure(error.localizedDescription)
                }
            }
        }
    }

    func toggleChecksExpansion(for pullRequestID: String) {
        if expandedChecksPullRequestIDs.contains(pullRequestID) {
            expandedChecksPullRequestIDs.remove(pullRequestID)
        } else {
            expandedChecksPullRequestIDs.insert(pullRequestID)
        }
    }

    func toggleCommentsExpansion(for pullRequestID: String) {
        if expandedCommentPullRequestIDs.contains(pullRequestID) {
            expandedCommentPullRequestIDs.remove(pullRequestID)
        } else {
            expandedCommentPullRequestIDs.insert(pullRequestID)
        }
    }

    private func applyLoadedSections(_ sections: [RepositorySection]) {
        let visibleIDs = Set(
            sections.flatMap { section in
                section.pullRequests.map(\.id)
            }
        )
        expandedChecksPullRequestIDs.formIntersection(visibleIDs)
        expandedCommentPullRequestIDs.formIntersection(visibleIDs)

        state = sections.isEmpty ? .empty : .loaded(sections)
    }

    private func cancelRefresh(restorePreviousState: Bool = false) {
        refreshTask?.cancel()
        refreshTask = nil

        if restorePreviousState, case .loading = state {
            state = stateBeforeLoading
        }
    }

    private func restartPolling() {
        cancelPolling()

        guard !isMenuVisible else {
            return
        }

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
                    self.refresh()
                }
            }
        }
    }

    private func cancelPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}
