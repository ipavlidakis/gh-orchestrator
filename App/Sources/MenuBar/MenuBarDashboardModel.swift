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
    var pullRequestScope: PullRequestScope {
        get { settingsStore.settings.dashboardPullRequestScope }
        set { settingsStore.settings.dashboardPullRequestScope = newValue }
    }
    var focusedRepositoryID: String? {
        get { settingsStore.settings.dashboardFocusedRepositoryID }
        set { settingsStore.settings.dashboardFocusedRepositoryID = newValue }
    }
    var collapsedRepositoryIDs = Set<String>()
    var expandedChecksPullRequestIDs = Set<String>()
    var expandedCommentPullRequestIDs = Set<String>()
    var retryingJobIDs = Set<Int>()
    var retryErrorMessagesByJobID: [Int: String] = [:]
    var refreshWarningMessage: String?
    var lastRefreshedAt: Date?

    var isRefreshing: Bool {
        if case .loading = state {
            return true
        }

        return false
    }

    var contentState: State {
        let visibleState = isRefreshing ? stateBeforeLoading : state
        guard case .loaded(let sections) = visibleState else { return visibleState }
        let filtered = sections.filter {
            focusedRepositoryID == nil || $0.repository.normalizedLookupKey == focusedRepositoryID
        }
        guard !filtered.isEmpty else { return .empty }
        return .loaded(RepositorySectionAggregationService().makeSections(
            observedRepositories: filtered.map(\.repository),
            pullRequests: filtered.flatMap(\.pullRequests),
            sortOrder: settingsStore.settings.pullRequestSortOrder,
            repositorySortOrder: settingsStore.settings.repositorySortOrder
        ))
    }

    var availableRepositories: [ObservedRepository] {
        let visibleState = isRefreshing ? stateBeforeLoading : state
        var repositories = settingsStore.settings.observedRepositories
        if case .loaded(let sections) = visibleState {
            repositories += sections.map(\.repository)
        }
        if let focusedRepositoryID, let repository = ObservedRepository(rawValue: focusedRepositoryID) {
            repositories.append(repository)
        }
        var seen = Set<String>()
        return repositories.filter { seen.insert($0.normalizedLookupKey).inserted }
            .sorted { $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending }
    }

    /// Pull requests that need the user's attention: failing checks or requested changes.
    var attentionCount: Int {
        guard case .loaded(let sections) = contentState else { return 0 }
        return sections.flatMap(\.pullRequests).filter {
            $0.checkRollupState == .failing || $0.reviewStatus == .changesRequested
        }.count
    }

    var areDashboardFiltersDisabled: Bool {
        if case .commandFailure = state { return false }
        return refreshWarningMessage != nil
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
                let categoryChanged = oldSettings.dashboardPullRequestScope != newSettings.dashboardPullRequestScope
                if let focused = self.focusedRepositoryID,
                   oldSettings.observedRepositories.contains(where: { $0.normalizedLookupKey == focused }),
                   !newSettings.observedRepositories.contains(where: { $0.normalizedLookupKey == focused }) {
                    self.focusedRepositoryID = nil
                }
                if categoryChanged {
                    self.state = .idle
                    self.stateBeforeLoading = .idle
                    self.refreshWarningMessage = nil
                }
                if repositoriesChanged || pollingIntervalChanged || categoryChanged {
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
    }

    func setAuthenticationState(_ authenticationState: GitHubAuthenticationState) {
        guard self.authenticationState != authenticationState else {
            return
        }

        self.authenticationState = authenticationState
        refresh()
    }

    func setPullRequestScope(_ pullRequestScope: PullRequestScope) {
        guard self.pullRequestScope != pullRequestScope else {
            return
        }

        self.pullRequestScope = pullRequestScope
    }

    func setFocusedRepositoryID(_ repositoryID: String?) {
        let normalizedRepositoryID = normalizedRepositoryID(repositoryID)
        let nextRepositoryID = normalizedRepositoryID.flatMap { repositoryID in
            availableRepositories.contains {
                $0.normalizedLookupKey == repositoryID
            } ? repositoryID : nil
        }

        guard focusedRepositoryID != nextRepositoryID else {
            return
        }

        focusedRepositoryID = nextRepositoryID
        if let nextRepositoryID {
            collapsedRepositoryIDs.remove(nextRepositoryID)
        }
    }

    func toggleRepositoryCollapsed(repositoryID: String) {
        let repositoryID = repositoryID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !repositoryID.isEmpty else {
            return
        }

        if collapsedRepositoryIDs.contains(repositoryID) {
            collapsedRepositoryIDs.remove(repositoryID)
        } else {
            collapsedRepositoryIDs.insert(repositoryID)
        }
    }

    func refresh() {
        let settings = settingsStore.settings
        let filter = DashboardFilter(
            pullRequestScope: pullRequestScope,
            focusedRepositoryID: focusedRepositoryID
        )

        refreshTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration

        switch authenticationState {
        case .notConfigured:
            refreshWarningMessage = nil
            state = .notConfigured
            return
        case .signedOut:
            refreshWarningMessage = nil
            state = .signedOut
            return
        case .authorizing:
            refreshWarningMessage = nil
            state = .authorizing
            return
        case .authFailure(let message):
            refreshWarningMessage = nil
            state = .authFailure(message)
            return
        case .authenticated:
            break
        }

        if case .loading = state {
            // Keep the previous stable state snapshot for restoration on cancellation.
        } else {
            stateBeforeLoading = state
        }
        state = .loading

        refreshTask = Task { [dataSource] in
            do {
                let sections = try await dataSource.loadSections(
                    for: settings,
                    filter: filter
                )
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

                    self.applyRefreshFailure(error.localizedDescription)
                }
            }
        }
    }

    func toggleChecksExpansion(for pullRequestID: String) {
        if expandedChecksPullRequestIDs.contains(pullRequestID) {
            expandedChecksPullRequestIDs.remove(pullRequestID)
        } else {
            expandedChecksPullRequestIDs = [pullRequestID]
            expandedCommentPullRequestIDs.removeAll()
        }
    }

    func toggleCommentsExpansion(for pullRequestID: String) {
        if expandedCommentPullRequestIDs.contains(pullRequestID) {
            expandedCommentPullRequestIDs.remove(pullRequestID)
        } else {
            expandedCommentPullRequestIDs = [pullRequestID]
            expandedChecksPullRequestIDs.removeAll()
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

    private func normalizedRepositoryID(_ repositoryID: String?) -> String? {
        guard let repositoryID else {
            return nil
        }

        let normalized = repositoryID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func applyLoadedSections(_ sections: [RepositorySection]) {
        lastRefreshedAt = Date()
        let visibleRepositoryIDs = Set(sections.map(\.repository.normalizedLookupKey))
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
        collapsedRepositoryIDs.formIntersection(visibleRepositoryIDs)
        expandedChecksPullRequestIDs.formIntersection(visibleIDs)
        expandedCommentPullRequestIDs.formIntersection(visibleIDs)
        retryingJobIDs.formIntersection(visibleJobIDs)
        retryErrorMessagesByJobID = retryErrorMessagesByJobID.filter { visibleJobIDs.contains($0.key) }

        refreshWarningMessage = nil
        state = sections.isEmpty ? .empty : .loaded(sections)
    }

    private func applyRefreshFailure(_ message: String) {
        switch stateBeforeLoading {
        case .loaded, .empty:
            refreshWarningMessage = message
            state = stateBeforeLoading
        default:
            refreshWarningMessage = message
            state = .commandFailure(message)
        }

        if isRateLimitFailure(message) {
            cancelPolling()
        }
    }

    private func isRateLimitFailure(_ message: String) -> Bool {
        message.localizedCaseInsensitiveContains("rate limit")
    }

    private func restartPolling() {
        cancelPolling()

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
        guard !isRefreshing else {
            return
        }

        refresh()
    }

    private func cancelPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}
