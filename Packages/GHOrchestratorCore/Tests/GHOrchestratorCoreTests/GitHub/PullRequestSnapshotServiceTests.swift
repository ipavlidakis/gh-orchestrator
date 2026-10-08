import Foundation
import XCTest
@testable import GHOrchestratorCore

final class PullRequestSnapshotServiceTests: XCTestCase {
    func testNotificationScopeStillIncludesAllPRsOnlyInWatchedRepositories() async throws {
        let transport = StubGitHubHTTPTransport(results: [.success(
            data: fixtureData(named: "no_prs", subdirectory: "PullRequestSearch"),
            response: makeHTTPResponse(url: "https://api.github.com/graphql", statusCode: 200)
        )])
        let service = GHPullRequestSnapshotService(client: URLSessionGitHubAPIClient(transport: transport, credentialStore: StubGitHubCredentialStore()))
        _ = try await service.fetchRepositorySnapshots(for: [ObservedRepository(owner: "openai", name: "codex"), ObservedRepository(owner: "cli", name: "cli")], scope: .all)
        let requests = await transport.recordedRequests()
        let payload = try JSONDecoder().decode(PullRequestGraphQLPayload.self, from: XCTUnwrap(requests.first?.httpBody))
        XCTAssertEqual(payload.variables.searchQuery, "is:pr is:open repo:openai/codex repo:cli/cli archived:false sort:updated-desc")
    }

