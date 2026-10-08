import Foundation

public enum PullRequestScope: String, Codable, CaseIterable, Sendable {
    case mine
    case reviewRequested
    // Background notifications include all PRs in their configured repositories.
    case all
}

public protocol PullRequestSnapshotFetching: Sendable {
    func fetchRepositorySnapshots(
        for repositories: [ObservedRepository],
        scope: PullRequestScope,
        queryLimits: PullRequestSnapshotQueryLimits
    ) async throws -> [RepositoryPullRequestSnapshot]
}

public extension PullRequestSnapshotFetching {
    func fetchRepositorySnapshots(
        for repositories: [ObservedRepository]
    ) async throws -> [RepositoryPullRequestSnapshot] {
        try await fetchRepositorySnapshots(
            for: repositories,
            scope: .mine,
            queryLimits: .default
        )
    }

    func fetchRepositorySnapshots(
        for repositories: [ObservedRepository],
        scope: PullRequestScope
    ) async throws -> [RepositoryPullRequestSnapshot] {
        try await fetchRepositorySnapshots(
            for: repositories,
            scope: scope,
            queryLimits: .default
        )
    }
}

public struct PullRequestSnapshotQueryLimits: Equatable, Sendable {
    public static let `default` = PullRequestSnapshotQueryLimits()

    public let searchResultLimit: Int
    public let reviewThreadLimit: Int
    public let reviewThreadCommentLimit: Int
    public let checkContextLimit: Int

    public init(
        searchResultLimit: Int = AppSettings.defaultGraphQLSearchResultLimit,
        reviewThreadLimit: Int = AppSettings.defaultGraphQLReviewThreadLimit,
        reviewThreadCommentLimit: Int = AppSettings.defaultGraphQLReviewThreadCommentLimit,
        checkContextLimit: Int = AppSettings.defaultGraphQLCheckContextLimit
    ) {
        self.searchResultLimit = AppSettings.clampGraphQLConnectionLimit(searchResultLimit)
        self.reviewThreadLimit = AppSettings.clampGraphQLConnectionLimit(reviewThreadLimit)
        self.reviewThreadCommentLimit = AppSettings.clampGraphQLReviewThreadCommentLimit(reviewThreadCommentLimit)
        self.checkContextLimit = AppSettings.clampGraphQLConnectionLimit(checkContextLimit)
    }
}

public enum PullRequestSnapshotServiceError: Error, Equatable, Sendable {
    case requestFailed(message: String)
    case invalidResponse(message: String)
}

extension PullRequestSnapshotServiceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .requestFailed(let message):
            return "Failed to load pull requests: \(message)"
        case .invalidResponse(let message):
            return "Received an invalid pull request response: \(message)"
        }
    }
}

public struct GHPullRequestSnapshotService: PullRequestSnapshotFetching {
    public let client: any GitHubAPIClient

    public init(client: any GitHubAPIClient = URLSessionGitHubAPIClient()) {
        self.client = client
    }

    public func fetchRepositorySnapshots(
        for repositories: [ObservedRepository],
        scope: PullRequestScope = .mine,
        queryLimits: PullRequestSnapshotQueryLimits = .default
    ) async throws -> [RepositoryPullRequestSnapshot] {
        if scope == .all && repositories.isEmpty { return [] }
        var items: [PullRequestSnapshotItem] = []
        var seenIDs = Set<String>()
        var seenCursors = Set<String>()
        var cursor: String?

        repeat {
            try Task.checkCancellation()
            let page = try await fetchSearchPage(repositories: repositories, scope: scope, cursor: cursor, queryLimits: queryLimits)
            guard page.issueCount <= 1_000 else {
                throw PullRequestSnapshotServiceError.requestFailed(message: "This category exceeds GitHub's 1,000-result search limit (\(page.issueCount) matches).")
            }
            for node in page.nodes where node.typename == "PullRequest" {
                guard let fullName = node.repository?.nameWithOwner,
                      let discovered = ObservedRepository(rawValue: fullName) else {
                    throw PullRequestSnapshotServiceError.invalidResponse(message: "Missing or invalid repository in GraphQL pull request response")
                }
                let repository = repositories.first { $0.normalizedLookupKey == discovered.normalizedLookupKey } ?? discovered
                if let item = try mapNode(node, repository: repository), seenIDs.insert(item.id).inserted {
                    items.append(item)
                }
            }
            guard page.pageInfo.hasNextPage else { break }
            guard let nextCursor = page.pageInfo.endCursor, !nextCursor.isEmpty,
                  seenCursors.insert(nextCursor).inserted else {
                throw PullRequestSnapshotServiceError.invalidResponse(message: "Missing or repeated search pagination cursor")
            }
            cursor = nextCursor
        } while true

        return Dictionary(grouping: items, by: \.repository.normalizedLookupKey).values.map { items in
            RepositoryPullRequestSnapshot(repository: items[0].repository, pullRequests: items)
        }.sorted { $0.repository.normalizedLookupKey < $1.repository.normalizedLookupKey }
    }
}

