import Foundation
import XCTest
@testable import GHOrchestratorCore

final class PullRequestSnapshotServiceTests: XCTestCase {
    func testFetchRepositorySnapshotsReturnsEmptyListForNoPullRequestsFixture() async throws {
        let repository = ObservedRepository(owner: "openai", name: "codex")
        let client = MockGHCLIClient(outputsBySearchQuery: [
            "repo:openai/codex is:pr is:open author:@me archived:false": .success(fixtureOutput(named: "no_prs"))
        ])

        let service = GHPullRequestSnapshotService(client: client)
        let snapshots = try await service.fetchRepositorySnapshots(for: [repository])

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].repository, repository)
        XCTAssertEqual(snapshots[0].pullRequests, [])
    }

    func testFetchRepositorySnapshotsMapsApprovedPullRequestFixture() async throws {
        let repository = ObservedRepository(owner: "cli", name: "cli")
        let client = MockGHCLIClient(outputsBySearchQuery: [
            "repo:cli/cli is:pr is:open author:@me archived:false": .success(fixtureOutput(named: "approved_pr"))
        ])

        let service = GHPullRequestSnapshotService(client: client)
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
        let client = MockGHCLIClient(outputsBySearchQuery: [
            "repo:cli/cli is:pr is:open author:@me archived:false": .success(fixtureOutput(named: "review_required_pr"))
        ])

        let service = GHPullRequestSnapshotService(client: client)
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
        let client = MockGHCLIClient(outputsBySearchQuery: [
            "repo:cli/cli is:pr is:open author:@me archived:false": .success(fixtureOutput(named: "draft_pr"))
        ])

        let service = GHPullRequestSnapshotService(client: client)
        let snapshots = try await service.fetchRepositorySnapshots(for: [repository])
        let pullRequest = try XCTUnwrap(snapshots.first?.pullRequests.first)

        XCTAssertTrue(pullRequest.isDraft)
        XCTAssertEqual(pullRequest.reviewStatus, .none)
        XCTAssertEqual(pullRequest.checkRollupState, .failing)
    }

    func testFetchRepositorySnapshotsBuildsRepositoryScopedQueryPerRepository() async throws {
        let repository = ObservedRepository(owner: "openai", name: "codex")
        let client = MockGHCLIClient(outputsBySearchQuery: [
            "repo:openai/codex is:pr is:open author:@me archived:false": .success(fixtureOutput(named: "no_prs"))
        ])

        let service = GHPullRequestSnapshotService(client: client)
        _ = try await service.fetchRepositorySnapshots(for: [repository])

        XCTAssertEqual(client.recordedSearchQueries, ["repo:openai/codex is:pr is:open author:@me archived:false"])
        XCTAssertTrue(client.recordedArguments.first?.contains("--hostname") == true)
        XCTAssertTrue(client.recordedArguments.first?.contains("github.com") == true)
    }
}

private final class MockGHCLIClient: GHCLIClient, @unchecked Sendable {
    enum StubResult {
        case success(ProcessOutput)
        case failure(Error)
    }

    private let outputsBySearchQuery: [String: StubResult]
    private(set) var recordedArguments: [[String]] = []
    private(set) var recordedSearchQueries: [String] = []

    init(outputsBySearchQuery: [String: StubResult]) {
        self.outputsBySearchQuery = outputsBySearchQuery
    }

    func run(arguments: [String]) throws -> ProcessOutput {
        recordedArguments.append(arguments)

        guard let queryField = arguments.last(where: { $0.hasPrefix("searchQuery=") }) else {
            XCTFail("Missing searchQuery field in arguments: \(arguments)")
            return ProcessOutput(exitCode: 1, standardOutput: "", standardError: "missing searchQuery")
        }

        let searchQuery = String(queryField.dropFirst("searchQuery=".count))
        recordedSearchQueries.append(searchQuery)

        guard let result = outputsBySearchQuery[searchQuery] else {
            XCTFail("No stub registered for query: \(searchQuery)")
            return ProcessOutput(exitCode: 1, standardOutput: "", standardError: "missing stub")
        }

        switch result {
        case .success(let output):
            return output
        case .failure(let error):
            throw error
        }
    }

    func health() -> GitHubCLIHealth {
        .authenticated(username: "octocat")
    }
}

private func fixtureOutput(named name: String) -> ProcessOutput {
    ProcessOutput(
        exitCode: 0,
        standardOutput: fixtureString(named: name),
        standardError: ""
    )
}

private func fixtureString(named name: String) -> String {
    let directURL = Bundle.module.url(forResource: name, withExtension: "json")
    let nestedURL = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "PullRequestSearch")
    let fixturesURL = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/PullRequestSearch")

    guard let url = directURL ?? nestedURL ?? fixturesURL else {
        fatalError("Missing fixture \(name).json")
    }

    guard let data = try? Data(contentsOf: url), let string = String(data: data, encoding: .utf8) else {
        fatalError("Unable to load fixture \(name).json")
    }

    return string
}
