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
        let first = #"{"data":{"repository":{"pullRequest":{"timelineItems":{"nodes":[null,{"__typename":"IssueComment","id":"C1","body":"hello","bodyHTML":"<p><strong>hello</strong></p>","url":"https://github.com/a/b/pull/1#issuecomment-1","createdAt":"2026-10-08T00:00:00Z","author":null}],"pageInfo":{"hasNextPage":true,"endCursor":"opaque-cursor"}}}}}}"#
        let second = #"{"data":{"repository":{"pullRequest":{"timelineItems":{"nodes":[{"__typename":"PullRequestCommit","commit":{"oid":"abc123","messageHeadline":"Fix startup","committedDate":"2026-10-08T01:00:00Z","url":"https://github.com/a/b/commit/abc123"}}],"pageInfo":{"hasNextPage":false,"endCursor":"final"}}}}}}"#
        let transport = StubGitHubHTTPTransport(results: [first, second].map {
            .success(data: Data($0.utf8), response: makeHTTPResponse(url: "https://api.github.com/graphql", statusCode: 200))
        })
        let service = PullRequestDetailService(client: URLSessionGitHubAPIClient(transport: transport, credentialStore: StubGitHubCredentialStore()))
        let address = try XCTUnwrap(PullRequestAddress(url: URL(string: "https://github.com/a/b/pull/1")!))
        let page1 = try await service.activity(address, after: nil)
        XCTAssertEqual(page1.nodes.map(\.id), ["C1"])
        XCTAssertNil(page1.nodes[0].author)
        XCTAssertEqual(page1.nodes[0].bodyHTML, "<p><strong>hello</strong></p>")
        let page2 = try await service.activity(address, after: page1.pageInfo.nextCursor())
        XCTAssertEqual(page2.nodes[0].body, "Fix startup")
        XCTAssertNil(page2.nodes[0].bodyHTML)
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

    func testConversationMutationsEncodeBodiesAndMapConfirmedResults() async throws {
        let comment = #"{"id":"C2","body":"New comment","bodyHTML":"<p>New comment</p>","url":"https://github.com/a/b/pull/1#issuecomment-2","createdAt":"2026-10-08T00:00:00Z","author":{"login":"alex","url":"https://github.com/alex","avatarUrl":"https://avatars.githubusercontent.com/u/1"}}"#
        let reviewComment = String(comment.dropLast()) + #", "pullRequestReview":{"id":"R1"}}"#
        let results = [
            #"{"data":{"addComment":{"commentEdge":{"node":\#(comment)}}}}"#,
            #"{"data":{"addPullRequestReviewThreadReply":{"comment":\#(reviewComment)}}}"#,
            #"{"data":{"action":{"thread":{"id":"T1","isResolved":true,"viewerCanResolve":false,"viewerCanUnresolve":true}}}}"#,
            #"{"data":{"action":{"thread":{"id":"T1","isResolved":false,"viewerCanResolve":true,"viewerCanUnresolve":false}}}}"#
        ]
        let transport = StubGitHubHTTPTransport(results: results.map {
            .success(data: Data($0.utf8), response: makeHTTPResponse(url: "https://api.github.com/graphql", statusCode: 200))
        })
        let service = PullRequestDetailService(client: URLSessionGitHubAPIClient(transport: transport, credentialStore: StubGitHubCredentialStore()))
        let body = "Keep `code`, \"quotes\" and\nnewlines. 👍🏽 👩‍💻 🇬🇷 👨‍👩‍👧‍👦 :rocket:"
        let posted = try await service.addComment(pullRequestID: "PR1", body: body)
        let reply = try await service.reply(threadID: "T1", body: body)
        XCTAssertEqual(posted.bodyHTML, "<p>New comment</p>")
        XCTAssertEqual(reply.author?.url?.absoluteString, "https://github.com/alex")
        XCTAssertNil(posted.pullRequestReview)
        XCTAssertEqual(reply.pullRequestReview?.id, "R1")
        let resolved = try await service.setResolved(threadID: "T1", resolved: true)
        let reopened = try await service.setResolved(threadID: "T1", resolved: false)
        XCTAssertTrue(resolved.isResolved)
        XCTAssertTrue(resolved.viewerCanUnresolve)
        XCTAssertFalse(reopened.isResolved)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 4)
        for (index, request) in requests.enumerated() {
            let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            let variables = try XCTUnwrap(payload["variables"] as? [String: Any])
            XCTAssertEqual(variables["id"] as? String, index == 0 ? "PR1" : "T1")
            if index < 2 { XCTAssertEqual(variables["body"] as? String, body) }
            if index < 2 {
                let query = try XCTUnwrap(payload["query"] as? String)
                XCTAssertEqual(query.contains("pullRequestReview { id }"), index == 1, "IssueComment has no review association field")
            }
        }
    }

    func testMissingMutationConfirmationAndDeniedActionAreVisibleFailures() async throws {
        let transport = StubGitHubHTTPTransport(results: [
            .success(data: Data(#"{"data":{"addPullRequestReviewThreadReply":null}}"#.utf8), response: makeHTTPResponse(url: "https://api.github.com/graphql", statusCode: 200)),
            .success(data: Data(#"{"errors":[{"message":"Not permitted"}]}"#.utf8), response: makeHTTPResponse(url: "https://api.github.com/graphql", statusCode: 200))
        ])
        let service = PullRequestDetailService(client: URLSessionGitHubAPIClient(transport: transport, credentialStore: StubGitHubCredentialStore()))
        do { _ = try await service.reply(threadID: "T1", body: "Reply"); XCTFail("Missing confirmation must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("did not confirm")) }
        do { _ = try await service.setResolved(threadID: "T1", resolved: true); XCTFail("Denied resolution must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Not permitted")) }
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 2, "Writes must not automatically retry")
    }

    func testReactionsUseTypedContentAndConfirmedSubjectCountsWithoutRetry() async throws {
        let added = #"{"data":{"action":{"subject":{"id":"C1","viewerCanReact":true,"reactionGroups":[{"content":"HEART","viewerHasReacted":true,"reactors":{"totalCount":3}}]}}}}"#
        let removed = added.replacingOccurrences(of: "\"viewerHasReacted\":true", with: "\"viewerHasReacted\":false").replacingOccurrences(of: "\"totalCount\":3", with: "\"totalCount\":2")
        let responses = [added, removed, added.replacingOccurrences(of: "\"C1\"", with: "\"another-comment\""), #"{"errors":[{"message":"Not permitted"}]}"#]
        let transport = StubGitHubHTTPTransport(results: responses.map { .success(data: Data($0.utf8), response: makeHTTPResponse(url: "https://api.github.com/graphql", statusCode: 200)) })
        let service = PullRequestDetailService(client: URLSessionGitHubAPIClient(transport: transport, credentialStore: StubGitHubCredentialStore()))
        let first = try await service.setReaction(subjectID: "C1", content: .heart, added: true)
        let second = try await service.setReaction(subjectID: "C1", content: .heart, added: false)
        XCTAssertEqual(first.reactionGroups.first?.reactors.totalCount, 3)
        XCTAssertEqual(first.reactionGroups.first?.viewerHasReacted, true)
        XCTAssertEqual(second.reactionGroups.first?.viewerHasReacted, false)
        XCTAssertEqual(second.reactionGroups.first?.reactors.totalCount, 2)
        do { _ = try await service.setReaction(subjectID: "C1", content: .heart, added: true); XCTFail("Wrong subject confirmation must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("did not confirm")) }
        do { _ = try await service.setReaction(subjectID: "C1", content: .heart, added: true); XCTFail("Denied action must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Not permitted")) }
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 4, "Reaction writes must not automatically retry")
        for (index, request) in requests.prefix(2).enumerated() {
            let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            let variables = try XCTUnwrap(payload["variables"] as? [String: Any])
            XCTAssertEqual(variables["id"] as? String, "C1")
            XCTAssertEqual(variables["content"] as? String, "HEART")
            XCTAssertTrue((payload["query"] as? String)?.contains(index == 0 ? "addReaction" : "removeReaction") == true)
        }
        XCTAssertEqual(PRReactionContent.allCases.count, 8)
        XCTAssertNil(PRReactionContent(rawValue: "UNSUPPORTED"))
    }
}