extension GHPullRequestSnapshotService {
    static func searchQuery(limits: PullRequestSnapshotQueryLimits = .default) -> String {
        """
    query($searchQuery: String!, $cursor: String) {
      search(query: $searchQuery, type: ISSUE, first: \(limits.searchResultLimit), after: $cursor) {
        issueCount
        pageInfo { hasNextPage endCursor }
        nodes {
          __typename
          ... on PullRequest {
            repository { nameWithOwner }
            number
            title
            url
            author {
              login
            }
            isDraft
            createdAt
            updatedAt
            reviewDecision
            mergeable
            reviewThreads(first: \(limits.reviewThreadLimit)) {
              nodes {
                isResolved
                isOutdated
                path
                comments(last: \(limits.reviewThreadCommentLimit)) {
                  nodes {
                    url
                    bodyText
                    createdAt
                    author {
                      login
                      avatarUrl(size: 56)
                    }
                  }
                }
              }
            }
            statusCheckRollup {
              state
              contexts(first: \(limits.checkContextLimit)) {
                nodes {
                  __typename
                  ... on CheckRun {
                    name
                    status
                    conclusion
                    detailsUrl
                    completedAt
                    checkSuite {
                      app {
                        name
                        slug
                      }
                      workflowRun {
                        databaseId
                        url
                        workflow {
                          name
                        }
                      }
                    }
                  }
                  ... on StatusContext {
                    context
                    state
                    targetUrl
                    description
                  }
                }
              }
            }
          }
        }
      }
    }
    """
    }

