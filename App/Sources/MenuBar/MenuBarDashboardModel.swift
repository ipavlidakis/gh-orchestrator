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

    var state: State = .idle
    var cliHealth: GitHubCLIHealth = .missing
    var isMenuVisible = false
    var expandedPullRequestIDs = Set<String>()

    init(
        settingsStore: SettingsStore = SettingsStore(),
        dataSource: any DashboardDataSource = LiveDashboardDataSource(),
        sleeper: any DashboardSleepProviding = TaskSleepProvider()
    ) {
        self.settingsStore = settingsStore
        self.dataSource = dataSource
        self.sleeper = sleeper

        observeSettings()
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
            refresh()
            restartPolling()
        } else {
            cancelPolling()
            cancelRefresh()
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

    func toggleExpansion(for pullRequestID: String) {
        if expandedPullRequestIDs.contains(pullRequestID) {
            expandedPullRequestIDs.remove(pullRequestID)
        } else {
            expandedPullRequestIDs.insert(pullRequestID)
        }
    }

    private func applyLoadedSections(_ sections: [RepositorySection]) {
        let visibleIDs = Set(
            sections.flatMap { section in
                section.pullRequests.map(\.id)
            }
        )
        expandedPullRequestIDs.formIntersection(visibleIDs)

        state = sections.isEmpty ? .empty : .loaded(sections)
    }

    private func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func restartPolling() {
        cancelPolling()

        guard isMenuVisible else {
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

    private func observeSettings() {
        withObservationTracking {
            _ = settingsStore.settings
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else {
                    return
                }

                if self.isMenuVisible {
                    self.refresh()
                    self.restartPolling()
                }

                self.observeSettings()
            }
        }
    }
}
