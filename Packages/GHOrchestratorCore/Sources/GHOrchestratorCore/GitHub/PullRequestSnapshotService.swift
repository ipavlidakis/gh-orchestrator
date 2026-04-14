import Foundation

public protocol PullRequestSnapshotFetching: Sendable {
    func fetchRepositorySnapshots(
        for repositories: [ObservedRepository]
    ) async throws -> [RepositoryPullRequestSnapshot]
}

public enum PullRequestSnapshotServiceError: Error, Equatable, Sendable {
    case repositoryRequestFailed(repository: ObservedRepository, message: String)
    case invalidResponse(repository: ObservedRepository, message: String)
}

public struct GHPullRequestSnapshotService: PullRequestSnapshotFetching {
    public let client: any GHCLIClient

    public init(client: any GHCLIClient = ProcessGHCLIClient()) {
        self.client = client
    }

    public func fetchRepositorySnapshots(
        for repositories: [ObservedRepository]
    ) async throws -> [RepositoryPullRequestSnapshot] {
        guard !repositories.isEmpty else {
            return []
        }

        return try await withThrowingTaskGroup(of: (Int, RepositoryPullRequestSnapshot).self) { group in
            for (index, repository) in repositories.enumerated() {
                group.addTask {
                    let snapshot = try self.fetchRepositorySnapshot(for: repository)
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
            isDraft
            updatedAt
            reviewDecision
            reviewThreads(first: 100) {
              nodes {
                isResolved
                isOutdated
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

    func fetchRepositorySnapshot(for repository: ObservedRepository) throws -> RepositoryPullRequestSnapshot {
        let output: ProcessOutput

        do {
            output = try client.run(arguments: [
                "api",
                "graphql",
                "--hostname",
                "github.com",
                "-f",
                "query=\(Self.searchQuery)",
                "-f",
                "searchQuery=\(searchQuery(for: repository))",
            ])
        } catch {
            throw PullRequestSnapshotServiceError.repositoryRequestFailed(
                repository: repository,
                message: error.localizedDescription
            )
        }

        guard output.exitCode == 0 else {
            throw PullRequestSnapshotServiceError.repositoryRequestFailed(
                repository: repository,
                message: output.combinedOutput.isEmpty ? "gh api graphql exited with code \(output.exitCode)" : output.combinedOutput
            )
        }

        let payload = Data(output.standardOutput.utf8)

        do {
            let decoder = JSONDecoder.githubGraphQL
            let response = try decoder.decode(PullRequestSearchResponseDTO.self, from: payload)
            let items = try response.data.search.nodes.compactMap { node in
                try mapNode(node, repository: repository)
            }

            return RepositoryPullRequestSnapshot(repository: repository, pullRequests: items)
        } catch let error as PullRequestSnapshotServiceError {
            throw error
        } catch {
            throw PullRequestSnapshotServiceError.invalidResponse(
                repository: repository,
                message: error.localizedDescription
            )
        }
    }

    func searchQuery(for repository: ObservedRepository) -> String {
        "repo:\(repository.fullName) is:pr is:open author:@me archived:false"
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
            isDraft: isDraft,
            updatedAt: updatedAt,
            reviewStatus: mapReviewStatus(node.reviewDecision),
            unresolvedReviewThreadCount: unresolvedCount,
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

private extension JSONDecoder {
    static let githubGraphQL: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = parseISO8601Date(value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date: \(value)"
            )
        }
        return decoder
    }()

    static func parseISO8601Date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

func parseISO8601Date(_ value: String) -> Date? {
    JSONDecoder.parseISO8601Date(value)
}
