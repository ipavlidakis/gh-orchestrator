import Foundation
import XCTest
@testable import GHOrchestratorCore

final class ActionsWorkflowListServiceTests: XCTestCase {
    func testListWorkflowsFetchesRepositoryWorkflowsAndSortsNames() async throws {
        let transport = StubGitHubHTTPTransport(
            results: [
                .success(
                    data: fixtureData(named: "list_workflows", subdirectory: "ActionsWorkflows"),
                    response: makeHTTPResponse(url: "https://api.github.com/repos/cli/cli/actions/workflows", statusCode: 200)
                )
            ]
        )
        let client = URLSessionGitHubAPIClient(
            transport: transport,
            credentialStore: StubGitHubCredentialStore()
        )
        let service = ActionsWorkflowListService(client: client)

        let workflows = try await service.listWorkflows(
            repository: ObservedRepository(owner: "cli", name: "cli")
        )
        let requests = await transport.recordedRequests()

        XCTAssertEqual(requests.map { $0.url?.absoluteString }, ["https://api.github.com/repos/cli/cli/actions/workflows"])
        XCTAssertEqual(workflows.map(\.name), ["CI", "Lint", "Release"])
        XCTAssertEqual(workflows.map(\.state), ["active", "disabled_manually", "active"])
        XCTAssertEqual(workflows[0].htmlURL?.absoluteString, "https://github.com/cli/cli/actions/workflows/ci.yml")
    }

    func testListWorkflowsFormatsGitHubErrors() async {
        let service = makeWorkflowListService(
            results: [
                .success(
                    data: Data(#"{"message":"Actions disabled"}"#.utf8),
                    response: makeHTTPResponse(url: "https://api.github.com/repos/cli/cli/actions/workflows", statusCode: 403)
                )
            ]
        )

        do {
            _ = try await service.listWorkflows(repository: ObservedRepository(owner: "cli", name: "cli"))
            XCTFail("Expected workflow list failure")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Failed to load Actions workflows for cli/cli: Actions disabled"
            )
        }
    }

    private func makeWorkflowListService(
        results: [StubGitHubHTTPTransport.Result]
    ) -> ActionsWorkflowListService {
        let client = URLSessionGitHubAPIClient(
            transport: StubGitHubHTTPTransport(results: results),
            credentialStore: StubGitHubCredentialStore()
        )

        return ActionsWorkflowListService(client: client)
    }
}
