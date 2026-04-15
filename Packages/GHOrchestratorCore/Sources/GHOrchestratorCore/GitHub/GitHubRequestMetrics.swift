import Foundation

public protocol GitHubRequestMetricsRecording: Sendable {
    func record(_ request: GitHubRequestRecord) async
}

public struct GitHubRequestRecord: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let method: String
    public let endpoint: String
    public let statusCode: Int?
    public let rateLimit: GitHubRateLimitStatus?
    public let errorMessage: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        method: String,
        endpoint: String,
        statusCode: Int?,
        rateLimit: GitHubRateLimitStatus?,
        errorMessage: String?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.method = method
        self.endpoint = endpoint
        self.statusCode = statusCode
        self.rateLimit = rateLimit
        self.errorMessage = errorMessage
    }
}

public struct GitHubRateLimitStatus: Equatable, Sendable {
    public let limit: Int
    public let remaining: Int
    public let used: Int
    public let resetDate: Date
    public let resource: String

    public init(
        limit: Int,
        remaining: Int,
        used: Int,
        resetDate: Date,
        resource: String
    ) {
        self.limit = limit
        self.remaining = remaining
        self.used = used
        self.resetDate = resetDate
        self.resource = resource
    }
}
