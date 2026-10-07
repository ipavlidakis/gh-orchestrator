import Foundation

public protocol PullRequestDetailLoading: Sendable {
    func summary(_ address: PullRequestAddress, checksAfter: String?) async throws -> PRSummary
    func activity(_ address: PullRequestAddress, after: String?) async throws -> PRConnection<PRActivity>
    func threads(_ address: PullRequestAddress, after: String?) async throws -> PRConnection<PRThread>
    func replies(threadID: String, after: String?) async throws -> PRConnection<PRComment>
}

public struct PullRequestDetailService: PullRequestDetailLoading {
    private let client: any GitHubAPIClient
    public init(client: any GitHubAPIClient) { self.client = client }

    public func summary(_ address: PullRequestAddress, checksAfter: String? = nil) async throws -> PRSummary {
        let result: PRSummary = try await pullRequest(address, after: checksAfter, fields: """
        title body state isDraft createdAt author { login avatarUrl }
        headRefName baseRefName additions deletions mergeable reviewDecision
        commits(last: 1) { nodes { commit { statusCheckRollup {
          contexts(first: 100, after: $after) {
            pageInfo { hasNextPage endCursor }
            nodes {
              ... on CheckRun { name status conclusion detailsUrl }
              ... on StatusContext { context state targetUrl }
            }
          }
        } } } }
        """)
        _ = try result.checksPageInfo?.nextCursor(after: checksAfter)
        return result
    }

    public func activity(_ address: PullRequestAddress, after: String? = nil) async throws -> PRConnection<PRActivity> {
        let result: ActivityResult = try await pullRequest(address, after: after, fields: """
        timelineItems(first: 50, after: $after, itemTypes: [ISSUE_COMMENT, PULL_REQUEST_REVIEW, PULL_REQUEST_COMMIT, MERGED_EVENT, CLOSED_EVENT, REOPENED_EVENT, READY_FOR_REVIEW_EVENT, CONVERT_TO_DRAFT_EVENT]) {
          pageInfo { hasNextPage endCursor }
          nodes {
            __typename
            ... on IssueComment { id body url createdAt author { login avatarUrl } }
            ... on PullRequestReview { id body url createdAt submittedAt state author { login avatarUrl } }
            ... on PullRequestCommit { commit { oid messageHeadline committedDate url } }
            ... on MergedEvent { id createdAt actor { login avatarUrl } }
            ... on ClosedEvent { id createdAt actor { login avatarUrl } }
            ... on ReopenedEvent { id createdAt actor { login avatarUrl } }
            ... on ReadyForReviewEvent { id createdAt actor { login avatarUrl } }
            ... on ConvertToDraftEvent { id createdAt actor { login avatarUrl } }
          }
        }
        """)
        _ = try result.timelineItems.pageInfo.nextCursor(after: after)
        return result.timelineItems
    }

    public func threads(_ address: PullRequestAddress, after: String? = nil) async throws -> PRConnection<PRThread> {
        let result: ThreadsResult = try await pullRequest(address, after: after, fields: """
        reviewThreads(first: 25, after: $after) {
          pageInfo { hasNextPage endCursor }
          nodes { id path line isResolved isOutdated comments(first: 20) {
            pageInfo { hasNextPage endCursor }
            nodes { id body url createdAt author { login avatarUrl } }
          } }
        }
        """)
        _ = try result.reviewThreads.pageInfo.nextCursor(after: after)
        for thread in result.reviewThreads.nodes { _ = try thread.comments.pageInfo.nextCursor() }
        return result.reviewThreads
    }

    public func replies(threadID: String, after: String? = nil) async throws -> PRConnection<PRComment> {
        struct Variables: Encodable { let id: String; let after: String? }
        struct Result: Decodable { let node: ThreadNode? }
        struct ThreadNode: Decodable { let comments: PRConnection<PRComment> }
        let result: Result = try await client.graphQL(query: """
        query PRReplies($id: ID!, $after: String) {
          node(id: $id) { ... on PullRequestReviewThread {
            comments(first: 50, after: $after) {
              pageInfo { hasNextPage endCursor }
              nodes { id body url createdAt author { login avatarUrl } }
            }
          } }
        }
        """, variables: Variables(id: threadID, after: after))
        guard let comments = result.node?.comments else { throw missingPullRequest() }
        _ = try comments.pageInfo.nextCursor(after: after)
        return comments
    }

    private func pullRequest<T: Decodable>(_ address: PullRequestAddress, after: String?, fields: String) async throws -> T {
        let result: RepositoryResult<T> = try await client.graphQL(query: """
        query PRViewer($owner: String!, $name: String!, $number: Int!, $after: String) {
          repository(owner: $owner, name: $name) { pullRequest(number: $number) { \(fields) } }
        }
        """, variables: Variables(owner: address.repository.owner, name: address.repository.name, number: address.number, after: after))
        guard let pullRequest = result.repository?.pullRequest else { throw missingPullRequest() }
        return pullRequest
    }

    private func missingPullRequest() -> GitHubAPIClientError {
        .invalidResponse(message: "This pull request could not be loaded. Check repository access and sign in again if needed.")
    }

    private struct Variables: Encodable { let owner: String; let name: String; let number: Int; let after: String? }
    private struct RepositoryResult<T: Decodable>: Decodable { let repository: Repository<T>? }
    private struct Repository<T: Decodable>: Decodable { let pullRequest: T? }
    private struct ActivityResult: Decodable { let timelineItems: PRConnection<PRActivity> }
    private struct ThreadsResult: Decodable { let reviewThreads: PRConnection<PRThread> }
}
