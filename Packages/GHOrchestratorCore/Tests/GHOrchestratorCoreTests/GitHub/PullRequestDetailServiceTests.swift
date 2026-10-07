import Foundation
import XCTest
@testable import GHOrchestratorCore

final class PullRequestDetailServiceTests: XCTestCase {
    func testPRRoutingAcceptsCommentsAndRejectsNonPRAndUntrustedURLs() throws {
        let address = try XCTUnwrap(PullRequestAddress(url: URL(string: "https://github.com/Orbit/Nova/pull/42#discussion_r123")!))
        XCTAssertEqual(address.repository.fullName, "orbit/nova")
        XCTAssertEqual(address.number, 42)
        for raw in ["http://github.com/a/b/pull/1", "https://github.com.evil/a/b/pull/1", "https://github.com/a/b/issues/1", "https://github.com/a/b/pull/0", "https://github.com/a/b/pull/999999999999999999999", "https://user@github.com/a/b/pull/1"] {
            XCTAssertNil(PullRequestAddress(url: URL(string: raw)!), raw)
        }
    }

    func testActivityPaginationUsesServerCursorAndMapsDeletedAuthorsAndCommits() async throws {
        let first = #"{"data":{"repository":{"pullRequest":{"timelineItems":{"nodes":[null,{"__typename":"IssueComment","id":"C1","body":"hello","url":"https://github.com/a/b/pull/1#issuecomment-1","createdAt":"2026-10-08T00:00:00Z","author":null}],"pageInfo":{"hasNextPage":true,"endCursor":"opaque-cursor"}}}}}}"#
        let second = #"{"data":{"repository":{"pullRequest":{"timelineItems":{"nodes":[{"__typename":"PullRequestCommit","commit":{"oid":"abc123","messageHeadline":"Fix startup","committedDate":"2026-10-08T01:00:00Z","url":"https://github.com/a/b/commit/abc123"}}],"pageInfo":{"hasNextPage":false,"endCursor":"final"}}}}}}"#
        let transport = StubGitHubHTTPTransport(results: [first, second].map {
            .success(data: Data($0.utf8), response: makeHTTPResponse(url: "https://api.github.com/graphql", statusCode: 200))
        })
        let service = PullRequestDetailService(client: URLSessionGitHubAPIClient(transport: transport, credentialStore: StubGitHubCredentialStore()))
        let address = try XCTUnwrap(PullRequestAddress(url: URL(string: "https://github.com/a/b/pull/1")!))
        let page1 = try await service.activity(address, after: nil)
        XCTAssertEqual(page1.nodes.map(\.id), ["C1"])
        XCTAssertNil(page1.nodes[0].author)
        let page2 = try await service.activity(address, after: page1.pageInfo.nextCursor())
        XCTAssertEqual(page2.nodes[0].body, "Fix startup")
        XCTAssertNil(try page2.pageInfo.nextCursor())
        let requests = await transport.recordedRequests()
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(requests[1].httpBody)) as? [String: Any])
        let variables = try XCTUnwrap(payload["variables"] as? [String: Any])
        XCTAssertEqual(variables["after"] as? String, "opaque-cursor")
        XCTAssertEqual(variables["number"] as? Int, 1)
    }

    func testMissingAndRepeatedPageCursorAreVisibleErrors() throws {
        for json in [#"{"hasNextPage":true,"endCursor":null}"#, #"{"hasNextPage":true,"endCursor":"same"}"#] {
            let info = try JSONDecoder().decode(PRPageInfo.self, from: Data(json.utf8))
            XCTAssertThrowsError(try info.nextCursor(after: "same"))
        }
    }
}
