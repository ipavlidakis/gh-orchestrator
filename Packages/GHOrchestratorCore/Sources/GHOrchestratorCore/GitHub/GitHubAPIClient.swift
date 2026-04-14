import Foundation

public protocol GitHubAPIClient: Sendable {
    func get<Response: Decodable>(_ path: String) async throws -> Response
    func graphQL<Response: Decodable, Variables: Encodable>(
        query: String,
        variables: Variables?
    ) async throws -> Response
    func authenticatedUser() async throws -> GitHubAuthenticatedUser
    func startDeviceAuthorization(
        configuration: OAuthAppConfiguration
    ) async throws -> GitHubDeviceAuthorization
    func pollDeviceAuthorization(
        configuration: OAuthAppConfiguration,
        deviceCode: String,
        interval: Int
    ) async throws -> GitHubDeviceAuthorizationPollResult
    func exchangeCode(
        configuration: OAuthAppConfiguration,
        callback: OAuthCallback,
        codeVerifier: OAuthCodeVerifier
    ) async throws -> GitHubSession
}

public struct URLSessionGitHubAPIClient: GitHubAPIClient {
    public static let defaultAPIBaseURL = URL(string: "https://api.github.com")!
    public static let defaultGraphQLURL = URL(string: "https://api.github.com/graphql")!

    public let transport: any GitHubHTTPTransport
    public let credentialStore: any GitHubCredentialStore
    public let apiBaseURL: URL
    public let graphQLURL: URL

    public init(
        transport: any GitHubHTTPTransport = URLSessionGitHubHTTPTransport(),
        credentialStore: any GitHubCredentialStore = KeychainGitHubCredentialStore(),
        apiBaseURL: URL = URLSessionGitHubAPIClient.defaultAPIBaseURL,
        graphQLURL: URL = URLSessionGitHubAPIClient.defaultGraphQLURL
    ) {
        self.transport = transport
        self.credentialStore = credentialStore
        self.apiBaseURL = apiBaseURL
        self.graphQLURL = graphQLURL
    }

    public func get<Response: Decodable>(_ path: String) async throws -> Response {
        let request = try authenticatedRequest(
            url: endpointURL(path: path),
            method: "GET"
        )

        let data = try await perform(request)

        do {
            return try GitHubJSONCoders.restDecoder.decode(Response.self, from: data)
        } catch {
            throw GitHubAPIClientError.invalidResponse(message: error.localizedDescription)
        }
    }

    public func graphQL<Response: Decodable, Variables: Encodable>(
        query: String,
        variables: Variables?
    ) async throws -> Response {
        let requestBody = GraphQLRequestBody(query: query, variables: variables)
        var request = try authenticatedRequest(
            url: graphQLURL,
            method: "POST"
        )

        do {
            request.httpBody = try GitHubJSONCoders.encoder.encode(requestBody)
        } catch {
            throw GitHubAPIClientError.invalidResponse(message: error.localizedDescription)
        }

        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data = try await perform(request)

        let envelope: GraphQLResponseEnvelope<Response>
        do {
            envelope = try GitHubJSONCoders.graphQLDecoder.decode(GraphQLResponseEnvelope<Response>.self, from: data)
        } catch {
            throw GitHubAPIClientError.invalidResponse(message: error.localizedDescription)
        }

        let messages = envelope.errors?
            .map(\.message)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []

        if !messages.isEmpty {
            throw GitHubAPIClientError.graphQLRequestFailed(messages: messages)
        }

        guard let response = envelope.data else {
            throw GitHubAPIClientError.invalidResponse(message: "The GraphQL response did not include a data payload.")
        }

        return response
    }

    public func authenticatedUser() async throws -> GitHubAuthenticatedUser {
        try await get("/user")
    }

