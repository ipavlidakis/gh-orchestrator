import Foundation

public protocol GitHubAPIClient: Sendable {
    func get<Response: Decodable>(_ path: String) async throws -> Response
    func graphQL<Response: Decodable, Variables: Encodable>(
        query: String,
        variables: Variables?
    ) async throws -> Response
    func authenticatedUser() async throws -> GitHubAuthenticatedUser
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

    public func exchangeCode(
        configuration: OAuthAppConfiguration,
        callback: OAuthCallback,
        codeVerifier: OAuthCodeVerifier
    ) async throws -> GitHubSession {
        let tokenRequest = GitHubTokenExchangeRequest(
            clientID: configuration.clientID,
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
