import Foundation
import XCTest
@testable import GHOrchestratorCore

final class GitHubAPIClientTests: XCTestCase {
    func testAuthenticatedUserUsesStoredBearerToken() async throws {
        let transport = MockGitHubHTTPTransport(
            results: [
                .success(
                    data: Data(#"{"login":"octocat"}"#.utf8),
                    response: httpResponse(url: "https://api.github.com/user", statusCode: 200)
                )
            ]
        )
        let credentialStore = MockGitHubCredentialStore(
            session: GitHubSession(
                accessToken: "access-token",
                tokenType: "bearer",
                scopes: ["repo"]
            )
        )
        let client = URLSessionGitHubAPIClient(
            transport: transport,
            credentialStore: credentialStore
        )

        let user = try await client.authenticatedUser()
        let requests = await transport.recordedRequests()

        XCTAssertEqual(user.login, "octocat")
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url?.absoluteString, "https://api.github.com/user")
        XCTAssertEqual(requests[0].httpMethod, "GET")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testGraphQLPostsQueryAndVariablesToGitHubEndpoint() async throws {
        let transport = MockGitHubHTTPTransport(
            results: [
                .success(
                    data: Data(#"{"data":{"viewer":{"login":"octocat"}}}"#.utf8),
                    response: httpResponse(url: "https://api.github.com/graphql", statusCode: 200)
                )
            ]
        )
        let credentialStore = MockGitHubCredentialStore(
            session: GitHubSession(
                accessToken: "access-token",
                tokenType: "bearer"
            )
        )
        let client = URLSessionGitHubAPIClient(
            transport: transport,
            credentialStore: credentialStore
        )

        let response: ViewerResponse = try await client.graphQL(
            query: "query($owner: String!) { viewer { login } }",
            variables: ["owner": "openai"]
        )
        let requests = await transport.recordedRequests()

        XCTAssertEqual(response.viewer.login, "octocat")
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url?.absoluteString, "https://api.github.com/graphql")
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(requests[0].httpBody)
        let payload = try JSONDecoder().decode(GraphQLPayload.self, from: body)
        XCTAssertEqual(payload.query, "query($owner: String!) { viewer { login } }")
        XCTAssertEqual(payload.variables, ["owner": "openai"])
    }

    func testGraphQLThrowsMessagesFromErrorsField() async throws {
        let transport = MockGitHubHTTPTransport(
            results: [
                .success(
                    data: Data(#"{"errors":[{"message":"Viewer unavailable"}]}"#.utf8),
                    response: httpResponse(url: "https://api.github.com/graphql", statusCode: 200)
                )
            ]
        )
        let credentialStore = MockGitHubCredentialStore(
            session: GitHubSession(accessToken: "access-token", tokenType: "bearer")
        )
        let client = URLSessionGitHubAPIClient(
            transport: transport,
            credentialStore: credentialStore
        )

        do {
            let _: ViewerResponse = try await client.graphQL(
                query: "query { viewer { login } }",
                variables: ["unused": "value"]
            )
            XCTFail("Expected GraphQL request to fail")
        } catch let error as GitHubAPIClientError {
            XCTAssertEqual(error, .graphQLRequestFailed(messages: ["Viewer unavailable"]))
        }
    }

    func testExchangeCodeResolvesUserAndPersistsSession() async throws {
        let configuration = try XCTUnwrap(
            OAuthAppConfiguration.resolve(clientID: "abc123").configuration
        )
        let callback = try OAuthCallback(
            url: URL(string: "ghorchestrator://oauth/callback?code=oauth-code&state=state-123")!,
            expectedState: try XCTUnwrap(OAuthState(rawValue: "state-123"))
        )
        let verifier = try XCTUnwrap(OAuthCodeVerifier(rawValue: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"))
        let transport = MockGitHubHTTPTransport(
            results: [
                .success(
                    data: Data(#"{"access_token":"access-token","token_type":"bearer","scope":"repo"}"#.utf8),
                    response: httpResponse(url: "https://github.com/login/oauth/access_token", statusCode: 200)
                ),
                .success(
                    data: Data(#"{"login":"octocat"}"#.utf8),
                    response: httpResponse(url: "https://api.github.com/user", statusCode: 200)
                )
            ]
        )
        let credentialStore = MockGitHubCredentialStore()
        let client = URLSessionGitHubAPIClient(
            transport: transport,
            credentialStore: credentialStore
        )

        let session = try await client.exchangeCode(
            configuration: configuration,
            callback: callback,
            codeVerifier: verifier
        )
        let requests = await transport.recordedRequests()
        let tokenRequestBody = String(decoding: try XCTUnwrap(requests[0].httpBody), as: UTF8.self)

        XCTAssertEqual(session.accessToken, "access-token")
        XCTAssertEqual(session.username, "octocat")
        XCTAssertEqual(try credentialStore.loadSession(), session)

        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].url?.absoluteString, "https://github.com/login/oauth/access_token")
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertTrue(tokenRequestBody.contains("client_id=abc123"))
        XCTAssertTrue(tokenRequestBody.contains("code=oauth-code"))
        XCTAssertTrue(tokenRequestBody.contains("code_verifier=dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"))
        XCTAssertTrue(tokenRequestBody.contains("redirect_uri=ghorchestrator%3A%2F%2Foauth%2Fcallback"))

        XCTAssertEqual(requests[1].url?.absoluteString, "https://api.github.com/user")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
    }

    func testAuthenticatedUserFailsWhenNoStoredSessionExists() async throws {
        let transport = MockGitHubHTTPTransport(results: [])
        let client = URLSessionGitHubAPIClient(
            transport: transport,
            credentialStore: MockGitHubCredentialStore()
        )

        do {
            let _: GitHubAuthenticatedUser = try await client.authenticatedUser()
            XCTFail("Expected missing-session failure")
        } catch let error as GitHubAPIClientError {
            XCTAssertEqual(error, .missingSession)
        }

        let requests = await transport.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testRequestFailureUsesNormalizedGitHubMessage() async throws {
        let transport = MockGitHubHTTPTransport(
            results: [
                .success(
                    data: Data(#"{"message":"Bad credentials"}"#.utf8),
                    response: httpResponse(url: "https://api.github.com/user", statusCode: 401)
                )
            ]
        )
        let credentialStore = MockGitHubCredentialStore(
            session: GitHubSession(accessToken: "access-token", tokenType: "bearer")
        )
        let client = URLSessionGitHubAPIClient(
            transport: transport,
            credentialStore: credentialStore
        )

        do {
            let _: GitHubAuthenticatedUser = try await client.authenticatedUser()
            XCTFail("Expected request failure")
        } catch let error as GitHubAPIClientError {
            XCTAssertEqual(error, .requestFailed(statusCode: 401, message: "Bad credentials"))
        }
    }
}

private struct ViewerResponse: Decodable, Equatable {
    let viewer: GitHubAuthenticatedUser
}

private struct GraphQLPayload: Decodable {
    let query: String
    let variables: [String: String]
}

private actor MockGitHubHTTPTransport: GitHubHTTPTransport {
    enum Result {
        case success(data: Data, response: URLResponse)
        case failure(Error)
    }

    private var results: [Result]
    private var requests: [URLRequest] = []

    init(results: [Result]) {
        self.results = results
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)

        guard !results.isEmpty else {
            throw MockTransportError.noQueuedResponse
        }

        let result = results.removeFirst()

        switch result {
        case .success(let data, let response):
            return (data, response)
        case .failure(let error):
            throw error
        }
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}

private enum MockTransportError: Error {
    case noQueuedResponse
}

private final class MockGitHubCredentialStore: GitHubCredentialStore, @unchecked Sendable {
    private var session: GitHubSession?

    init(session: GitHubSession? = nil) {
        self.session = session
    }

    func loadSession() throws -> GitHubSession? {
        session
    }

    func saveSession(_ session: GitHubSession) throws {
        self.session = session
    }

    func deleteSession() throws {
        session = nil
    }
}

private func httpResponse(url: String, statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: url)!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
    )!
}