    func testNotificationScopeWithoutWatchedRepositoriesMakesNoRequest() async throws {
        let transport = StubGitHubHTTPTransport(results: [])
        let service = GHPullRequestSnapshotService(client: URLSessionGitHubAPIClient(transport: transport, credentialStore: StubGitHubCredentialStore()))
        let snapshots = try await service.fetchRepositorySnapshots(for: [], scope: .all)
        XCTAssertTrue(snapshots.isEmpty)
        let requests = await transport.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testGlobalSearchGroupsDiscoveredRepositoriesWithOneRequest() async throws {
        let transport = RoutingGitHubHTTPTransport { _ in
            Data(#"{"data":{"search":{"issueCount":2,"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"__typename":"PullRequest","repository":{"nameWithOwner":"outside/first"},"number":1,"title":"First","url":"https://github.com/outside/first/pull/1","isDraft":false,"updatedAt":"2026-10-08T10:00:00Z"},{"__typename":"PullRequest","repository":{"nameWithOwner":"outside/second"},"number":1,"title":"Second","url":"https://github.com/outside/second/pull/1","isDraft":false,"updatedAt":"2026-10-08T10:00:00Z"}]}}}"#.utf8)
        }
        let service = GHPullRequestSnapshotService(client: URLSessionGitHubAPIClient(
            transport: transport, credentialStore: StubGitHubCredentialStore()
        ))
        let snapshots = try await service.fetchRepositorySnapshots(for: [
            ObservedRepository(owner: "configured", name: "one"),
            ObservedRepository(owner: "configured", name: "two")
        ])
        XCTAssertEqual(snapshots.map(\.repository.fullName).sorted(), ["outside/first", "outside/second"])
        XCTAssertEqual(snapshots.flatMap(\.pullRequests).map(\.id).sorted(), ["outside/first#1", "outside/second#1"])
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 1)
        let payload = try JSONDecoder().decode(PullRequestGraphQLPayload.self, from: XCTUnwrap(requests.first?.httpBody))
        XCTAssertFalse(payload.variables.searchQuery.contains("repo:"))
    }

    func testMergeabilitySurvivesDashboardMappingAndLegacyDecoding() async throws {
        let repository = ObservedRepository(owner: "cli", name: "cli")
        for (raw, expected) in [("CONFLICTING", MergeableState.conflicting), ("MERGEABLE", .mergeable), ("UNKNOWN", .unknown), ("FUTURE_VALUE", .unknown), ("", .unknown)] {
            let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: fixtureData(named: "approved_pr", subdirectory: "PullRequestSearch")) as? [String: Any])
            var data = try XCTUnwrap(fixture["data"] as? [String: Any])
            var search = try XCTUnwrap(data["search"] as? [String: Any])
            var nodes = try XCTUnwrap(search["nodes"] as? [[String: Any]])
            nodes[0]["mergeable"] = raw.isEmpty ? nil : raw
            nodes[0]["statusCheckRollup"] = ["state": "SUCCESS", "contexts": ["nodes": []]]
            search["nodes"] = nodes; data["search"] = search
            let service = makeService(results: [.success(
                data: try JSONSerialization.data(withJSONObject: ["data": data]),
                response: makeHTTPResponse(url: "https://api.github.com/graphql", statusCode: 200)
            )])
            let snapshots = try await service.fetchRepositorySnapshots(for: [repository])
            let items = try await ActionsJobsEnrichmentService(client: service.client).buildPullRequestItems(from: snapshots)
            let item = try XCTUnwrap(items.first)
            XCTAssertEqual(item.mergeable, expected, "Conflict state must survive snapshot and Actions enrichment: \(raw)")
            XCTAssertEqual(item.reviewStatus, .approved, "Approval does not imply conflict-free status")
            XCTAssertEqual(item.checkRollupState, .passing)
            let encoded = try JSONEncoder().encode(item)
            XCTAssertEqual(try JSONDecoder().decode(PullRequestItem.self, from: encoded).mergeable, expected)
            var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            legacy.removeValue(forKey: "mergeable")
            XCTAssertNil(try JSONDecoder().decode(PullRequestItem.self, from: JSONSerialization.data(withJSONObject: legacy)).mergeable)
        }
    }

    func testFetchRepositorySnapshotsReturnsEmptyListForNoPullRequestsFixture() async throws {
        let repository = ObservedRepository(owner: "openai", name: "codex")
        let service = makeService(
            results: [
                .success(
                    data: fixtureData(named: "no_prs", subdirectory: "PullRequestSearch"),
                    response: makeHTTPResponse(url: "https://api.github.com/graphql", statusCode: 200)
                )
            ]
        )

        let snapshots = try await service.fetchRepositorySnapshots(for: [repository])

        XCTAssertTrue(snapshots.isEmpty)
    }

    func testFetchRepositorySnapshotsMapsApprovedPullRequestFixture() async throws {
        let repository = ObservedRepository(owner: "cli", name: "cli")
        let service = makeService(
            results: [
                .success(
                    data: fixtureData(named: "approved_pr", subdirectory: "PullRequestSearch"),
                    response: makeHTTPResponse(url: "https://api.github.com/graphql", statusCode: 200)
                )
            ]
        )

        let snapshots = try await service.fetchRepositorySnapshots(for: [repository])
        let pullRequest = try XCTUnwrap(snapshots.first?.pullRequests.first)

        XCTAssertEqual(pullRequest.reviewStatus, .approved)
        XCTAssertEqual(pullRequest.createdAt, ISO8601DateFormatter().date(from: "2026-04-01T06:01:33Z"))
        XCTAssertEqual(pullRequest.authorLogin, "dependabot")
        XCTAssertEqual(pullRequest.checkRollupState, .passing)
        XCTAssertEqual(pullRequest.unresolvedReviewThreadCount, 0)
        XCTAssertEqual(pullRequest.checkRuns.first?.workflowRun?.id, 123456789)
        XCTAssertEqual(pullRequest.checkRuns.first?.appSlug, "github-actions")
        XCTAssertEqual(pullRequest.statusContexts.first?.context, "mergeable")
    }

    func testFetchRepositorySnapshotsMapsReviewRequiredFixtureCountingOnlyActiveThreads() async throws {
        let repository = ObservedRepository(owner: "cli", name: "cli")
        let service = makeService(
            results: [
                .success(
                    data: fixtureData(named: "review_required_pr", subdirectory: "PullRequestSearch"),
                    response: makeHTTPResponse(url: "https://api.github.com/graphql", statusCode: 200)
                )
            ]
        )

        let snapshots = try await service.fetchRepositorySnapshots(for: [repository])
        let pullRequest = try XCTUnwrap(snapshots.first?.pullRequests.first)

        XCTAssertEqual(pullRequest.reviewStatus, .reviewRequired)
        XCTAssertEqual(pullRequest.checkRollupState, .pending)
        XCTAssertEqual(pullRequest.unresolvedReviewThreadCount, 2)
        XCTAssertEqual(
            pullRequest.unresolvedReviewComments.map(\.authorLogin),
            ["octocat", "monalisa"]
        )
        XCTAssertEqual(
            pullRequest.unresolvedReviewComments.map(\.filePath),
            ["Sources/Feature/CallView.swift", "Sources/Core/Store.swift"]
        )
        XCTAssertEqual(
            pullRequest.unresolvedReviewComments.first?.authorAvatarURL?.absoluteString,
            "https://avatars.githubusercontent.com/u/583231?s=56&v=4"
        )
        XCTAssertEqual(
            pullRequest.unresolvedReviewComments.first?.createdAt,
            ISO8601DateFormatter().date(from: "2026-04-14T07:00:00Z")
        )
        XCTAssertNil(pullRequest.unresolvedReviewComments.last?.authorAvatarURL)
        XCTAssertNil(pullRequest.unresolvedReviewComments.last?.createdAt)
    }

    func testFetchRepositorySnapshotsMapsDraftPullRequestFixture() async throws {
        let repository = ObservedRepository(owner: "cli", name: "cli")
        let service = makeService(
            results: [
                .success(
                    data: fixtureData(named: "draft_pr", subdirectory: "PullRequestSearch"),
                    response: makeHTTPResponse(url: "https://api.github.com/graphql", statusCode: 200)
                )
            ]
        )

        let snapshots = try await service.fetchRepositorySnapshots(for: [repository])
        let pullRequest = try XCTUnwrap(snapshots.first?.pullRequests.first)

        XCTAssertTrue(pullRequest.isDraft)
        XCTAssertEqual(pullRequest.reviewStatus, .none)
        XCTAssertEqual(pullRequest.checkRollupState, .failing)
    }

    func testFetchRepositorySnapshotsBuildsGlobalAuthoredQuery() async throws {
        let repository = ObservedRepository(owner: "openai", name: "codex")
        let transport = StubGitHubHTTPTransport(
            results: [
                .success(
                    data: fixtureData(named: "no_prs", subdirectory: "PullRequestSearch"),
                    response: makeHTTPResponse(url: "https://api.github.com/graphql", statusCode: 200)
                )
            ]
        )
        let client = URLSessionGitHubAPIClient(
            transport: transport,
            credentialStore: StubGitHubCredentialStore()
        )
        let service = GHPullRequestSnapshotService(client: client)

        _ = try await service.fetchRepositorySnapshots(for: [repository])

        let requests = await transport.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        let body = try XCTUnwrap(request.httpBody)
        let payload = try JSONDecoder().decode(PullRequestGraphQLPayload.self, from: body)

        XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/graphql")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(payload.query, GHPullRequestSnapshotService.searchQuery())
        XCTAssertEqual(payload.variables.searchQuery, "is:pr is:open author:@me archived:false sort:updated-desc")
    }

    func testSearchQueryUsesBoundedDashboardConnectionLimits() {
        let query = GHPullRequestSnapshotService.searchQuery()

        XCTAssertTrue(query.contains("search(query: $searchQuery, type: ISSUE, first: 10, after: $cursor)"))
        XCTAssertTrue(query.contains("reviewThreads(first: 10)"))
        XCTAssertTrue(query.contains("comments(last: 5)"))
        XCTAssertTrue(query.contains("contexts(first: 15)"))

        XCTAssertFalse(query.contains("first: 100"))
        XCTAssertFalse(query.contains("last: 20"))
    }

    func testSearchQueryUsesCustomDashboardConnectionLimits() {
        let query = GHPullRequestSnapshotService.searchQuery(
            limits: PullRequestSnapshotQueryLimits(
                searchResultLimit: 7,
                reviewThreadLimit: 8,
                reviewThreadCommentLimit: 4,
                checkContextLimit: 9
            )
        )

        XCTAssertTrue(query.contains("search(query: $searchQuery, type: ISSUE, first: 7, after: $cursor)"))
        XCTAssertTrue(query.contains("reviewThreads(first: 8)"))
        XCTAssertTrue(query.contains("comments(last: 4)"))
        XCTAssertTrue(query.contains("contexts(first: 9)"))
    }

    func testFetchRepositorySnapshotsBuildsRequestedReviewsQuery() async throws {
        let repository = ObservedRepository(owner: "openai", name: "codex")
        let transport = StubGitHubHTTPTransport(
            results: [
                .success(
                    data: fixtureData(named: "no_prs", subdirectory: "PullRequestSearch"),
                    response: makeHTTPResponse(url: "https://api.github.com/graphql", statusCode: 200)
                )
            ]
        )
        let client = URLSessionGitHubAPIClient(
            transport: transport,
            credentialStore: StubGitHubCredentialStore()
        )
        let service = GHPullRequestSnapshotService(client: client)

        _ = try await service.fetchRepositorySnapshots(
            for: [repository],
            scope: .reviewRequested
        )

        let requests = await transport.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        let body = try XCTUnwrap(request.httpBody)
        let payload = try JSONDecoder().decode(PullRequestGraphQLPayload.self, from: body)

        XCTAssertEqual(payload.variables.searchQuery, "is:pr is:open review-requested:@me archived:false sort:updated-desc")
    }

    func testGlobalSearchLoadsEveryPageAndDeduplicatesMovingResults() async throws {
        let transport = StubGitHubHTTPTransport(results: [
            .success(data: try searchPage(repositories: ["outside/first"], hasNextPage: true, endCursor: "page-one", issueCount: 2),
                     response: makeHTTPResponse(url: "https://api.github.com/graphql", statusCode: 200)),
            .success(data: try searchPage(repositories: ["outside/first", "outside/second"], issueCount: 2),
                     response: makeHTTPResponse(url: "https://api.github.com/graphql", statusCode: 200))
        ])
        let service = GHPullRequestSnapshotService(client: URLSessionGitHubAPIClient(
            transport: transport, credentialStore: StubGitHubCredentialStore()
        ))
        let snapshots = try await service.fetchRepositorySnapshots(for: [], queryLimits: PullRequestSnapshotQueryLimits(searchResultLimit: 1))
        XCTAssertEqual(snapshots.map(\.repository.fullName), ["outside/first", "outside/second"])
        XCTAssertEqual(snapshots.flatMap(\.pullRequests).count, 2)
        let requests = await transport.recordedRequests()
        let payloads = try requests.map { try JSONDecoder().decode(PullRequestGraphQLPayload.self, from: XCTUnwrap($0.httpBody)) }
        XCTAssertEqual(payloads.map(\.variables.cursor), [nil, "page-one"])
        XCTAssertTrue(payloads.allSatisfy { !$0.variables.searchQuery.contains("repo:") })
    }

    func testLaterSearchPageFailureDoesNotReturnAnIncompleteCategory() async throws {
        let service = makeService(results: [
            .success(data: try searchPage(repositories: ["outside/first"], hasNextPage: true, endCursor: "page-one", issueCount: 2),
                     response: makeHTTPResponse(url: "https://api.github.com/graphql", statusCode: 200)),
            .failure(GitHubAPIClientError.transportFailed(message: "network unavailable"))
        ])
        do {
            _ = try await service.fetchRepositorySnapshots(for: [])
            XCTFail("An incomplete category must not be reported as loaded")
        } catch let error as PullRequestSnapshotServiceError {
            XCTAssertTrue(error.localizedDescription.contains("network unavailable"))
        }
    }

    func testGlobalSearchRejectsMissingAndRepeatedPaginationCursors() async throws {
        for cursor in [nil, "", "repeated"] as [String?] {
            let page = try searchPage(repositories: ["outside/first"], hasNextPage: true, endCursor: cursor, issueCount: 2)
            let transport = RoutingGitHubHTTPTransport { _ in page }
            let service = GHPullRequestSnapshotService(client: URLSessionGitHubAPIClient(
                transport: transport, credentialStore: StubGitHubCredentialStore()
            ))
            do {
                _ = try await service.fetchRepositorySnapshots(for: [])
                XCTFail("Invalid pagination must fail rather than truncate or loop")
            } catch let error as PullRequestSnapshotServiceError {
                XCTAssertTrue(error.localizedDescription.contains("pagination cursor"))
            }
        }
    }

    func testGlobalSearchReportsGitHubResultLimitInsteadOfTruncating() async throws {
        let service = makeService(results: [.success(
            data: try searchPage(repositories: [], issueCount: 1_001),
            response: makeHTTPResponse(url: "https://api.github.com/graphql", statusCode: 200)
        )])
        do {
            _ = try await service.fetchRepositorySnapshots(for: [])
            XCTFail("A category above GitHub's search limit must not appear complete")
        } catch let error as PullRequestSnapshotServiceError {
            XCTAssertTrue(error.localizedDescription.contains("1,000-result search limit"))
        }
    }

    func testGlobalSearchRejectsPullRequestsWithoutRepositoryIdentity() async throws {
        var page = try XCTUnwrap(JSONSerialization.jsonObject(with: searchPage(repositories: ["outside/first"])) as? [String: Any])
        var data = try XCTUnwrap(page["data"] as? [String: Any])
        var search = try XCTUnwrap(data["search"] as? [String: Any])
        var nodes = try XCTUnwrap(search["nodes"] as? [[String: Any]])
        nodes[0].removeValue(forKey: "repository")
        search["nodes"] = nodes; data["search"] = search; page["data"] = data
        let service = makeService(results: [.success(
            data: try JSONSerialization.data(withJSONObject: page),
            response: makeHTTPResponse(url: "https://api.github.com/graphql", statusCode: 200)
        )])
        do {
            _ = try await service.fetchRepositorySnapshots(for: [])
            XCTFail("A PR without repository identity cannot be grouped safely")
        } catch let error as PullRequestSnapshotServiceError {
            XCTAssertTrue(error.localizedDescription.contains("repository"))
        }
    }

    func testFetchRepositorySnapshotsFormatsGitHubAPIErrorsForDisplay() async {
        let repository = ObservedRepository(owner: "ipavlidakis", name: "gh-orchestrator")
        let service = makeService(
            results: [
                .success(
                    data: Data(#"{"errors":[{"message":"API rate limit exceeded for user ID 472467."}]}"#.utf8),
                    response: makeHTTPResponse(url: "https://api.github.com/graphql", statusCode: 403)
                )
            ]
        )

        do {
            _ = try await service.fetchRepositorySnapshots(for: [repository])
            XCTFail("Expected fetchRepositorySnapshots to throw")
        } catch let error as PullRequestSnapshotServiceError {
            XCTAssertEqual(
                error.localizedDescription,
                "Failed to load pull requests: API rate limit exceeded for user ID 472467."
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private func searchPage(
    repositories: [String],
    hasNextPage: Bool = false,
    endCursor: String? = nil,
    issueCount: Int? = nil
) throws -> Data {
    let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: fixtureData(named: "approved_pr", subdirectory: "PullRequestSearch")) as? [String: Any])
    let data = try XCTUnwrap(fixture["data"] as? [String: Any])
    let search = try XCTUnwrap(data["search"] as? [String: Any])
    let template = try XCTUnwrap((search["nodes"] as? [[String: Any]])?.first)
    let nodes = repositories.map { repository -> [String: Any] in
        var node = template
        node["repository"] = ["nameWithOwner": repository]
        node["url"] = "https://github.com/\(repository)/pull/13152"
        return node
    }
    return try JSONSerialization.data(withJSONObject: ["data": ["search": [
        "nodes": nodes,
        "issueCount": issueCount ?? repositories.count,
        "pageInfo": ["hasNextPage": hasNextPage, "endCursor": endCursor.map { $0 as Any } ?? NSNull()]
    ]]])
}

private func makeService(
    results: [StubGitHubHTTPTransport.Result]
) -> GHPullRequestSnapshotService {
    let client = URLSessionGitHubAPIClient(
        transport: StubGitHubHTTPTransport(results: results),
        credentialStore: StubGitHubCredentialStore()
    )

    return GHPullRequestSnapshotService(client: client)
}

private struct PullRequestGraphQLPayload: Decodable {
    let query: String
    let variables: PullRequestVariables
}

private struct PullRequestVariables: Decodable {
    let searchQuery: String
    let cursor: String?
}
