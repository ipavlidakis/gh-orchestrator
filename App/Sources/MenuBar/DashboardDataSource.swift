import Foundation
import GHOrchestratorCore

struct DashboardFilter: Equatable, Sendable {
    static let `default` = DashboardFilter()

    let pullRequestScope: PullRequestScope
    let focusedRepositoryID: String?

    init(
        pullRequestScope: PullRequestScope = .mine,
        focusedRepositoryID: String? = nil
    ) {
        self.pullRequestScope = pullRequestScope
        self.focusedRepositoryID = focusedRepositoryID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

protocol DashboardDataSource: Sendable {
    func loadSections(
        for settings: AppSettings,
        filter: DashboardFilter
    ) async throws -> [RepositorySection]
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

    func loadSections(
        for settings: AppSettings,
        filter: DashboardFilter
    ) async throws -> [RepositorySection] {
        let repositories = repositories(
            from: settings,
            focusedRepositoryID: filter.focusedRepositoryID
        )
        let snapshots = try await snapshotService.fetchRepositorySnapshots(
            for: repositories,
            scope: filter.pullRequestScope,
            queryLimits: PullRequestSnapshotQueryLimits(
                searchResultLimit: settings.graphQLSearchResultLimit,
                reviewThreadLimit: settings.graphQLReviewThreadLimit,
                reviewThreadCommentLimit: settings.graphQLReviewThreadCommentLimit,
                checkContextLimit: settings.graphQLCheckContextLimit
            )
        )
        let items = try await actionsService.buildPullRequestItems(from: snapshots)
        return aggregationService.makeSections(
            observedRepositories: repositories,
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

    private func repositories(
        from settings: AppSettings,
        focusedRepositoryID: String?
    ) -> [ObservedRepository] {
        guard let focusedRepositoryID else {
            return settings.observedRepositories
        }

        let focusedRepositories = settings.observedRepositories.filter {
            $0.normalizedLookupKey == focusedRepositoryID
        }

        return focusedRepositories.isEmpty ? settings.observedRepositories : focusedRepositories
    }
}
