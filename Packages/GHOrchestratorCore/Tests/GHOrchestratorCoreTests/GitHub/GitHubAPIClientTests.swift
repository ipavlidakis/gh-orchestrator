import Foundation
import XCTest
@testable import GHOrchestratorCore

final class GitHubAPIClientTests: XCTestCase {
    func testAuthenticatedUserUsesStoredBearerToken() async throws {
        let transport = StubGitHubHTTPTransport(
            results: [
                .success(
                    data: fixtureData(named: "authenticated_user", subdirectory: "GitHubAPI"),
                    response: makeHTTPResponse(url: "https://api.github.com/user", statusCode: 200)
                )
            ]
        )
        let credentialStore = StubGitHubCredentialStore(
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

    func testAuthenticatedRequestRecordsRateLimitHeaders() async throws {
        let metricsRecorder = RecordingGitHubRequestMetrics()
        let transport = StubGitHubHTTPTransport(
            results: [
                .success(
                    data: fixtureData(named: "authenticated_user", subdirectory: "GitHubAPI"),
                    response: makeHTTPResponse(
                        url: "https://api.github.com/user",
                        statusCode: 200,
                        headerFields: [
                            "x-ratelimit-limit": "5000",
                            "x-ratelimit-remaining": "4991",
                            "x-ratelimit-used": "9",
                            "x-ratelimit-reset": "1735689600",
                            "x-ratelimit-resource": "core",
                        ]
                    )
                )
            ]
        )
        let credentialStore = StubGitHubCredentialStore(
            session: GitHubSession(
                accessToken: "access-token",
                tokenType: "bearer",
                scopes: ["repo"]
            )
        )
        let client = URLSessionGitHubAPIClient(
            transport: transport,
            credentialStore: credentialStore,
            metricsRecorder: metricsRecorder
        )

        _ = try await client.authenticatedUser()

        let records = await metricsRecorder.records()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].method, "GET")
        XCTAssertEqual(records[0].endpoint, "api.github.com/user")
        XCTAssertEqual(records[0].statusCode, 200)
        XCTAssertEqual(
            records[0].rateLimit,
            GitHubRateLimitStatus(
                limit: 5000,
                remaining: 4991,
                used: 9,
                resetDate: Date(timeIntervalSince1970: 1_735_689_600),
                resource: "core"
            )
        )
    }

