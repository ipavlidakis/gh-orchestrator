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

public struct PRActor: Codable, Equatable, Sendable {
    public let login: String
    public let avatarUrl: URL?
    public let url: URL?
}

public struct PRReviewer: Decodable, Identifiable, Equatable, Sendable {
    public let id: String
    public let login: String
    public let name: String?
    public let avatarUrl: URL?
    public let url: URL?
}

public struct PRReviewRequest: Decodable, Identifiable, Sendable {
    public let id: String
    public let requestedReviewer: PRReviewer?
    public let isTeam: Bool

    private enum CodingKeys: String, CodingKey { case id, requestedReviewer }
    private enum ReviewerKeys: String, CodingKey { case type = "__typename" }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        if container.contains(.requestedReviewer), try !container.decodeNil(forKey: .requestedReviewer) {
            let reviewer = try container.nestedContainer(keyedBy: ReviewerKeys.self, forKey: .requestedReviewer)
            isTeam = try reviewer.decodeIfPresent(String.self, forKey: .type) == "Team"
            requestedReviewer = isTeam ? nil : try container.decode(PRReviewer.self, forKey: .requestedReviewer)
        } else {
            isTeam = false
            requestedReviewer = nil
        }
    }
}

public struct PRReviewersUpdate: Decodable, Sendable {
    public let id: String
    public let reviewRequests: PRConnection<PRReviewRequest>
}

public struct PRTextUpdate: Decodable, Sendable {
    public let id: String
    public let title: String
    public let body: String
    public let bodyHTML: String
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
    public let bodyHTML: String?
    public let url: URL
    public let createdAt: Date
    public let author: PRActor?
    public let pullRequestReview: ReviewReference?
    public var viewerCanReact: Bool?
    public var reactionGroups: [PRReactionGroup]?

    public struct ReviewReference: Decodable, Equatable, Sendable {
        public let id: String
    }
}

public enum PRReactionContent: String, Codable, CaseIterable, Sendable {
    case thumbsUp = "THUMBS_UP", thumbsDown = "THUMBS_DOWN", laugh = "LAUGH", hooray = "HOORAY"
    case confused = "CONFUSED", heart = "HEART", rocket = "ROCKET", eyes = "EYES"
}

public struct PRReactionGroup: Codable, Equatable, Sendable {
    public let content: PRReactionContent
    public let viewerHasReacted: Bool
    public let reactors: Reactors
    public struct Reactors: Codable, Equatable, Sendable { public let totalCount: Int }
}

public struct PRReactionSubject: Decodable, Sendable {
    public let id: String
    public let viewerCanReact: Bool
    public let reactionGroups: [PRReactionGroup]
}

public struct PRThread: Decodable, Identifiable, Sendable {
    public let id: String
    public let path: String
    public let line: Int?
    public var isResolved: Bool
    public let isOutdated: Bool
    public let viewerCanReply: Bool?
    public var viewerCanResolve: Bool?
    public var viewerCanUnresolve: Bool?
    public var comments: PRConnection<PRComment>
}

public struct PRThreadResolution: Decodable, Sendable {
    public let id: String
    public let isResolved: Bool
    public let viewerCanResolve: Bool
    public let viewerCanUnresolve: Bool
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
    public let id: String?
    public let locked: Bool?
    public let viewerCanUpdate: Bool?
    public var title: String
    public var body: String
    public var bodyHTML: String?
    public var state: String
    public let isDraft: Bool
    public let author: PRActor?
    public let createdAt: Date
    public let headRefName: String
    public let baseRefName: String
    public let additions: Int
    public let deletions: Int
    public let changedFiles: Int?
    public let mergeable: String
    public let reviewDecision: String?
    public let headRefOid: String?
    public let mergeStateStatus: String?
    public let isMergeQueueEnabled: Bool?
    public let viewerCanMergeAsAdmin: Bool?
    public let viewerCanEnableAutoMerge: Bool?
    public let viewerCanDisableAutoMerge: Bool?
    public let repository: PRMergeRepository?
    public var autoMergeRequest: PRAutoMergeRequest?
    public var reviewRequests: PRConnection<PRReviewRequest>?
    public let commits: CommitConnection

