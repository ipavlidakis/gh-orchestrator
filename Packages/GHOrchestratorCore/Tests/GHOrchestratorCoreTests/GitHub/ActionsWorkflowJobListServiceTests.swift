import Foundation
import XCTest
@testable import GHOrchestratorCore

final class ActionsWorkflowJobListServiceTests: XCTestCase {
    func testListJobNamesAggregatesRecentWorkflowRunJobs() async throws {
        let transport = StubGitHubHTTPTransport(
            results: [
                .success(
                    data: fixtureData(named: "workflow_runs", subdirectory: "ActionsWorkflows"),
                    response: makeHTTPResponse(url: "https://api.github.com/repos/cli/cli/actions/workflows/10/runs", statusCode: 200)
                ),
                .success(
                    data: fixtureData(named: "completed_jobs", subdirectory: "ActionsJobs"),
                    response: makeHTTPResponse(url: "https://api.github.com/repos/cli/cli/actions/runs/321/jobs", statusCode: 200)
                ),
                .success(
                    data: fixtureData(named: "queued_jobs", subdirectory: "ActionsJobs"),
                    response: makeHTTPResponse(url: "https://api.github.com/repos/cli/cli/actions/runs/555/jobs", statusCode: 200)
                )
            ]
        )
        let client = URLSessionGitHubAPIClient(
            transport: transport,
            credentialStore: StubGitHubCredentialStore()
        )
        let service = ActionsWorkflowJobListService(client: client)

        let jobNames = try await service.listJobNames(
            repository: ObservedRepository(owner: "cli", name: "cli"),
            workflow: ActionsWorkflowItem(id: 10, name: "CI", path: ".github/workflows/ci.yml", state: "active")
        )
        let requests = await transport.recordedRequests()

        XCTAssertEqual(
            requests.map { $0.url?.absoluteString },
            [
                "https://api.github.com/repos/cli/cli/actions/workflows/10/runs",
                "https://api.github.com/repos/cli/cli/actions/runs/321/jobs",
                "https://api.github.com/repos/cli/cli/actions/runs/555/jobs"
            ]
        )
        XCTAssertEqual(jobNames, ["lint", "unit-tests"])
    }

    func testListJobNamesReturnsEmptyWhenWorkflowHasNoRuns() async throws {
        let service = makeWorkflowJobListService(
            results: [
                .success(
                    data: Data(#"{"workflow_runs":[]}"#.utf8),
                    response: makeHTTPResponse(url: "https://api.github.com/repos/cli/cli/actions/workflows/10/runs", statusCode: 200)
                )
            ]
        )

        let jobNames = try await service.listJobNames(
            repository: ObservedRepository(owner: "cli", name: "cli"),
            workflow: ActionsWorkflowItem(id: 10, name: "CI", path: ".github/workflows/ci.yml", state: "active")
        )

        XCTAssertTrue(jobNames.isEmpty)
    }

    func testListJobNamesFormatsGitHubErrors() async {
        let service = makeWorkflowJobListService(
            results: [
                .success(
                    data: Data(#"{"message":"Actions disabled"}"#.utf8),
                    response: makeHTTPResponse(url: "https://api.github.com/repos/cli/cli/actions/workflows/10/runs", statusCode: 403)
                )
            ]
        )

        do {
            _ = try await service.listJobNames(
                repository: ObservedRepository(owner: "cli", name: "cli"),
                workflow: ActionsWorkflowItem(id: 10, name: "CI", path: ".github/workflows/ci.yml", state: "active")
            )
            XCTFail("Expected workflow job list failure")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Failed to load Actions jobs for CI in cli/cli: Actions disabled"
            )
        }
    }

    private func makeWorkflowJobListService(
        results: [StubGitHubHTTPTransport.Result]
    ) -> ActionsWorkflowJobListService {
        let client = URLSessionGitHubAPIClient(
            transport: StubGitHubHTTPTransport(results: results),
            credentialStore: StubGitHubCredentialStore()
        )

        return ActionsWorkflowJobListService(client: client)
    }
}
