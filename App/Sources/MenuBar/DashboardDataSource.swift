import GHOrchestratorCore

protocol DashboardDataSource: Sendable {
    func cliHealth() -> GitHubCLIHealth
    func loadSections(for settings: AppSettings) async throws -> [RepositorySection]
}

struct LiveDashboardDataSource: DashboardDataSource {
    let healthClient: any GHCLIClient
    let snapshotService: any PullRequestSnapshotFetching
    let actionsService: any ActionsJobsEnriching
    let aggregationService: any RepositorySectionAggregating

    init(
        healthClient: any GHCLIClient = ProcessGHCLIClient(),
        snapshotService: any PullRequestSnapshotFetching = GHPullRequestSnapshotService(),
        actionsService: any ActionsJobsEnriching = ActionsJobsEnrichmentService(),
        aggregationService: any RepositorySectionAggregating = RepositorySectionAggregationService()
    ) {
        self.healthClient = healthClient
        self.snapshotService = snapshotService
        self.actionsService = actionsService
        self.aggregationService = aggregationService
    }

    func cliHealth() -> GitHubCLIHealth {
        healthClient.health()
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