    public struct CommitConnection: Decodable, Sendable {
        public let totalCount: Int?
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

    public func canMerge(method: PRMergeMethod, bypassRules: Bool = false) -> Bool {
        guard state == "OPEN", !isDraft, mergeable == "MERGEABLE", isMergeQueueEnabled == false,
              repository?.canWrite == true, repository?.methods.contains(method) == true,
              id?.isEmpty == false, headRefOid?.isEmpty == false,
              !bypassRules || viewerCanMergeAsAdmin == true else { return false }
        return ["CLEAN", "HAS_HOOKS", "UNSTABLE"].contains(mergeStateStatus ?? "") ||
            (bypassRules && ["BLOCKED", "BEHIND"].contains(mergeStateStatus ?? ""))
    }

    public func canEnableAutoMerge(method: PRMergeMethod) -> Bool {
        state == "OPEN" && !isDraft && mergeable == "MERGEABLE" && isMergeQueueEnabled == false &&
            viewerCanEnableAutoMerge == true && repository?.autoMergeAllowed == true &&
            repository?.canWrite == true && repository?.methods.contains(method) == true && autoMergeRequest == nil &&
            id?.isEmpty == false && headRefOid?.isEmpty == false
    }
}

public enum PRMergeMethod: String, Codable, CaseIterable, Sendable { case merge = "MERGE", squash = "SQUASH", rebase = "REBASE" }
public enum PRMergeAction: Sendable { case merge, enableAutoMerge, disableAutoMerge }

public struct PRMergeRequest: Sendable {
    public let method: PRMergeMethod
    public let action: PRMergeAction
    public let expectedHeadOID: String
    public let expectedBaseRefName: String
    public let bypassRules: Bool
    public init(method: PRMergeMethod, action: PRMergeAction, expectedHeadOID: String, expectedBaseRefName: String, bypassRules: Bool = false) {
        self.method = method; self.action = action; self.expectedHeadOID = expectedHeadOID; self.bypassRules = bypassRules
        self.expectedBaseRefName = expectedBaseRefName
    }
}

public struct PRMergeRepository: Decodable, Sendable {
    public let mergeCommitAllowed: Bool
    public let squashMergeAllowed: Bool
    public let rebaseMergeAllowed: Bool
    public let autoMergeAllowed: Bool
    public let viewerPermission: String?
    public var canWrite: Bool { ["WRITE", "MAINTAIN", "ADMIN"].contains(viewerPermission ?? "") }
    public var methods: [PRMergeMethod] {
        PRMergeMethod.allCases.filter { method in
            switch method { case .merge: mergeCommitAllowed; case .squash: squashMergeAllowed; case .rebase: rebaseMergeAllowed }
        }
    }
}

public struct PRAutoMergeRequest: Decodable, Sendable { public let mergeMethod: PRMergeMethod }

public struct PRMergeUpdate: Decodable, Sendable {
    public let id: String
    public let state: String
    public let autoMergeRequest: PRAutoMergeRequest?
    private enum CodingKeys: String, CodingKey { case id, state, autoMergeRequest }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        state = try values.decode(String.self, forKey: .state)
        autoMergeRequest = try values.decode(PRAutoMergeRequest?.self, forKey: .autoMergeRequest)
    }
}

public struct PRDescriptionUpdate: Decodable, Sendable {
    public let id: String
    public let body: String
    public let bodyHTML: String
}

public struct PRDescriptionTask: Encodable, Sendable {
    public let offset: Int
    public let checked: Bool

