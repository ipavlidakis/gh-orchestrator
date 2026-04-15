import Foundation

public enum PullRequestScope: String, Codable, CaseIterable, Sendable {
    case mine
    case all
}

public protocol PullRequestSnapshotFetching: Sendable {
    func fetchRepositorySnapshots(
        for repositories: [ObservedRepository],
        scope: PullRequestScope
    ) async throws -> [RepositoryPullRequestSnapshot]
}

public extension PullRequestSnapshotFetching {
    func fetchRepositorySnapshots(
        for repositories: [ObservedRepository]
    ) async throws -> [RepositoryPullRequestSnapshot] {
        try await fetchRepositorySnapshots(
            for: repositories,
            scope: .mine
        )
    }
}

public enum PullRequestSnapshotServiceError: Error, Equatable, Sendable {
    case repositoryRequestFailed(repository: ObservedRepository, message: String)
    case invalidResponse(repository: ObservedRepository, message: String)
}

extension PullRequestSnapshotServiceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .repositoryRequestFailed(let repository, let message):
            return "Failed to load pull requests for \(repository.fullName): \(message)"
        case .invalidResponse(let repository, let message):
            return "Received an invalid pull request response for \(repository.fullName): \(message)"
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
        scope: PullRequestScope = .mine
    ) async throws -> [RepositoryPullRequestSnapshot] {
        guard !repositories.isEmpty else {
            return []
        }

        return try await withThrowingTaskGroup(of: (Int, RepositoryPullRequestSnapshot).self) { group in
            for (index, repository) in repositories.enumerated() {
                group.addTask {
                    let snapshot = try await self.fetchRepositorySnapshot(
                        for: repository,
                        scope: scope
                    )
                    return (index, snapshot)
                }
            }

            var orderedResults: [(Int, RepositoryPullRequestSnapshot)] = []
            for try await result in group {
                orderedResults.append(result)
            }

            return orderedResults
                .sorted { $0.0 < $1.0 }
                .map(\.1)
        }
    }
}

extension GHPullRequestSnapshotService {
    static let searchQuery = """
    query($searchQuery: String!) {
      search(query: $searchQuery, type: ISSUE, first: 100) {
        nodes {
          __typename
          ... on PullRequest {
            number
            title
            url
            author {
              login
            }
            isDraft
            updatedAt
            reviewDecision
            reviewThreads(first: 100) {
              nodes {
                isResolved
                isOutdated
                path
                comments(last: 20) {
                  nodes {
                    url
                    bodyText
                    author {
                      login
                    }
                  }
                }
              }
            }
            statusCheckRollup {
              state
              contexts(first: 100) {
                nodes {
                  __typename
                  ... on CheckRun {
                    name
                    status
                    conclusion
                    detailsUrl
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

    func fetchRepositorySnapshot(
        for repository: ObservedRepository,
        scope: PullRequestScope
    ) async throws -> RepositoryPullRequestSnapshot {
        do {
            let response: PullRequestSearchResponseDTO.SearchDataDTO = try await client.graphQL(
                query: Self.searchQuery,
                variables: SearchQueryVariables(searchQuery: searchQuery(for: repository, scope: scope))
            )
            let items = try response.search.nodes.compactMap { node in
                try mapNode(node, repository: repository)
            }

            return RepositoryPullRequestSnapshot(repository: repository, pullRequests: items)
        } catch let error as GitHubAPIClientError {
            switch error {
            case .invalidResponse(let message):
                throw PullRequestSnapshotServiceError.invalidResponse(
                    repository: repository,
                    message: message
                )
            default:
                throw PullRequestSnapshotServiceError.repositoryRequestFailed(
                    repository: repository,
                    message: error.displayMessage
                )
            }
        } catch {
            throw PullRequestSnapshotServiceError.repositoryRequestFailed(
                repository: repository,
                message: error.localizedDescription
            )
        }
    }

    func searchQuery(for repository: ObservedRepository, scope: PullRequestScope) -> String {
        var qualifiers = [
            "repo:\(repository.fullName)",
            "is:pr",
            "is:open"
        ]

        if scope == .mine {
            qualifiers.append("author:@me")
        }

        qualifiers.append("archived:false")

        return qualifiers.joined(separator: " ")
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
                repository: repository,
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
                        filePath: filePath
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
            updatedAt: updatedAt,
            reviewStatus: mapReviewStatus(node.reviewDecision),
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
}
