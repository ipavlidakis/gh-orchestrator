import Foundation

public protocol PullRequestDiffLoading: Sendable {
    func diffSnapshot(_ address: PullRequestAddress, after: String?) async throws -> PRDiffSnapshot
    func diffRevision(_ address: PullRequestAddress) async throws -> PRDiffRevision
    func diffPatches(_ address: PullRequestAddress, page: Int) async throws -> [PRDiffPatch]
    func setFileViewed(_ address: PullRequestAddress, path: String, viewed: Bool, expected: PRDiffRevision) async throws
    func addLineComment(_ address: PullRequestAddress, selection: PRDiffLineSelection, body: String, expected: PRDiffRevision) async throws -> PRComment
}

public extension PullRequestDiffLoading {
    func diffRevision(_ address: PullRequestAddress) async throws -> PRDiffRevision {
        try await diffSnapshot(address, after: nil).revision
    }
}

public struct PRDiffLineSelection: Hashable, Sendable {
    public enum Side: String, Sendable, Encodable { case left = "LEFT", right = "RIGHT" }
    public let path: String
    public let start: Int
    public let end: Int
    public let startSide: Side
    public let endSide: Side
    public var isRange: Bool { start != end || startSide != endSide }
    public init?(path: String, start: Int, end: Int, startSide: Side, endSide: Side) {
        guard !path.isEmpty, start > 0, end > 0, startSide != endSide || end >= start else { return nil }
        self.path = path; self.start = start; self.end = end; self.startSide = startSide; self.endSide = endSide
    }
}

public struct PRDiffRevision: Decodable, Equatable, Sendable {
    public let id: String
    public let baseRefOid: String
    public let headRefOid: String
}

public struct PRDiffSnapshot: Decodable, Sendable {
    public let id: String
    public let baseRefOid: String
    public let headRefOid: String
    public let changedFiles: Int
    public let files: PRConnection<PRDiffFile>
    public var revision: PRDiffRevision { PRDiffRevision(id: id, baseRefOid: baseRefOid, headRefOid: headRefOid) }
}

public struct PRDiffFile: Codable, Identifiable, Sendable {
    public let path: String
    public let additions: Int
    public let deletions: Int
    public let changeType: String
    public let viewerViewedState: String
    public var id: String { path }
    public var isViewed: Bool { viewerViewedState == "VIEWED" }
    public var fileExtension: String { (path as NSString).pathExtension.lowercased() }
}

public struct PRDiffPatch: Decodable, Encodable, Sendable {
    public static let pageSize = 100
    public let filename: String
    public let previousFilename: String?
    public let sha: String
    public let patch: String?
    public let unavailable: String?
    private enum CodingKeys: String, CodingKey { case filename, previousFilename = "previous_filename", sha, patch, unavailable }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        filename = try c.decode(String.self, forKey: .filename)
        previousFilename = try c.decodeIfPresent(String.self, forKey: .previousFilename)
        sha = try c.decode(String.self, forKey: .sha)
        let text = try c.decodeIfPresent(String.self, forKey: .patch)
        // shortcut: oversized API patches stay on GitHub; add streamed full-file loading if local large-file review is required.
        if let text, text.utf8.count > 1_048_576 || text.utf8.lazy.filter({ $0 == 10 }).prefix(20_001).count > 20_000 {
            patch = nil; unavailable = "This diff exceeds the local display limit. Open it on GitHub."
        } else {
            patch = text
            unavailable = text == nil ? "GitHub did not supply a text patch for this file." : nil
        }
    }
}
