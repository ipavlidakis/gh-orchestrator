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
    func setDescriptionTask(_ address: PullRequestAddress, offset: Int, checked: Bool, expectedBody: String) async throws -> PRDescriptionUpdate
    func updateText(_ address: PullRequestAddress, title: String, body: String, expectedTitle: String, expectedBody: String) async throws -> PRTextUpdate
    func reviewers(_ address: PullRequestAddress, query: String, after: String?) async throws -> PRConnection<PRReviewer>
    func requestReviewers(_ address: PullRequestAddress, userIDs: [String]) async throws -> PRReviewersUpdate
    func merge(_ address: PullRequestAddress, request: PRMergeRequest) async throws -> PRMergeUpdate
}

public struct PullRequestDetailService: PullRequestDetailLoading {
    private let client: any GitHubAPIClient
    public init(client: any GitHubAPIClient) { self.client = client }

    public func summary(_ address: PullRequestAddress, checksAfter: String? = nil) async throws -> PRSummary {
        let result: PRSummary = try await pullRequest(address, after: checksAfter, fields: """
        id locked viewerCanUpdate title body bodyHTML state isDraft createdAt author { login avatarUrl(size: 56) url }
        headRefName baseRefName additions deletions changedFiles mergeable reviewDecision
        headRefOid mergeStateStatus isMergeQueueEnabled viewerCanMergeAsAdmin viewerCanEnableAutoMerge viewerCanDisableAutoMerge
        repository { mergeCommitAllowed squashMergeAllowed rebaseMergeAllowed autoMergeAllowed viewerPermission }
        autoMergeRequest { mergeMethod }
        \(Self.reviewRequestsFields)
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

    public func setDescriptionTask(_ address: PullRequestAddress, offset: Int, checked: Bool, expectedBody: String) async throws -> PRDescriptionUpdate {
        let current = try await summary(address)
        guard current.viewerCanUpdate == true, let id = current.id else {
            throw GitHubAPIClientError.invalidResponse(message: "You cannot edit this pull request description. Check your repository access on GitHub.")
        }
        guard current.body.utf8.elementsEqual(expectedBody.utf8) else {
            throw GitHubAPIClientError.invalidResponse(message: "The description changed on GitHub. Refresh before changing a checkbox.")
        }
        guard PRDescriptionTask.items(in: current.body).contains(where: { $0.offset == offset }) else {
            throw GitHubAPIClientError.invalidResponse(message: "This checkbox could not be matched to the description. Refresh or edit it on GitHub.")
        }
        try Task.checkCancellation()
        let body = (current.body as NSString).replacingCharacters(in: NSRange(location: offset, length: 1), with: checked ? "x" : " ")
        struct Variables: Encodable { let id: String; let body: String }
        struct Result: Decodable { let updatePullRequest: Payload? }
        struct Payload: Decodable { let pullRequest: PRDescriptionUpdate? }
        let result: Result = try await client.graphQL(query: """
        mutation PRDescriptionTask($id: ID!, $body: String!) {
          updatePullRequest(input: {pullRequestId: $id, body: $body}) {
            pullRequest { id body bodyHTML }
          }
        }
        """, variables: Variables(id: id, body: body))
        guard let updated = result.updatePullRequest?.pullRequest, updated.id == id else { throw missingMutation() }
        return updated
    }

    public func updateText(_ address: PullRequestAddress, title: String, body: String, expectedTitle: String, expectedBody: String) async throws -> PRTextUpdate {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitHubAPIClientError.invalidResponse(message: "Enter a pull request title before saving.")
        }
        let current = try await summary(address)
        guard current.viewerCanUpdate == true, let id = current.id else {
            throw GitHubAPIClientError.invalidResponse(message: "You cannot edit this pull request. Check your repository access on GitHub.")
        }
        guard current.title.utf8.elementsEqual(expectedTitle.utf8), current.body.utf8.elementsEqual(expectedBody.utf8) else {
            throw GitHubAPIClientError.invalidResponse(message: "The title or description changed on GitHub. Your draft is preserved; refresh and compare before saving again.")
        }
        try Task.checkCancellation()
        struct Variables: Encodable { let id: String; let title: String; let body: String }
        struct Result: Decodable { let updatePullRequest: Payload? }
        struct Payload: Decodable { let pullRequest: PRTextUpdate? }
        let result: Result = try await client.graphQL(query: """
        mutation PRText($id: ID!, $title: String!, $body: String!) {
          updatePullRequest(input: {pullRequestId: $id, title: $title, body: $body}) {
            pullRequest { id title body bodyHTML }
          }
        }
        """, variables: Variables(id: id, title: title, body: body))
        guard let updated = result.updatePullRequest?.pullRequest, updated.id == id else { throw missingMutation() }
        return updated
    }

    public func reviewers(_ address: PullRequestAddress, query: String, after: String?) async throws -> PRConnection<PRReviewer> {
        struct Variables: Encodable { let owner: String; let name: String; let query: String; let after: String? }
        struct Result: Decodable { let repository: Repository? }
        struct Repository: Decodable { let assignableUsers: PRConnection<PRReviewer> }
        let result: Result = try await client.graphQL(query: """
        query PRReviewers($owner: String!, $name: String!, $query: String!, $after: String) {
          repository(owner: $owner, name: $name) {
            assignableUsers(first: 30, query: $query, after: $after) {
              nodes { \(Self.reviewerFields) } pageInfo { hasNextPage endCursor }
            }
          }
        }
        """, variables: Variables(owner: address.repository.owner, name: address.repository.name, query: query, after: after))
        guard let page = result.repository?.assignableUsers else { throw missingPullRequest() }
        _ = try page.pageInfo.nextCursor(after: after)
        return page
    }

    public func requestReviewers(_ address: PullRequestAddress, userIDs: [String]) async throws -> PRReviewersUpdate {
        guard !userIDs.isEmpty, userIDs.allSatisfy({ !$0.isEmpty }), Set(userIDs).count == userIDs.count else {
            throw GitHubAPIClientError.invalidResponse(message: "Select reviewers before requesting a review.")
        }
        let current = try await summary(address)
        guard current.viewerCanUpdate == true, let id = current.id else {
            throw GitHubAPIClientError.invalidResponse(message: "You cannot request reviewers for this pull request. Check your repository access on GitHub.")
        }
        try Task.checkCancellation()
        struct Variables: Encodable { let id: String; let users: [String] }
        struct Result: Decodable { let requestReviews: Payload? }
        struct Payload: Decodable { let pullRequest: PRReviewersUpdate? }
        let result: Result = try await client.graphQL(query: """
        mutation PRRequestReviewers($id: ID!, $users: [ID!]!) {
          requestReviews(input: {pullRequestId: $id, userIds: $users, union: true}) {
            pullRequest { id \(Self.reviewRequestsFields) }
          }
        }
        """, variables: Variables(id: id, users: userIDs))
        guard let updated = result.requestReviews?.pullRequest, updated.id == id else { throw missingMutation() }
        return updated
    }

    public func merge(_ address: PullRequestAddress, request: PRMergeRequest) async throws -> PRMergeUpdate {
        let current = try await summary(address)
        guard let id = current.id, !id.isEmpty, !request.expectedHeadOID.isEmpty, current.headRefOid == request.expectedHeadOID, current.baseRefName == request.expectedBaseRefName else {
            throw GitHubAPIClientError.invalidResponse(message: "The pull request head or base branch changed. Refresh and review it before confirming again.")
        }
        let mutation: String, inputType: String, permitted: Bool
        switch request.action {
        case .merge:
            (mutation, inputType, permitted) = ("mergePullRequest", "MergePullRequestInput", current.canMerge(method: request.method, bypassRules: request.bypassRules))
        case .enableAutoMerge:
            (mutation, inputType, permitted) = ("enablePullRequestAutoMerge", "EnablePullRequestAutoMergeInput", !request.bypassRules && current.canEnableAutoMerge(method: request.method))
        case .disableAutoMerge:
            (mutation, inputType, permitted) = ("disablePullRequestAutoMerge", "DisablePullRequestAutoMergeInput", !request.bypassRules && current.state == "OPEN" && current.viewerCanDisableAutoMerge == true && current.autoMergeRequest?.mergeMethod == request.method)
        }
        guard permitted else {
            throw GitHubAPIClientError.invalidResponse(message: "This action is no longer available. Refresh merge status to check permissions, repository methods and requirements.")
        }
        try Task.checkCancellation()
        struct Input: Encodable { let pullRequestId: String; let mergeMethod: PRMergeMethod?; let expectedHeadOid: String? }
        struct Variables: Encodable { let input: Input }
        struct Result: Decodable { let action: Payload? }
        struct Payload: Decodable { let pullRequest: PRMergeUpdate? }
        let disabling = request.action == .disableAutoMerge
        let result: Result = try await client.graphQL(query: """
        mutation PRMerge($input: \(inputType)!) {
          action: \(mutation)(input: $input) { pullRequest { id state autoMergeRequest { mergeMethod } } }
        }
        """, variables: Variables(input: Input(pullRequestId: id, mergeMethod: disabling ? nil : request.method, expectedHeadOid: disabling ? nil : request.expectedHeadOID)))
        guard let updated = result.action?.pullRequest, updated.id == id else { throw missingMutation() }
        let confirmed: Bool
        switch request.action {
        case .merge: confirmed = updated.state == "MERGED"
        case .enableAutoMerge: confirmed = updated.state == "MERGED" || (updated.state == "OPEN" && updated.autoMergeRequest?.mergeMethod == request.method)
        case .disableAutoMerge: confirmed = updated.state == "OPEN" && updated.autoMergeRequest == nil
        }
        guard confirmed else { throw missingMutation() }
        return updated
    }

    private static let reviewerFields = "id login name avatarUrl(size: 56) url"
    private static let reviewRequestsFields = """
    reviewRequests(first: 100) {
      pageInfo { hasNextPage endCursor }
      nodes { id requestedReviewer {
        __typename
        ... on User { \(reviewerFields) }
        ... on Bot { id login avatarUrl(size: 56) url }
      } }
    }
    """

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