    private func fetchSearchPage(
        repositories: [ObservedRepository],
        scope: PullRequestScope,
        cursor: String?,
        queryLimits: PullRequestSnapshotQueryLimits
    ) async throws -> PullRequestSearchResponseDTO.SearchResultDTO {
        do {
            let response: PullRequestSearchResponseDTO.SearchDataDTO = try await client.graphQL(
                query: Self.searchQuery(limits: queryLimits),
                variables: SearchQueryVariables(searchQuery: searchQuery(scope: scope, repositories: repositories), cursor: cursor)
            )
            return response.search
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as GitHubAPIClientError {
            switch error {
            case .invalidResponse(let message):
                throw PullRequestSnapshotServiceError.invalidResponse(
                    message: message
                )
            default:
                throw PullRequestSnapshotServiceError.requestFailed(
                    message: error.displayMessage
                )
            }
        } catch {
            throw PullRequestSnapshotServiceError.requestFailed(
                message: error.localizedDescription
            )
        }
    }

    func searchQuery(scope: PullRequestScope, repositories: [ObservedRepository]) -> String {
        let qualifiers: String
        switch scope {
        case .mine: qualifiers = "author:@me"
        case .reviewRequested: qualifiers = "review-requested:@me"
        case .all: qualifiers = repositories.map { "repo:\($0.fullName)" }.joined(separator: " ")
        }
        return "is:pr is:open \(qualifiers) archived:false sort:updated-desc"
    }

    private func mapNode(
        _ node: PullRequestSearchResponseDTO.SearchNodeDTO,
        repository: ObservedRepository
    ) throws -> PullRequestSnapshotItem? {
        guard node.typename == "PullRequest" else {
            return nil
        }

        guard
            let number = node.number,
            let title = node.title,
            let url = node.url,
            let isDraft = node.isDraft,
            let updatedAt = node.updatedAt
        else {
            throw PullRequestSnapshotServiceError.invalidResponse(
                message: "Missing required pull request fields in GraphQL response"
            )
        }

        let unresolvedCount = node.reviewThreads?.nodes.reduce(into: 0) { count, thread in
            if !thread.isResolved && !thread.isOutdated {
                count += 1
            }
        } ?? 0

        let unresolvedComments = (node.reviewThreads?.nodes ?? [])
            .filter { !$0.isResolved && !$0.isOutdated }
            .flatMap { thread in
                (thread.comments?.nodes ?? []).compactMap { comment -> UnresolvedReviewCommentSnapshot? in
                    guard
                        let url = comment.url,
                        let authorLogin = comment.author?.login,
                        let bodyText = comment.bodyText,
                        let filePath = thread.path,
                        !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    else {
                        return nil
                    }

                    return UnresolvedReviewCommentSnapshot(
                        url: url,
                        authorLogin: authorLogin,
                        bodyText: bodyText,
                        filePath: filePath,
                        authorAvatarURL: comment.author?.avatarUrl,
                        createdAt: comment.createdAt
                    )
                }
            }

        let mappedCheckRuns = node.statusCheckRollup?.contexts.nodes.compactMap { context in
            mapCheckRun(context)
        } ?? []

        let mappedStatusContexts = node.statusCheckRollup?.contexts.nodes.compactMap { context in
            mapStatusContext(context)
        } ?? []

        return PullRequestSnapshotItem(
            repository: repository,
            number: number,
            title: title,
            url: url,
            authorLogin: node.author?.login,
            isDraft: isDraft,
            createdAt: node.createdAt,
            updatedAt: updatedAt,
            reviewStatus: mapReviewStatus(node.reviewDecision),
            mergeable: node.mergeable.flatMap(MergeableState.init(rawValue:)) ?? .unknown,
            unresolvedReviewThreadCount: unresolvedCount,
            unresolvedReviewComments: unresolvedComments,
            checkRollupState: mapCheckRollupState(node.statusCheckRollup?.state),
            checkRuns: mappedCheckRuns,
            statusContexts: mappedStatusContexts
        )
    }

    private func mapReviewStatus(_ reviewDecision: String?) -> ReviewStatus {
        switch reviewDecision {
        case "APPROVED":
            return .approved
        case "CHANGES_REQUESTED":
            return .changesRequested
        case "REVIEW_REQUIRED":
            return .reviewRequired
        default:
            return .none
        }
    }

    private func mapCheckRollupState(_ state: String?) -> CheckRollupState {
        switch state {
        case "SUCCESS":
            return .passing
        case "EXPECTED", "PENDING", "IN_PROGRESS", "QUEUED":
            return .pending
        case "ERROR", "FAILURE", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE", "STALE", "CANCELLED":
            return .failing
        default:
            return .none
        }
    }

    private func mapCheckRun(_ context: PullRequestSearchResponseDTO.CheckContextNodeDTO) -> CheckRunSnapshot? {
        guard context.typename == "CheckRun",
              let name = context.name,
              let status = context.status
        else {
            return nil
        }

        return CheckRunSnapshot(
            name: name,
            status: status,
            conclusion: context.conclusion,
            detailsURL: context.detailsUrl,
            completedAt: context.completedAt,
            appName: context.checkSuite?.app?.name,
            appSlug: context.checkSuite?.app?.slug,
            workflowRun: mapWorkflowRun(context.checkSuite?.workflowRun)
        )
    }

    private func mapStatusContext(_ context: PullRequestSearchResponseDTO.CheckContextNodeDTO) -> StatusContextSnapshot? {
        guard context.typename == "StatusContext",
              let name = context.context,
              let state = context.state
        else {
            return nil
        }

        return StatusContextSnapshot(
            context: name,
            state: state,
            targetURL: context.targetUrl,
            description: context.description
        )
    }

    private func mapWorkflowRun(
        _ workflowRun: PullRequestSearchResponseDTO.WorkflowRunDTO?
    ) -> WorkflowRunReferenceSnapshot? {
        guard let workflowRun else {
            return nil
        }

        return WorkflowRunReferenceSnapshot(
            id: workflowRun.databaseId,
            url: workflowRun.url,
            workflowName: workflowRun.workflow?.name
        )
    }
}

private struct SearchQueryVariables: Encodable, Sendable {
    let searchQuery: String
    let cursor: String?
}
