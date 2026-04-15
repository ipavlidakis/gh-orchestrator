import Foundation

public enum ReviewStatus: String, Codable, CaseIterable, Sendable {
    case none
    case reviewRequired
    case approved
    case changesRequested
}

public enum CheckRollupState: String, Codable, CaseIterable, Sendable {
    case none
    case pending
    case passing
    case failing
}

public struct ExternalCheckItem: Codable, Equatable, Hashable, Sendable {
    public let name: String
    public let status: String
    public let conclusion: String?
    public let detailsURL: URL?
    public let summary: String?

    public init(
        name: String,
        status: String,
        conclusion: String? = nil,
        detailsURL: URL? = nil,
        summary: String? = nil
    ) {
        self.name = name
        self.status = status
        self.conclusion = conclusion
        self.detailsURL = detailsURL
        self.summary = summary
    }
}

public struct ActionStepItem: Codable, Equatable, Hashable, Sendable {
    public let number: Int
    public let name: String
    public let status: String
    public let conclusion: String?
    public let startedAt: Date?
    public let completedAt: Date?
    public let detailsURL: URL?

    public init(
        number: Int,
        name: String,
        status: String,
        conclusion: String? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        detailsURL: URL? = nil
    ) {
        self.number = number
        self.name = name
        self.status = status
        self.conclusion = conclusion
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.detailsURL = detailsURL
    }
}

public struct ActionJobItem: Codable, Equatable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let status: String
    public let conclusion: String?
    public let createdAt: Date?
    public let startedAt: Date?
    public let completedAt: Date?
    public let detailsURL: URL?
    public let steps: [ActionStepItem]

    public init(
        id: Int,
        name: String,
        status: String,
        conclusion: String? = nil,
        createdAt: Date? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        detailsURL: URL? = nil,
        steps: [ActionStepItem] = []
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.conclusion = conclusion
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.detailsURL = detailsURL
        self.steps = steps
    }
}

public struct WorkflowRunItem: Codable, Equatable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let status: String
    public let conclusion: String?
    public let detailsURL: URL?
    public let jobs: [ActionJobItem]

    public init(
        id: Int,
        name: String,
        status: String,
        conclusion: String? = nil,
        detailsURL: URL? = nil,
        jobs: [ActionJobItem] = []
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.conclusion = conclusion
        self.detailsURL = detailsURL
        self.jobs = jobs
    }
}

public struct UnresolvedReviewCommentItem: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let url: URL
    public let authorLogin: String
    public let bodyText: String
    public let filePath: String

    public var id: String {
        url.absoluteString
    }

    public init(
        url: URL,
        authorLogin: String,
        bodyText: String,
        filePath: String
    ) {
        self.url = url
        self.authorLogin = authorLogin
        self.bodyText = bodyText
        self.filePath = filePath
    }
}

public struct PullRequestItem: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let repository: ObservedRepository
    public let number: Int
    public let title: String
    public let url: URL
    public let authorLogin: String?
    public let isDraft: Bool
    public let updatedAt: Date
    public let reviewStatus: ReviewStatus
    public let unresolvedReviewThreadCount: Int
    public let unresolvedReviewComments: [UnresolvedReviewCommentItem]
    public let checkRollupState: CheckRollupState
    public let externalChecks: [ExternalCheckItem]
    public let workflowRuns: [WorkflowRunItem]

    public var id: String {
        "\(repository.normalizedLookupKey)#\(number)"
    }

    public init(
        repository: ObservedRepository,
        number: Int,
        title: String,
        url: URL,
        authorLogin: String? = nil,
        isDraft: Bool,
        updatedAt: Date,
        reviewStatus: ReviewStatus,
        unresolvedReviewThreadCount: Int,
        unresolvedReviewComments: [UnresolvedReviewCommentItem] = [],
        checkRollupState: CheckRollupState,
        externalChecks: [ExternalCheckItem] = [],
        workflowRuns: [WorkflowRunItem] = []
    ) {
        self.repository = repository
        self.number = number
        self.title = title
        self.url = url
        self.authorLogin = authorLogin
        self.isDraft = isDraft
        self.updatedAt = updatedAt
        self.reviewStatus = reviewStatus
        self.unresolvedReviewThreadCount = unresolvedReviewThreadCount
        self.unresolvedReviewComments = unresolvedReviewComments
        self.checkRollupState = checkRollupState
        self.externalChecks = externalChecks
        self.workflowRuns = workflowRuns
    }
}

public struct RepositorySection: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let repository: ObservedRepository
    public let pullRequests: [PullRequestItem]

    public var id: String {
        repository.normalizedLookupKey
    }

    public init(repository: ObservedRepository, pullRequests: [PullRequestItem]) {
        self.repository = repository
        self.pullRequests = pullRequests
    }
}
