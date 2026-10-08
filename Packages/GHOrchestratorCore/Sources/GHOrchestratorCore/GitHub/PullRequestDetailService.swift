import Foundation

public protocol PullRequestDetailLoading: Sendable {
    func summary(_ address: PullRequestAddress, checksAfter: String?) async throws -> PRSummary
    func activity(_ address: PullRequestAddress, after: String?) async throws -> PRConnection<PRActivity>
    func threads(_ address: PullRequestAddress, after: String?) async throws -> PRConnection<PRThread>
    func replies(threadID: String, after: String?) async throws -> PRConnection<PRComment>
    func addComment(pullRequestID: String, body: String) async throws -> PRComment
    func reply(threadID: String, body: String) async throws -> PRComment
    func setResolved(threadID: String, resolved: Bool) async throws -> PRThreadResolution
    func setReaction(subjectID: String, content: PRReactionContent, added: Bool) async throws -> PRReactionSubject
}

public struct PullRequestDetailService: PullRequestDetailLoading {
    private let client: any GitHubAPIClient
    public init(client: any GitHubAPIClient) { self.client = client }

    public func summary(_ address: PullRequestAddress, checksAfter: String? = nil) async throws -> PRSummary {
        let result: PRSummary = try await pullRequest(address, after: checksAfter, fields: """
        id locked title body bodyHTML state isDraft createdAt author { login avatarUrl(size: 56) url }
        headRefName baseRefName additions deletions mergeable reviewDecision
        commits(last: 1) { totalCount nodes { commit { statusCheckRollup {
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
            ... on IssueComment { \(Self.commentFields) }
            ... on PullRequestReview { \(Self.commentFields) submittedAt state comments { totalCount } }
            ... on PullRequestCommit { commit { oid messageHeadline committedDate url author { name avatarUrl(size: 56) user { login avatarUrl(size: 56) url } } } }
            ... on MergedEvent { id createdAt actor { login avatarUrl(size: 56) url } }
            ... on ClosedEvent { id createdAt actor { login avatarUrl(size: 56) url } }
            ... on ReopenedEvent { id createdAt actor { login avatarUrl(size: 56) url } }
            ... on ReadyForReviewEvent { id createdAt actor { login avatarUrl(size: 56) url } }
            ... on ConvertToDraftEvent { id createdAt actor { login avatarUrl(size: 56) url } }
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
          nodes { id path line isResolved isOutdated viewerCanReply viewerCanResolve viewerCanUnresolve comments(first: 20) {
            pageInfo { hasNextPage endCursor }
            nodes { \(Self.reviewCommentFields) }
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
              nodes { \(Self.reviewCommentFields) }
            }
          } }
        }
        """, variables: Variables(id: threadID, after: after))
        guard let comments = result.node?.comments else { throw missingPullRequest() }
        _ = try comments.pageInfo.nextCursor(after: after)
        return comments
    }

    public func addComment(pullRequestID: String, body: String) async throws -> PRComment {
        struct Variables: Encodable { let id: String; let body: String }
        struct Result: Decodable { let addComment: Payload? }
        struct Payload: Decodable { let commentEdge: Edge? }
        struct Edge: Decodable { let node: PRComment? }
        let result: Result = try await client.graphQL(query: """
        mutation PRComment($id: ID!, $body: String!) {
          addComment(input: {subjectId: $id, body: $body}) {
            commentEdge { node { \(Self.commentFields) } }
          }
        }
        """, variables: Variables(id: pullRequestID, body: body))
        guard let comment = result.addComment?.commentEdge?.node else { throw missingMutation() }
        return comment
    }

    public func reply(threadID: String, body: String) async throws -> PRComment {
        struct Variables: Encodable { let id: String; let body: String }
        struct Result: Decodable { let addPullRequestReviewThreadReply: Payload? }
        struct Payload: Decodable { let comment: PRComment? }
        let result: Result = try await client.graphQL(query: """
        mutation PRReply($id: ID!, $body: String!) {
          addPullRequestReviewThreadReply(input: {pullRequestReviewThreadId: $id, body: $body}) {
            comment { \(Self.reviewCommentFields) }
          }
        }
        """, variables: Variables(id: threadID, body: body))
        guard let comment = result.addPullRequestReviewThreadReply?.comment else { throw missingMutation() }
        return comment
    }

    public func setResolved(threadID: String, resolved: Bool) async throws -> PRThreadResolution {
        struct Variables: Encodable { let id: String }
        struct Result: Decodable { let action: Payload? }
        struct Payload: Decodable { let thread: PRThreadResolution? }
        let mutation = resolved ? "resolveReviewThread" : "unresolveReviewThread"
        let result: Result = try await client.graphQL(query: """
        mutation PRResolve($id: ID!) {
          action: \(mutation)(input: {threadId: $id}) {
            thread { id isResolved viewerCanResolve viewerCanUnresolve }
          }
        }
        """, variables: Variables(id: threadID))
        guard let thread = result.action?.thread, thread.id == threadID else { throw missingMutation() }
        return thread
    }

    public func setReaction(subjectID: String, content: PRReactionContent, added: Bool) async throws -> PRReactionSubject {
        struct Variables: Encodable { let id: String; let content: PRReactionContent }
        struct Result: Decodable { let action: Payload? }
        struct Payload: Decodable { let subject: PRReactionSubject? }
        let mutation = added ? "addReaction" : "removeReaction"
        let result: Result = try await client.graphQL(query: """
        mutation PRReaction($id: ID!, $content: ReactionContent!) {
          action: \(mutation)(input: {subjectId: $id, content: $content}) {
            subject { id \(Self.reactionFields) }
          }
        }
        """, variables: Variables(id: subjectID, content: content))
        guard let subject = result.action?.subject, subject.id == subjectID else { throw missingMutation() }
        return subject
    }

    private static let reactionFields = "viewerCanReact reactionGroups { content viewerHasReacted reactors { totalCount } }"
    private static let commentFields = "id body bodyHTML url createdAt author { login avatarUrl(size: 56) url } \(reactionFields)"
    private static let reviewCommentFields = "\(commentFields) pullRequestReview { id }"
    private func missingMutation() -> GitHubAPIClientError {
        .invalidResponse(message: "GitHub did not confirm this action. Refresh the conversation before trying again.")
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