    func testGraphQLPostsQueryAndVariablesToGitHubEndpoint() async throws {
        let transport = StubGitHubHTTPTransport(
            results: [
                .success(
                    data: fixtureData(named: "graphql_viewer", subdirectory: "GitHubAPI"),
                    response: makeHTTPResponse(url: "https://api.github.com/graphql", statusCode: 200)
                )
            ]
        )
        let credentialStore = StubGitHubCredentialStore(
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
        let transport = StubGitHubHTTPTransport(
            results: [
                .success(
                    data: fixtureData(named: "graphql_error", subdirectory: "GitHubAPI"),
                    response: makeHTTPResponse(url: "https://api.github.com/graphql", statusCode: 200)
                )
            ]
        )
        let credentialStore = StubGitHubCredentialStore(
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

    func testRerunWorkflowJobPostsToJobRerunEndpoint() async throws {
        let transport = StubGitHubHTTPTransport(
            results: [
                .success(
                    data: Data(),
                    response: makeHTTPResponse(
                        url: "https://api.github.com/repos/openai/codex/actions/jobs/42/rerun",
                        statusCode: 201
                    )
                )
            ]
        )
        let credentialStore = StubGitHubCredentialStore(
            session: GitHubSession(accessToken: "access-token", tokenType: "bearer")
        )
        let client = URLSessionGitHubAPIClient(
            transport: transport,
            credentialStore: credentialStore
        )

        try await client.rerunWorkflowJob(
            repository: ObservedRepository(owner: "openai", name: "codex"),
            jobID: 42
        )

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(
            requests[0].url?.absoluteString,
            "https://api.github.com/repos/openai/codex/actions/jobs/42/rerun"
        )
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
    }

    func testStartDeviceAuthorizationPostsClientIDAndScopeToGitHubEndpoint() async throws {
        let configuration = try XCTUnwrap(
            OAuthAppConfiguration.resolve(
                clientID: "abc123",
                scopes: ["repo", "workflow"]
            ).configuration
        )
        let transport = StubGitHubHTTPTransport(
            results: [
                .success(
                    data: Data(#"{"device_code":"device-code","user_code":"WDJB-MJHT","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#.utf8),
                    response: makeHTTPResponse(url: "https://github.com/login/device/code", statusCode: 200)
                )
            ]
        )
        let credentialStore = StubGitHubCredentialStore(session: nil)
        let client = URLSessionGitHubAPIClient(
            transport: transport,
            credentialStore: credentialStore
        )

        let authorization = try await client.startDeviceAuthorization(configuration: configuration)
        let requests = await transport.recordedRequests()
        let requestBody = String(decoding: try XCTUnwrap(requests[0].httpBody), as: UTF8.self)

        XCTAssertEqual(authorization.deviceCode, "device-code")
        XCTAssertEqual(authorization.userCode, "WDJB-MJHT")
        XCTAssertEqual(authorization.interval, 5)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url?.absoluteString, "https://github.com/login/device/code")
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertTrue(requestBody.contains("client_id=abc123"))
        XCTAssertTrue(requestBody.contains("scope=repo%20workflow"))
    }

    func testPollDeviceAuthorizationResolvesUserAndPersistsSession() async throws {
        let configuration = try XCTUnwrap(
            OAuthAppConfiguration.resolve(clientID: "abc123").configuration
        )
        let transport = StubGitHubHTTPTransport(
            results: [
                .success(
                    data: fixtureData(named: "token_exchange_success", subdirectory: "GitHubAPI"),
                    response: makeHTTPResponse(url: "https://github.com/login/oauth/access_token", statusCode: 200)
                ),
                .success(
                    data: fixtureData(named: "authenticated_user", subdirectory: "GitHubAPI"),
                    response: makeHTTPResponse(url: "https://api.github.com/user", statusCode: 200)
                )
            ]
        )
        let credentialStore = StubGitHubCredentialStore(session: nil)
        let client = URLSessionGitHubAPIClient(
            transport: transport,
            credentialStore: credentialStore
        )

        let result = try await client.pollDeviceAuthorization(
            configuration: configuration,
            deviceCode: "device-code",
            interval: 5
        )
        let requests = await transport.recordedRequests()
        let tokenRequestBody = String(decoding: try XCTUnwrap(requests[0].httpBody), as: UTF8.self)

        guard case .success(let session) = result else {
            return XCTFail("Expected a successful device authorization poll result")
        }

        XCTAssertEqual(session.accessToken, "access-token")
        XCTAssertEqual(session.username, "octocat")
        XCTAssertEqual(try credentialStore.loadSession(), session)

        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].url?.absoluteString, "https://github.com/login/oauth/access_token")
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertTrue(tokenRequestBody.contains("client_id=abc123"))
        XCTAssertTrue(tokenRequestBody.contains("device_code=device-code"))
        XCTAssertTrue(tokenRequestBody.contains("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code"))

        XCTAssertEqual(requests[1].url?.absoluteString, "https://api.github.com/user")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
    }

    func testPollDeviceAuthorizationReturnsPendingWithSlowDownBackoff() async throws {
        let configuration = try XCTUnwrap(
            OAuthAppConfiguration.resolve(clientID: "abc123").configuration
        )
        let transport = StubGitHubHTTPTransport(
            results: [
                .success(
                    data: Data(#"{"error":"slow_down","interval":9}"#.utf8),
                    response: makeHTTPResponse(url: "https://github.com/login/oauth/access_token", statusCode: 200)
                )
            ]
        )
        let client = URLSessionGitHubAPIClient(
            transport: transport,
            credentialStore: StubGitHubCredentialStore(session: nil)
        )

        let result = try await client.pollDeviceAuthorization(
            configuration: configuration,
            deviceCode: "device-code",
            interval: 5
        )

        XCTAssertEqual(result, .pending(nextInterval: 10))
    }

    func testAuthenticatedUserFailsWhenNoStoredSessionExists() async throws {
        let transport = StubGitHubHTTPTransport(results: [])
        let client = URLSessionGitHubAPIClient(
            transport: transport,
            credentialStore: StubGitHubCredentialStore(session: nil)
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
        let transport = StubGitHubHTTPTransport(
            results: [
                .success(
                    data: fixtureData(named: "bad_credentials", subdirectory: "GitHubAPI"),
                    response: makeHTTPResponse(url: "https://api.github.com/user", statusCode: 401)
                )
            ]
        )
        let credentialStore = StubGitHubCredentialStore(
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

private actor RecordingGitHubRequestMetrics: GitHubRequestMetricsRecording {
    private var storedRecords: [GitHubRequestRecord] = []

    func record(_ request: GitHubRequestRecord) async {
        storedRecords.append(request)
    }

    func records() -> [GitHubRequestRecord] {
        storedRecords
    }
}
