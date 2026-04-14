import Foundation

public struct RepositoryPullRequestSnapshot: Equatable, Sendable {
    public let repository: ObservedRepository
    public let pullRequests: [PullRequestSnapshotItem]

    public init(repository: ObservedRepository, pullRequests: [PullRequestSnapshotItem]) {
        self.repository = repository
        self.pullRequests = pullRequests
    }
}

public struct PullRequestSnapshotItem: Equatable, Identifiable, Sendable {
    public let repository: ObservedRepository
    public let number: Int
    public let title: String
    public let url: URL
    public let isDraft: Bool
    public let updatedAt: Date
    public let reviewStatus: ReviewStatus
    public let unresolvedReviewThreadCount: Int
    public let checkRollupState: CheckRollupState
    public let checkRuns: [CheckRunSnapshot]
    public let statusContexts: [StatusContextSnapshot]

    public var id: String {
        "\(repository.normalizedLookupKey)#\(number)"
    }

    public init(
        repository: ObservedRepository,
        number: Int,
        title: String,
        url: URL,
        isDraft: Bool,
        updatedAt: Date,
        reviewStatus: ReviewStatus,
        unresolvedReviewThreadCount: Int,
        checkRollupState: CheckRollupState,
        checkRuns: [CheckRunSnapshot],
        statusContexts: [StatusContextSnapshot]
    ) {
        self.repository = repository
        self.number = number
        self.title = title
        self.url = url
        self.isDraft = isDraft
        self.updatedAt = updatedAt
        self.reviewStatus = reviewStatus
        self.unresolvedReviewThreadCount = unresolvedReviewThreadCount
        self.checkRollupState = checkRollupState
        self.checkRuns = checkRuns
        self.statusContexts = statusContexts
    }
}

public struct CheckRunSnapshot: Equatable, Sendable {
    public let name: String
    public let status: String
    public let conclusion: String?
    public let detailsURL: URL?
    public let appName: String?
    public let appSlug: String?
    public let workflowRun: WorkflowRunReferenceSnapshot?

    public init(
        name: String,
        status: String,
        conclusion: String? = nil,
        detailsURL: URL? = nil,
        appName: String? = nil,
        appSlug: String? = nil,
        workflowRun: WorkflowRunReferenceSnapshot? = nil
    ) {
        self.name = name
        self.status = status
        self.conclusion = conclusion
        self.detailsURL = detailsURL
        self.appName = appName
        self.appSlug = appSlug
        self.workflowRun = workflowRun
    }
}

public struct WorkflowRunReferenceSnapshot: Equatable, Sendable {
    public let id: Int
    public let url: URL?
    public let workflowName: String?

    public init(id: Int, url: URL? = nil, workflowName: String? = nil) {
        self.id = id
        self.url = url
        self.workflowName = workflowName
    }
}

public struct StatusContextSnapshot: Equatable, Sendable {
    public let context: String
    public let state: String
    public let targetURL: URL?
    public let description: String?

    public init(
        context: String,
        state: String,
        targetURL: URL? = nil,
        description: String? = nil
    ) {
        self.context = context
        self.state = state
        self.targetURL = targetURL
        self.description = description
    }
}
