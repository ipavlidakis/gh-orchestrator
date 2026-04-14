import Foundation
import GHOrchestratorCore
import Observation

@MainActor
@Observable
final class MenuBarDashboardModel {
    enum State: Equatable {
        case idle
        case loading
        case notConfigured
        case signedOut
        case authorizing
        case empty
        case noRepositoriesConfigured
        case authFailure(String)
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
    private var retryTasksByJobID: [Int: Task<Void, Never>] = [:]

    @ObservationIgnored
    private var stateBeforeLoading: State = .idle

    var state: State = .idle
    var authenticationState: GitHubAuthenticationState
    var isMenuVisible = false
    var expandedChecksPullRequestIDs = Set<String>()
    var expandedCommentPullRequestIDs = Set<String>()
    var retryingJobIDs = Set<Int>()
    var retryErrorMessagesByJobID: [Int: String] = [:]

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
        sleeper: any DashboardSleepProviding = TaskSleepProvider(),
        authenticationState: GitHubAuthenticationState = .signedOut
    ) {
        self.settingsStore = settingsStore
        self.dataSource = dataSource
        self.sleeper = sleeper
        self.authenticationState = authenticationState

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
        retryTasksByJobID.values.forEach { $0.cancel() }
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

    func setAuthenticationState(_ authenticationState: GitHubAuthenticationState) {
        guard self.authenticationState != authenticationState else {
            return
        }

        self.authenticationState = authenticationState
        refresh()
    }

    func refresh() {
        let settings = settingsStore.settings

        refreshTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration

        switch authenticationState {
        case .notConfigured:
            state = .notConfigured
            return
        case .signedOut:
            state = .signedOut
            return
        case .authorizing:
            state = .authorizing
            return
        case .authFailure(let message):
            state = .authFailure(message)
            return
        case .authenticated:
            break
        }

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

    func retryWorkflowJob(
        repository: ObservedRepository,
        jobID: Int
    ) {
        guard retryTasksByJobID[jobID] == nil else {
            return
        }

        retryErrorMessagesByJobID[jobID] = nil
        retryingJobIDs.insert(jobID)

        let task = Task { [dataSource] in
            do {
                try await dataSource.rerunWorkflowJob(
                    repository: repository,
                    jobID: jobID
                )

                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    self.retryingJobIDs.remove(jobID)
                    self.retryTasksByJobID[jobID] = nil
                    self.refresh()
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.retryingJobIDs.remove(jobID)
                    self.retryTasksByJobID[jobID] = nil
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    self.retryingJobIDs.remove(jobID)
                    self.retryTasksByJobID[jobID] = nil
                    self.retryErrorMessagesByJobID[jobID] = error.localizedDescription
                }
            }
        }

        retryTasksByJobID[jobID] = task
    }

    func isRetryingJob(_ jobID: Int) -> Bool {
        retryingJobIDs.contains(jobID)
    }

    func retryErrorMessage(for jobID: Int) -> String? {
        retryErrorMessagesByJobID[jobID]
    }

    private func applyLoadedSections(_ sections: [RepositorySection]) {
        let visibleIDs = Set(
            sections.flatMap { section in
                section.pullRequests.map(\.id)
            }
        )
        let visibleJobIDs = Set(
            sections.flatMap { section in
                section.pullRequests.flatMap { pullRequest in
                    pullRequest.workflowRuns.flatMap { workflowRun in
                        workflowRun.jobs.map(\.id)
                    }
                }
            }
        )
        expandedChecksPullRequestIDs.formIntersection(visibleIDs)
        expandedCommentPullRequestIDs.formIntersection(visibleIDs)
        retryingJobIDs.formIntersection(visibleJobIDs)
        retryErrorMessagesByJobID = retryErrorMessagesByJobID.filter { visibleJobIDs.contains($0.key) }

        state = sections.isEmpty ? .empty : .loaded(sections)
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
