import GHOrchestratorCore

protocol DashboardDataSource: Sendable {
    func loadSections(for settings: AppSettings) async throws -> [RepositorySection]
}

struct LiveDashboardDataSource: DashboardDataSource {
    let snapshotService: any PullRequestSnapshotFetching
    let actionsService: any ActionsJobsEnriching
    let aggregationService: any RepositorySectionAggregating

    init(
        client: any GitHubAPIClient = URLSessionGitHubAPIClient(),
        aggregationService: any RepositorySectionAggregating = RepositorySectionAggregationService()
    ) {
        self.snapshotService = GHPullRequestSnapshotService(client: client)
        self.actionsService = ActionsJobsEnrichmentService(client: client)
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
}
