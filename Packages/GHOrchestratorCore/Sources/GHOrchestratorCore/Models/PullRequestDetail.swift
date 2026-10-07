import Foundation

public struct PullRequestAddress: Hashable, Sendable {
    public let repository: ObservedRepository
    public let number: Int
    public var url: URL { URL(string: "https://github.com/\(repository.fullName)/pull/\(number)")! }

    public init?(url: URL) {
        let parts = url.path.split(separator: "/")
        guard url.scheme == "https", url.host?.lowercased() == "github.com",
              url.user == nil, url.password == nil, url.port == nil,
              parts.count >= 4, parts[2] == "pull",
              let number = Int(parts[3]), number > 0,
              parts[0].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
              parts[1].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) })
        else { return nil }
        self.repository = ObservedRepository(owner: String(parts[0]).lowercased(), name: String(parts[1]).lowercased())
        self.number = number
    }
}

public struct PRActor: Decodable, Equatable, Sendable {
    public let login: String
    public let avatarUrl: URL?
}

public struct PRPageInfo: Decodable, Equatable, Sendable {
    public let hasNextPage: Bool
    public let endCursor: String?

    public func nextCursor(after: String? = nil) throws -> String? {
        guard hasNextPage else { return nil }
        guard let endCursor, !endCursor.isEmpty, endCursor != after else {
            throw GitHubAPIClientError.invalidResponse(message: "GitHub omitted the next page cursor. Retry loading this page.")
        }
        return endCursor
    }
}

public struct PRConnection<Node: Decodable & Sendable>: Decodable, Sendable {
    public let nodes: [Node]
    public let pageInfo: PRPageInfo
    public init(nodes: [Node], pageInfo: PRPageInfo) { self.nodes = nodes; self.pageInfo = pageInfo }
    private enum CodingKeys: String, CodingKey { case nodes, pageInfo }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nodes = try c.decode([Node?].self, forKey: .nodes).compactMap { $0 }
        pageInfo = try c.decode(PRPageInfo.self, forKey: .pageInfo)
    }
}

public struct PRComment: Decodable, Identifiable, Equatable, Sendable {
    public let id: String
    public let body: String
    public let url: URL
    public let createdAt: Date
    public let author: PRActor?
}

public struct PRThread: Decodable, Identifiable, Sendable {
    public let id: String
    public let path: String
    public let line: Int?
    public let isResolved: Bool
    public let isOutdated: Bool
    public var comments: PRConnection<PRComment>
}

public struct PRCheck: Decodable, Identifiable, Sendable {
    public let name: String
    public let status: String
    public let conclusion: String?
    public let url: URL?
    public var id: String { "\(name):\(url?.absoluteString ?? "")" }

    private enum CodingKeys: String, CodingKey { case name, context, status, state, conclusion, detailsUrl, targetUrl }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? c.decode(String.self, forKey: .context)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "COMPLETED"
        conclusion = try c.decodeIfPresent(String.self, forKey: .conclusion) ?? c.decodeIfPresent(String.self, forKey: .state)
        url = try c.decodeIfPresent(URL.self, forKey: .detailsUrl) ?? c.decodeIfPresent(URL.self, forKey: .targetUrl)
    }
}

public struct PRSummary: Decodable, Sendable {
    public let title: String
    public let body: String
    public let state: String
    public let isDraft: Bool
    public let author: PRActor?
    public let createdAt: Date
    public let headRefName: String
    public let baseRefName: String
    public let additions: Int
    public let deletions: Int
    public let mergeable: String
    public let reviewDecision: String?
    public let commits: CommitConnection

    public struct CommitConnection: Decodable, Sendable {
        public let nodes: [CommitNode]
    }
    public struct CommitNode: Decodable, Sendable {
        public let commit: Commit
    }
    public struct Commit: Decodable, Sendable {
        public let statusCheckRollup: Rollup?
    }
    public struct Rollup: Decodable, Sendable {
        public let contexts: PRConnection<PRCheck>
    }
    public var checks: [PRCheck] { commits.nodes.first?.commit.statusCheckRollup?.contexts.nodes ?? [] }
    public var checksPageInfo: PRPageInfo? { commits.nodes.first?.commit.statusCheckRollup?.contexts.pageInfo }
}

public struct PRActivity: Decodable, Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: String
    public let body: String
    public let url: URL?
    public let createdAt: Date
    public let author: PRActor?
    public let state: String?

    private enum CodingKeys: String, CodingKey { case id, __typename, body, url, createdAt, submittedAt, author, actor, state, commit }
    private struct Commit: Decodable {
        let oid: String
        let messageHeadline: String
        let committedDate: Date
        let url: URL
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(String.self, forKey: .__typename)
        if let commit = try c.decodeIfPresent(Commit.self, forKey: .commit) {
            id = commit.oid
            body = commit.messageHeadline
            createdAt = commit.committedDate
            url = commit.url
        } else {
            id = try c.decode(String.self, forKey: .id)
            body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
            createdAt = try c.decodeIfPresent(Date.self, forKey: .submittedAt) ?? c.decode(Date.self, forKey: .createdAt)
            url = try c.decodeIfPresent(URL.self, forKey: .url)
        }
        author = try c.decodeIfPresent(PRActor.self, forKey: .author) ?? c.decodeIfPresent(PRActor.self, forKey: .actor)
        state = try c.decodeIfPresent(String.self, forKey: .state)
    }
}
