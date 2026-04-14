import GHOrchestratorCore

protocol DashboardDataSource: Sendable {
    func loadSections(for settings: AppSettings) async throws -> [RepositorySection]
    func rerunWorkflowJob(
        repository: ObservedRepository,
        jobID: Int
    ) async throws
}

struct LiveDashboardDataSource: DashboardDataSource {
    let snapshotService: any PullRequestSnapshotFetching
    let actionsService: any ActionsJobsEnriching
    let retryService: any ActionsJobRetrying
    let aggregationService: any RepositorySectionAggregating

    init(
        client: any GitHubAPIClient = URLSessionGitHubAPIClient(),
        aggregationService: any RepositorySectionAggregating = RepositorySectionAggregationService()
    ) {
        self.snapshotService = GHPullRequestSnapshotService(client: client)
        self.actionsService = ActionsJobsEnrichmentService(client: client)
        self.retryService = ActionsJobRetryService(client: client)
        self.aggregationService = aggregationService
    }

    func loadSections(for settings: AppSettings) async throws -> [RepositorySection] {
        let snapshots = try await snapshotService.fetchRepositorySnapshots(
            for: settings.observedRepositories
        )
        let items = try await actionsService.buildPullRequestItems(from: snapshots)
        return aggregationService.makeSections(
            observedRepositories: settings.observedRepositories,
            pullRequests: items
        )
    }

    func rerunWorkflowJob(
        repository: ObservedRepository,
        jobID: Int
    ) async throws {
        try await retryService.rerunJob(
            repository: repository,
            jobID: jobID
        )
    }
}