    public func startDeviceAuthorization(
        configuration: OAuthAppConfiguration
    ) async throws -> GitHubDeviceAuthorization {
        let deviceRequest = GitHubDeviceAuthorizationRequest(
            clientID: configuration.clientID,
            scopes: configuration.scopes
        )

        var request = URLRequest(url: configuration.deviceCodeURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = deviceRequest.formURLEncodedData()

        let data = try await perform(request, includeAuthorization: false)

        do {
            return try GitHubJSONCoders.restDecoder.decode(GitHubDeviceAuthorization.self, from: data)
        } catch {
            throw GitHubAPIClientError.invalidResponse(message: error.localizedDescription)
        }
    }

    public func pollDeviceAuthorization(
        configuration: OAuthAppConfiguration,
        deviceCode: String,
        interval: Int
    ) async throws -> GitHubDeviceAuthorizationPollResult {
        let pollRequest = GitHubDeviceAccessTokenPollRequest(
            clientID: configuration.clientID,
            deviceCode: deviceCode
        )

        var request = URLRequest(url: configuration.accessTokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = pollRequest.formURLEncodedData()

        let data = try await perform(request, includeAuthorization: false)

        let tokenResponse: GitHubTokenExchangeResponse
        do {
            tokenResponse = try GitHubJSONCoders.restDecoder.decode(GitHubTokenExchangeResponse.self, from: data)
        } catch {
            throw GitHubAPIClientError.invalidResponse(message: error.localizedDescription)
        }

        if let errorCode = tokenResponse.error?.trimmingCharacters(in: .whitespacesAndNewlines), !errorCode.isEmpty {
            return try pollResult(
                for: errorCode,
                response: tokenResponse,
                fallbackInterval: interval
            )
        }

        var session = try tokenResponse.session()
        let user = try await authenticatedUser(using: session)
        session = session.withUsername(user.login)
        try credentialStore.saveSession(session)
        return .success(session)
    }

    public func exchangeCode(
        configuration: OAuthAppConfiguration,
        callback: OAuthCallback,
        codeVerifier: OAuthCodeVerifier
    ) async throws -> GitHubSession {
        guard let clientSecret = configuration.clientSecret else {
            throw GitHubAPIClientError.invalidResponse(
                message: "GitHub OAuth web flow requires a client secret."
            )
        }

        let tokenRequest = GitHubTokenExchangeRequest(
            clientID: configuration.clientID,
            clientSecret: clientSecret,
            code: callback.code,
            codeVerifier: codeVerifier,
            redirectURI: configuration.redirectURI
        )

        var request = URLRequest(url: configuration.accessTokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = tokenRequest.formURLEncodedData()

        let data = try await perform(request, includeAuthorization: false)

        let tokenResponse: GitHubTokenExchangeResponse
        do {
            tokenResponse = try GitHubJSONCoders.restDecoder.decode(GitHubTokenExchangeResponse.self, from: data)
        } catch {
            throw GitHubAPIClientError.invalidResponse(message: error.localizedDescription)
        }

        var session = try tokenResponse.session()
        let user = try await authenticatedUser(using: session)
        session = session.withUsername(user.login)
        try credentialStore.saveSession(session)
        return session
    }
}

extension URLSessionGitHubAPIClient {
    private func pollResult(
        for errorCode: String,
        response: GitHubTokenExchangeResponse,
        fallbackInterval: Int
    ) throws -> GitHubDeviceAuthorizationPollResult {
        switch errorCode {
        case "authorization_pending":
            return .pending(nextInterval: max(fallbackInterval, 1))
        case "slow_down":
            let nextInterval = response.interval ?? (fallbackInterval + 5)
            return .pending(nextInterval: max(nextInterval, fallbackInterval + 5))
        case "expired_token", "token_expired":
            throw GitHubDeviceAuthorizationError.expiredToken
        case "access_denied":
            throw GitHubDeviceAuthorizationError.accessDenied(
                description: response.errorDescription,
                documentationURL: response.errorURI
            )
        case "device_flow_disabled":
            throw GitHubDeviceAuthorizationError.deviceFlowDisabled
        case "incorrect_client_credentials":
            throw GitHubDeviceAuthorizationError.incorrectClientCredentials
        case "incorrect_device_code":
            throw GitHubDeviceAuthorizationError.incorrectDeviceCode
        case "unsupported_grant_type":
            throw GitHubDeviceAuthorizationError.unsupportedGrantType
        default:
            throw GitHubDeviceAuthorizationError.authorizationFailed(
                error: errorCode,
                description: response.errorDescription,
                documentationURL: response.errorURI
            )
        }
    }

    private func authenticatedUser(using session: GitHubSession) async throws -> GitHubAuthenticatedUser {
        let request = try authenticatedRequest(
            url: endpointURL(path: "/user"),
            method: "GET",
            session: session
        )

        let data = try await perform(request)

        do {
            return try GitHubJSONCoders.restDecoder.decode(GitHubAuthenticatedUser.self, from: data)
        } catch {
            throw GitHubAPIClientError.invalidResponse(message: error.localizedDescription)
        }
    }

    private func endpointURL(path: String) -> URL {
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return apiBaseURL.appendingPathComponent(normalizedPath)
    }

    private func authenticatedRequest(
        url: URL,
        method: String,
        session: GitHubSession? = nil
    ) throws -> URLRequest {
        let resolvedSession: GitHubSession?
        if let session {
            resolvedSession = session
        } else {
            resolvedSession = try credentialStore.loadSession()
        }

        guard let resolvedSession else {
            throw GitHubAPIClientError.missingSession
        }

        var request = baseRequest(url: url, method: method)
        request.setValue(
            authorizationHeaderValue(for: resolvedSession),
            forHTTPHeaderField: "Authorization"
        )
        return request
    }

    private func baseRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func perform(
        _ request: URLRequest,
        includeAuthorization: Bool = true
    ) async throws -> Data {
        let responseData: Data
        let response: URLResponse

        do {
            (responseData, response) = try await transport.data(for: request)
        } catch {
            throw GitHubAPIClientError.transportFailed(message: error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubAPIClientError.invalidResponse(message: "Expected an HTTPURLResponse from GitHub.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = GitHubAPIErrorMessageFormatter.normalize(data: responseData)
            throw GitHubAPIClientError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: message.isEmpty ? defaultFailureMessage(for: httpResponse.statusCode, includeAuthorization: includeAuthorization) : message
            )
        }

        return responseData
    }

    private func defaultFailureMessage(for statusCode: Int, includeAuthorization: Bool) -> String {
        if includeAuthorization {
            return "GitHub API request failed with status code \(statusCode)."
        }

        return "GitHub OAuth token exchange failed with status code \(statusCode)."
    }

    private func authorizationHeaderValue(for session: GitHubSession) -> String {
        let tokenType = session.tokenType.trimmingCharacters(in: .whitespacesAndNewlines)

        if tokenType.caseInsensitiveCompare("bearer") == .orderedSame {
            return "Bearer \(session.accessToken)"
        }

        return "\(tokenType) \(session.accessToken)"
    }
}

public enum GitHubAPIClientError: Error, Equatable, LocalizedError, Sendable {
    case missingSession
    case transportFailed(message: String)
    case requestFailed(statusCode: Int, message: String)
    case graphQLRequestFailed(messages: [String])
    case invalidResponse(message: String)

    public var errorDescription: String? {
        switch self {
        case .missingSession:
            return "No GitHub session is available."
        case .transportFailed(let message):
            return "GitHub transport failed: \(message)"
        case .requestFailed(let statusCode, let message):
            return "GitHub request failed with status code \(statusCode): \(message)"
        case .graphQLRequestFailed(let messages):
            return "GitHub GraphQL request failed: \(messages.joined(separator: " "))"
        case .invalidResponse(let message):
            return "GitHub returned an invalid response: \(message)"
        }
    }
}

extension GitHubAPIClientError {
    var displayMessage: String {
        switch self {
        case .missingSession:
            return "No GitHub session is available."
        case .transportFailed(let message):
            return message
        case .requestFailed(_, let message):
            return message
        case .graphQLRequestFailed(let messages):
            return messages.joined(separator: " ")
        case .invalidResponse(let message):
            return message
        }
    }
}

public protocol GitHubHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

public struct URLSessionGitHubHTTPTransport: GitHubHTTPTransport, @unchecked Sendable {
    public let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

private struct GraphQLRequestBody<Variables: Encodable>: Encodable {
    let query: String
    let variables: Variables?
}

private struct GraphQLResponseEnvelope<Response: Decodable>: Decodable {
    let data: Response?
    let errors: [GraphQLError]?
}

private struct GraphQLError: Decodable {
    let message: String
}

private extension GitHubSession {
    func withUsername(_ username: String) -> GitHubSession {
        GitHubSession(
            accessToken: accessToken,
            tokenType: tokenType,
            scopes: scopes,
            refreshToken: refreshToken,
            accessTokenExpirationDate: accessTokenExpirationDate,
            refreshTokenExpirationDate: refreshTokenExpirationDate,
            username: username
        )
    }
}
