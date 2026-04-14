import Foundation
import XCTest
@testable import GHOrchestratorCore

final class PullRequestSnapshotServiceTests: XCTestCase {
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

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].repository, repository)
        XCTAssertEqual(snapshots[0].pullRequests, [])
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

    func testFetchRepositorySnapshotsBuildsRepositoryScopedQueryPerRepository() async throws {
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
        XCTAssertEqual(payload.query, GHPullRequestSnapshotService.searchQuery)
        XCTAssertEqual(payload.variables.searchQuery, "repo:openai/codex is:pr is:open author:@me archived:false")
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
                "Failed to load pull requests for ipavlidakis/gh-orchestrator: API rate limit exceeded for user ID 472467."
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
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
}