    public static func items(in body: String) -> [Self] {
        // shortcut: ambiguous HTML stays read-only; use a full Markdown parser if those descriptions need editing.
        guard body.range(of: "<input", options: .caseInsensitive) == nil else { return [] }
        let task = try! NSRegularExpression(pattern: #"^[ \t]*(?:>[ \t]*)*(?:[-+*]|[0-9]{1,9}[.)])[ \t]+\[([ xX])\](?:[ \t]|$)"#)
        let fence = try! NSRegularExpression(pattern: #"^[ \t]*(?:>[ \t]*)*(?:(?:[-+*]|[0-9]{1,9}[.)])[ \t]+)?(`{3,}|~{3,})(.*)$"#)
        let comments = try! NSRegularExpression(pattern: #"<!--[\s\S]*?(?:-->|$)"#)
        let hidden = comments.matches(in: body, range: NSRange(body.startIndex..., in: body)).map(\.range)
        var activeFence: (String, Int)?
        var result: [Self] = []
        body.enumerateSubstrings(in: body.startIndex..., options: .byLines) { line, range, _, _ in
            guard let line else { return }
            let lineRange = NSRange(range, in: body)
            if hidden.contains(where: { NSIntersectionRange($0, lineRange).length > 0 }) { return }
            let full = NSRange(line.startIndex..., in: line)
            if let match = fence.firstMatch(in: line, range: full) {
                let marker = (line as NSString).substring(with: match.range(at: 1))
                let tail = (line as NSString).substring(with: match.range(at: 2))
                let character = String(marker.prefix(1))
                if let current = activeFence {
                    if character == current.0 && marker.count >= current.1 && tail.trimmingCharacters(in: .whitespaces).isEmpty { activeFence = nil }
                } else { activeFence = (character, marker.count) }
                return
            }
            guard activeFence == nil, let match = task.firstMatch(in: line, range: full) else { return }
            let marker = match.range(at: 1)
            result.append(Self(offset: lineRange.location + marker.location, checked: (line as NSString).substring(with: marker) != " "))
        }
        return result
    }
}

public struct PRActivity: Decodable, Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: String
    public let body: String
    public let bodyHTML: String?
    public let url: URL?
    public let createdAt: Date
    public let author: PRActor?
    public let state: String?
    public let reviewCommentCount: Int?
    public var viewerCanReact: Bool?
    public var reactionGroups: [PRReactionGroup]?

    private enum CodingKeys: String, CodingKey { case id, __typename, body, bodyHTML, url, createdAt, submittedAt, author, actor, state, commit, comments, viewerCanReact, reactionGroups }
    private struct ReviewComments: Decodable { let totalCount: Int }
    private struct Commit: Decodable {
        let oid: String
        let messageHeadline: String
        let committedDate: Date
        let url: URL
        let author: GitActor?
    }
    private struct GitActor: Decodable {
        let name: String?
        let avatarUrl: URL?
        let user: PRActor?
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(String.self, forKey: .__typename)
        bodyHTML = try c.decodeIfPresent(String.self, forKey: .bodyHTML)
        if let commit = try c.decodeIfPresent(Commit.self, forKey: .commit) {
            id = commit.oid
            body = commit.messageHeadline
            createdAt = commit.committedDate
            url = commit.url
            author = commit.author?.user ?? commit.author?.name.map { PRActor(login: $0, avatarUrl: commit.author?.avatarUrl, url: nil) }
        } else {
            id = try c.decode(String.self, forKey: .id)
            body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
            createdAt = try c.decodeIfPresent(Date.self, forKey: .submittedAt) ?? c.decode(Date.self, forKey: .createdAt)
            url = try c.decodeIfPresent(URL.self, forKey: .url)
            author = try c.decodeIfPresent(PRActor.self, forKey: .author) ?? c.decodeIfPresent(PRActor.self, forKey: .actor)
        }
        state = try c.decodeIfPresent(String.self, forKey: .state)
        reviewCommentCount = try c.decodeIfPresent(ReviewComments.self, forKey: .comments)?.totalCount
        viewerCanReact = try c.decodeIfPresent(Bool.self, forKey: .viewerCanReact)
        reactionGroups = try c.decodeIfPresent([PRReactionGroup].self, forKey: .reactionGroups)
    }

    public init(comment: PRComment) {
        id = comment.id; kind = "IssueComment"; body = comment.body; bodyHTML = comment.bodyHTML
        url = comment.url; createdAt = comment.createdAt; author = comment.author; state = nil; reviewCommentCount = nil
        viewerCanReact = comment.viewerCanReact; reactionGroups = comment.reactionGroups
    }
}
