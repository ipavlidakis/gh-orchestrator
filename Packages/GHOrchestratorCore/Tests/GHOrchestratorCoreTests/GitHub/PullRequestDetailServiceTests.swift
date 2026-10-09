import Foundation
import XCTest
@testable import GHOrchestratorCore

final class PullRequestDetailServiceTests: XCTestCase {
    func testRepoOnlyTokenLoadsSummaryAndConfirmsReviewerRequestsWithoutTeamScopes() async throws {
        let address = try XCTUnwrap(PullRequestAddress(url: URL(string: "https://github.com/a/b/pull/1")!))
        let reviewRequests: [String: Any] = [
            "nodes": [
                ["id": "RR-team", "requestedReviewer": ["__typename": "Team"]],
                ["id": "RR-user", "requestedReviewer": ["__typename": "User", "id": "U1", "login": "morgan", "avatarUrl": "https://avatars.githubusercontent.com/u/1"]]
            ],
            "pageInfo": ["hasNextPage": false]
        ]
        var summaryEnvelope = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(textSummaryResponse().utf8)) as? [String: Any])
        var summaryData = try XCTUnwrap(summaryEnvelope["data"] as? [String: Any])
        var repository = try XCTUnwrap(summaryData["repository"] as? [String: Any])
        var summary = try XCTUnwrap(repository["pullRequest"] as? [String: Any])
        summary["reviewRequests"] = reviewRequests
        repository["pullRequest"] = summary; summaryData["repository"] = repository; summaryEnvelope["data"] = summaryData
        let summaryResponse = try JSONSerialization.data(withJSONObject: summaryEnvelope)
        let mutationResponse = try JSONSerialization.data(withJSONObject: ["data": ["requestReviews": ["pullRequest": ["id": "PR1", "reviewRequests": reviewRequests]]]])
        let scopeFailure = Data(#"{"errors":[{"type":"INSUFFICIENT_SCOPES","message":"Your token has not been granted the required scopes to execute this query. The 'id' field requires one of the following scopes: ['read:org', 'read:discussion'], but your token has only been granted: ['repo'] scopes."}]}"#.utf8)
        let transport = RoutingGitHubHTTPTransport { request in
            let payload = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            let query = payload?["query"] as? String ?? ""
            if query.contains("... on Team") { return scopeFailure }
            return query.contains("mutation PRRequestReviewers") ? mutationResponse : summaryResponse
        }
        let credentials = StubGitHubCredentialStore(session: GitHubSession(accessToken: "repo-only-token", tokenType: "bearer", scopes: ["repo"]))
        let service = PullRequestDetailService(client: URLSessionGitHubAPIClient(transport: transport, credentialStore: credentials))
        let loaded = try await service.summary(address)
        XCTAssertEqual(loaded.title, "PR")
        XCTAssertEqual(loaded.viewerCanUpdate, true)
        XCTAssertEqual(loaded.reviewRequests?.nodes.map(\.id), ["RR-team", "RR-user"])
        XCTAssertEqual(loaded.reviewRequests?.nodes.first?.isTeam, true)
        XCTAssertNil(loaded.reviewRequests?.nodes.first?.requestedReviewer)
        XCTAssertEqual(loaded.reviewRequests?.nodes.last?.requestedReviewer?.login, "morgan")
        let confirmed = try await service.requestReviewers(address, userIDs: ["U1"])
        XCTAssertEqual(confirmed.id, "PR1")
        XCTAssertEqual(confirmed.reviewRequests.nodes.map(\.id), ["RR-team", "RR-user"])
        XCTAssertEqual(confirmed.reviewRequests.nodes.first?.isTeam, true)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 3, "Summary, permission check and one mutation; no scope recovery or duplicate notification")
    }

    func testTextEditingRechecksBothFieldsAndRequiresConfirmedMutation() async throws {
        let address = try XCTUnwrap(PullRequestAddress(url: URL(string: "https://github.com/a/b/pull/1")!))
        let transport = StubGitHubHTTPTransport(results: try [
            textSummaryResponse(),
            #"{"data":{"updatePullRequest":{"pullRequest":{"id":"PR1","title":"Updated 👩‍💻","body":"- [x] Ship\r\n","bodyHTML":"<p>Saved</p>"}}}}"#,
            textSummaryResponse(title: "Remote title"),
            textSummaryResponse(body: "Remote description"),
            textSummaryResponse(canUpdate: false),
            textSummaryResponse(),
            #"{"data":{"updatePullRequest":null}}"#
        ].map { .success(data: Data($0.utf8), response: makeHTTPResponse(url: "https://api.github.com/graphql", statusCode: 200)) })
        let service = PullRequestDetailService(client: URLSessionGitHubAPIClient(transport: transport, credentialStore: StubGitHubCredentialStore()))
        let result = try await service.updateText(address, title: "Updated 👩‍💻", body: "- [x] Ship\r\n", expectedTitle: "PR", expectedBody: "Original")
        XCTAssertEqual(result.title, "Updated 👩‍💻")
        XCTAssertEqual(result.bodyHTML, "<p>Saved</p>")
        for expected in ["changed on GitHub", "changed on GitHub", "cannot edit", "did not confirm"] {
            do { _ = try await service.updateText(address, title: "Updated", body: "Draft", expectedTitle: "PR", expectedBody: "Original"); XCTFail("Expected \(expected)") }
            catch { XCTAssertTrue(error.localizedDescription.contains(expected), error.localizedDescription) }
        }
        do { _ = try await service.updateText(address, title: "  ", body: "Draft", expectedTitle: "PR", expectedBody: "Original"); XCTFail("Empty title must be rejected") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Enter a pull request title")) }
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 7, "Stale fields, access denial and blank titles never mutate")
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(requests[1].httpBody)) as? [String: Any])
        let variables = try XCTUnwrap(payload["variables"] as? [String: Any])
        XCTAssertEqual(variables["title"] as? String, "Updated 👩‍💻")
        XCTAssertEqual(variables["body"] as? String, "- [x] Ship\r\n")
    }

    func testReviewerSearchPagesAndAddingKeepsExistingTeamRequests() async throws {
        let address = try XCTUnwrap(PullRequestAddress(url: URL(string: "https://github.com/a/b/pull/1")!))
        let team = #"{"id":"RR-team","requestedReviewer":{"__typename":"Team"}}"#
        let responses = try [
            #"{"data":{"repository":{"assignableUsers":{"nodes":[{"id":"U1","login":"morgan","name":"Morgan","avatarUrl":"https://avatars.githubusercontent.com/u/1"}],"pageInfo":{"hasNextPage":true,"endCursor":"page-2"}}}}}"#,
            #"{"data":{"repository":{"assignableUsers":{"nodes":[{"id":"U2","login":"sam"}],"pageInfo":{"hasNextPage":false}}}}}"#,
            textSummaryResponse(),
            #"{"data":{"requestReviews":{"pullRequest":{"id":"PR1","reviewRequests":{"nodes":[\#(team),{"id":"RR-user","requestedReviewer":{"id":"U1","login":"morgan"}}],"pageInfo":{"hasNextPage":false}}}}}}"#,
            textSummaryResponse(canUpdate: false),
            textSummaryResponse(),
            #"{"data":{"requestReviews":null}}"#
        ]
        let transport = StubGitHubHTTPTransport(results: responses.map { .success(data: Data($0.utf8), response: makeHTTPResponse(url: "https://api.github.com/graphql", statusCode: 200)) })
        let service = PullRequestDetailService(client: URLSessionGitHubAPIClient(transport: transport, credentialStore: StubGitHubCredentialStore()))
        let first = try await service.reviewers(address, query: "mor", after: nil)
        XCTAssertEqual(first.nodes.first?.login, "morgan")
        let next = try await service.reviewers(address, query: "mor", after: first.pageInfo.nextCursor())
        XCTAssertEqual(next.nodes.first?.login, "sam")
        XCTAssertNil(try next.pageInfo.nextCursor())
        let added = try await service.requestReviewers(address, userIDs: ["U1"])
        XCTAssertEqual(added.reviewRequests.nodes.first?.id, "RR-team")
        XCTAssertEqual(added.reviewRequests.nodes.first?.isTeam, true)
        XCTAssertEqual(added.reviewRequests.nodes.compactMap { $0.requestedReviewer?.login }, ["morgan"])
        for expected in ["cannot request reviewers", "did not confirm"] {
            do { _ = try await service.requestReviewers(address, userIDs: ["U1"]); XCTFail("Expected \(expected)") }
            catch { XCTAssertTrue(error.localizedDescription.contains(expected), error.localizedDescription) }
        }
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 7)
        let search = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(requests[1].httpBody)) as? [String: Any])
        XCTAssertEqual((search["variables"] as? [String: Any])?["query"] as? String, "mor")
        XCTAssertEqual((search["variables"] as? [String: Any])?["after"] as? String, "page-2")
        let mutation = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(requests[3].httpBody)) as? [String: Any])
        XCTAssertTrue((mutation["query"] as? String)?.contains("union: true") == true, "GitHub must add requests without clearing teams or other users")
        XCTAssertEqual((mutation["variables"] as? [String: Any])?["users"] as? [String], ["U1"])
    }

    private func textSummaryResponse(title: String = "PR", body: String = "Original", canUpdate: Bool = true) throws -> String {
        let summary: [String: Any] = ["id": "PR1", "viewerCanUpdate": canUpdate, "title": title, "body": body, "bodyHTML": "<p>Original</p>", "state": "OPEN", "isDraft": false, "createdAt": "2026-10-09T00:00:00Z", "headRefName": "feature", "baseRefName": "main", "additions": 1, "deletions": 0, "mergeable": "MERGEABLE", "commits": ["nodes": []]]
        return String(decoding: try JSONSerialization.data(withJSONObject: ["data": ["repository": ["pullRequest": summary]]]), as: UTF8.self)
    }

    private func mergeSummaryResponse(overrides: [String: Any] = [:]) throws -> String {
        let envelope = try JSONSerialization.jsonObject(with: Data(textSummaryResponse().utf8)) as! [String: Any]
        var summary = ((envelope["data"] as! [String: Any])["repository"] as! [String: Any])["pullRequest"] as! [String: Any]
        summary.merge([
            "headRefOid": "head1", "mergeStateStatus": "CLEAN", "isMergeQueueEnabled": false,
            "viewerCanMergeAsAdmin": false, "viewerCanEnableAutoMerge": true, "viewerCanDisableAutoMerge": true,
            "autoMergeRequest": NSNull(), "repository": ["mergeCommitAllowed": true, "squashMergeAllowed": true, "rebaseMergeAllowed": true, "autoMergeAllowed": true, "viewerPermission": "WRITE"]
        ]) { _, new in new }
        summary.merge(overrides) { _, new in new }
        return String(decoding: try JSONSerialization.data(withJSONObject: ["data": ["repository": ["pullRequest": summary]]]), as: UTF8.self)
    }

    func testMergeMethodsAutoMergeAndBypassUseFreshHeadAndConfirmedResults() async throws {
        let address = try XCTUnwrap(PullRequestAddress(url: URL(string: "https://github.com/a/b/pull/1")!))
        for method in PRMergeMethod.allCases {
            for action in [PRMergeAction.merge, .enableAutoMerge, .disableAutoMerge] {
                let automatic: Any = ["mergeMethod": method.rawValue]
                let overrides: [String: Any] = action == .disableAutoMerge ? ["autoMergeRequest": automatic] : action == .merge ? ["mergeStateStatus": "BLOCKED", "viewerCanMergeAsAdmin": true] : ["mergeStateStatus": "BLOCKED"]
                let confirmation: [String: Any] = ["id": "PR1", "state": action == .merge ? "MERGED" : "OPEN", "autoMergeRequest": action == .enableAutoMerge ? automatic : NSNull()]
                let mutation = String(decoding: try JSONSerialization.data(withJSONObject: ["data": ["action": ["pullRequest": confirmation]]]), as: UTF8.self)
                let transport = StubGitHubHTTPTransport(results: try [mergeSummaryResponse(overrides: overrides), mutation].map {
                    .success(data: Data($0.utf8), response: makeHTTPResponse(url: "https://api.github.com/graphql", statusCode: 200))
                })
                let service = PullRequestDetailService(client: URLSessionGitHubAPIClient(transport: transport, credentialStore: StubGitHubCredentialStore()))
                let result = try await service.merge(address, request: PRMergeRequest(method: method, action: action, expectedHeadOID: "head1", expectedBaseRefName: "main", bypassRules: action == .merge))
                XCTAssertEqual(result.state, action == .merge ? "MERGED" : "OPEN")
                XCTAssertEqual(result.autoMergeRequest?.mergeMethod, action == .enableAutoMerge ? method : nil)
                let requests = await transport.recordedRequests()
                XCTAssertEqual(requests.count, 2)
                let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(requests[1].httpBody)) as? [String: Any])
                let input = try XCTUnwrap((payload["variables"] as? [String: Any])?["input"] as? [String: Any])
                XCTAssertEqual(input["pullRequestId"] as? String, "PR1")
                XCTAssertEqual(input["expectedHeadOid"] as? String, action == .disableAutoMerge ? nil : "head1")
                XCTAssertEqual(input["mergeMethod"] as? String, action == .disableAutoMerge ? nil : method.rawValue)
                let expectedMutation = action == .merge ? "mergePullRequest" : action == .enableAutoMerge ? "enablePullRequestAutoMerge" : "disablePullRequestAutoMerge"
                XCTAssertTrue((payload["query"] as? String)?.contains(expectedMutation) == true)
            }
        }
    }

    func testMergeRejectsStaleHeadsBranchesPermissionsRequirementsAndUnconfirmedWrites() async throws {
        let address = try XCTUnwrap(PullRequestAddress(url: URL(string: "https://github.com/a/b/pull/1")!))
        let denied: [[String: Any]] = [
            ["headRefOid": "new-head"], ["baseRefName": "new-base"], ["state": "CLOSED"], ["isDraft": true],
            ["mergeable": "CONFLICTING"], ["isMergeQueueEnabled": true], ["mergeStateStatus": "UNKNOWN"],
            ["mergeStateStatus": "BLOCKED"], ["repository": ["mergeCommitAllowed": true, "squashMergeAllowed": false, "rebaseMergeAllowed": true, "autoMergeAllowed": true, "viewerPermission": "WRITE"]],
            ["repository": ["mergeCommitAllowed": true, "squashMergeAllowed": true, "rebaseMergeAllowed": true, "autoMergeAllowed": true, "viewerPermission": "READ"]]
        ]
        for (overrides, bypass, confirmation) in denied.map({ ($0, false, "") }) + [(["mergeStateStatus": "BLOCKED"], true, ""), ([:], false, #"{"data":{"action":{"pullRequest":{"id":"PR1","state":"OPEN","autoMergeRequest":null}}}}"#), ([:], false, #"{"errors":[{"message":"Merging is blocked"}]}"#)] {
            let responses = [try mergeSummaryResponse(overrides: overrides)] + (confirmation.isEmpty ? [] : [confirmation])
            let transport = StubGitHubHTTPTransport(results: responses.map { .success(data: Data($0.utf8), response: makeHTTPResponse(url: "https://api.github.com/graphql", statusCode: 200)) })
            let service = PullRequestDetailService(client: URLSessionGitHubAPIClient(transport: transport, credentialStore: StubGitHubCredentialStore()))
            do {
                _ = try await service.merge(address, request: PRMergeRequest(method: .squash, action: .merge, expectedHeadOID: "head1", expectedBaseRefName: "main", bypassRules: bypass))
                XCTFail("Unsafe or unconfirmed merge must fail: \(overrides)")
            } catch {}
            let requests = await transport.recordedRequests()
            XCTAssertEqual(requests.count, responses.count, "Denied operations stop before mutation; failed writes never retry")
        }
    }

    func testDescriptionTasksSkipExamplesAndKeepUnicodeSourceOffsets() throws {
        let body = "👩‍💻 Intro\r\n```md\r\n- [ ] example\r\n```\r\n<!--\r\n- [x] hidden\r\n-->\r\n- [ ] real\r\n  * [X] nested\r\n> 1. [x] quoted\r\n~~~\r\n- [ ] another example\r\n~~~\r\n"
        let tasks = PRDescriptionTask.items(in: body)
        XCTAssertEqual(tasks.map(\.checked), [false, true, true])
        XCTAssertEqual(tasks.map(\.offset), ["[ ] real", "[X] nested", "[x] quoted"].map { (body as NSString).range(of: $0).location + 1 })
        XCTAssertTrue(PRDescriptionTask.items(in: "<input type='checkbox'>\n- [ ] ambiguous").isEmpty)
    }

    func testDescriptionTaskWriteRechecksCurrentBodyAndPreservesEveryOtherByte() async throws {
        let body = "👩‍💻 Intro\r\n- [ ] Ship **safely**\r\n- [X] Keep `code`\r\n"
        let updatedBody = "👩‍💻 Intro\r\n- [x] Ship **safely**\r\n- [X] Keep `code`\r\n"
        let offset = (body as NSString).range(of: "[ ]").location + 1
        let address = try XCTUnwrap(PullRequestAddress(url: URL(string: "https://github.com/a/b/pull/1")!))
        func response(_ body: String, canUpdate: Bool) throws -> String {
            let summary: [String: Any] = ["id": "PR1", "viewerCanUpdate": canUpdate, "title": "PR", "body": body, "bodyHTML": "<p>Checklist</p>", "state": "OPEN", "isDraft": false, "createdAt": "2026-10-09T00:00:00Z", "headRefName": "feature", "baseRefName": "main", "additions": 1, "deletions": 0, "mergeable": "MERGEABLE", "commits": ["nodes": []]]
            return String(decoding: try JSONSerialization.data(withJSONObject: ["data": ["repository": ["pullRequest": summary]]]), as: UTF8.self)
        }
        let confirmation = String(decoding: try JSONSerialization.data(withJSONObject: ["data": ["updatePullRequest": ["pullRequest": ["id": "PR1", "body": updatedBody, "bodyHTML": "<p>Saved by GitHub</p>"]]]]), as: UTF8.self)
        let transport = StubGitHubHTTPTransport(results: try [response(body, canUpdate: true), confirmation, response(body + "Elsewhere", canUpdate: true), response(body, canUpdate: false), response(body, canUpdate: true), #"{"data":{"updatePullRequest":null}}"#].map {
            .success(data: Data($0.utf8), response: makeHTTPResponse(url: "https://api.github.com/graphql", statusCode: 200))
        })
        let service = PullRequestDetailService(client: URLSessionGitHubAPIClient(transport: transport, credentialStore: StubGitHubCredentialStore()))
        let updated = try await service.setDescriptionTask(address, offset: offset, checked: true, expectedBody: body)
        XCTAssertEqual(updated.body, updatedBody)
        XCTAssertEqual(updated.bodyHTML, "<p>Saved by GitHub</p>")
        for expectedError in ["changed on GitHub", "cannot edit", "did not confirm"] {
            do { _ = try await service.setDescriptionTask(address, offset: offset, checked: true, expectedBody: body); XCTFail("Expected \(expectedError)") }
            catch { XCTAssertTrue(error.localizedDescription.contains(expectedError), error.localizedDescription) }
        }
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 6, "Stale and denied writes stop before mutation; failed writes never retry")
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(requests[1].httpBody)) as? [String: Any])
        let variables = try XCTUnwrap(payload["variables"] as? [String: Any])
        XCTAssertEqual(variables["body"] as? String, updatedBody)
        XCTAssertEqual(variables["id"] as? String, "PR1")
    }

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
