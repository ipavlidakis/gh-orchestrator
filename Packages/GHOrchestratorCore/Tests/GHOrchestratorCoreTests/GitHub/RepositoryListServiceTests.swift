import Foundation
import XCTest
@testable import GHOrchestratorCore

final class RepositoryListServiceTests: XCTestCase {
    func testDiscoveryLoadsAllPagesAndDeduplicatesRepositories() async throws {
        let firstPage = try JSONSerialization.data(withJSONObject: (0..<100).map { ["full_name": "team/project\($0)"] })
        let secondPage = Data(#"[{"full_name":"TEAM/project0"},{"full_name":"outside/library"}]"#.utf8)
        let transport = StubGitHubHTTPTransport(results: [response(firstPage), response(secondPage)])
        let service = RepositoryListService(client: URLSessionGitHubAPIClient(transport: transport, credentialStore: StubGitHubCredentialStore()))
        let repositories = try await service.listRepositories()
        let requests = await transport.recordedRequests()
        XCTAssertEqual(repositories.count, 101)
        XCTAssertEqual(repositories.first?.fullName, "outside/library")
        XCTAssertTrue(repositories.contains { $0.fullName == "team/project99" })
        XCTAssertEqual(requests.compactMap { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "page" }?.value }, ["1", "2"])
        XCTAssertTrue(requests.allSatisfy { $0.url?.path == "/user/repos" && $0.url?.query?.contains("affiliation=owner,collaborator,organization_member") == true })
    }

    func testInvalidNamesAndAccessFailuresAreVisible() async {
        let cases: [(Data, Int, GitHubAPIClientError)] = [
            (Data(#"[{"full_name":"invalid"}]"#.utf8), 200, .invalidResponse(message: "GitHub returned an invalid repository name.")),
            (Data(#"{"message":"Organization access denied"}"#.utf8), 403, .requestFailed(statusCode: 403, message: "Organization access denied"))
        ]
        for (data, status, expected) in cases {
            let transport = StubGitHubHTTPTransport(results: [response(data, status: status)])
            let service = RepositoryListService(client: URLSessionGitHubAPIClient(transport: transport, credentialStore: StubGitHubCredentialStore()))
            do {
                _ = try await service.listRepositories()
                XCTFail("Expected discovery to fail")
            } catch {
                XCTAssertEqual(error as? GitHubAPIClientError, expected)
            }
        }
    }

    func testRepeatedPageFailsInsteadOfLoopingOrReturningPartialCatalogue() async throws {
        let page = try JSONSerialization.data(withJSONObject: (0..<100).map { ["full_name": "team/project\($0)"] })
        let transport = StubGitHubHTTPTransport(results: [response(page), response(page)])
        let service = RepositoryListService(client: URLSessionGitHubAPIClient(transport: transport, credentialStore: StubGitHubCredentialStore()))
        do {
            _ = try await service.listRepositories()
            XCTFail("Expected repeated-page failure")
        } catch {
            XCTAssertEqual(error as? GitHubAPIClientError, .invalidResponse(message: "GitHub repeated a repository page. Please refresh the list."))
        }
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 2)
    }

    private func response(_ data: Data, status: Int = 200) -> StubGitHubHTTPTransport.Result {
        .success(data: data, response: makeHTTPResponse(url: "https://api.github.com/user/repos", statusCode: status))
    }
}
