import Foundation

public struct GitHubTokenExchangeRequest: Codable, Equatable, Sendable {
    public let clientID: String
    public let clientSecret: String
    public let code: String
    public let codeVerifier: String
    public let redirectURI: String

    public init(
        clientID: String,
        clientSecret: String,
        code: String,
        codeVerifier: OAuthCodeVerifier,
        redirectURI: URL = OAuthAppConfiguration.defaultRedirectURI
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.code = code
        self.codeVerifier = codeVerifier.rawValue
        self.redirectURI = redirectURI.absoluteString
    }

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case clientSecret = "client_secret"
        case code
        case codeVerifier = "code_verifier"
        case redirectURI = "redirect_uri"
    }
}

public struct GitHubTokenExchangeResponse: Codable, Equatable, Sendable {
    public let accessToken: String?
    public let tokenType: String?
    public let scope: String?
    public let refreshToken: String?
    public let expiresIn: Int?
    public let refreshTokenExpiresIn: Int?
    public let interval: Int?
    public let error: String?
    public let errorDescription: String?
    public let errorURI: URL?

    public init(
        accessToken: String? = nil,
        tokenType: String? = nil,
        scope: String? = nil,
        refreshToken: String? = nil,
        expiresIn: Int? = nil,
        refreshTokenExpiresIn: Int? = nil,
        interval: Int? = nil,
        error: String? = nil,
        errorDescription: String? = nil,
        errorURI: URL? = nil
    ) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.scope = scope
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
        self.refreshTokenExpiresIn = refreshTokenExpiresIn
        self.interval = interval
        self.error = error
        self.errorDescription = errorDescription
        self.errorURI = errorURI
    }

    public func session(
        username: String? = nil,
        now: Date = Date()
    ) throws -> GitHubSession {
        if let error {
            throw GitHubTokenExchangeError.authorizationFailed(
                error: error,
                description: errorDescription,
                documentationURL: errorURI
            )
        }

        guard let accessToken, !accessToken.isEmpty else {
            throw GitHubTokenExchangeError.missingAccessToken
        }

        guard let tokenType, !tokenType.isEmpty else {
            throw GitHubTokenExchangeError.missingTokenType
        }

        return GitHubSession(
            accessToken: accessToken,
            tokenType: tokenType,
            scopes: Self.normalizedScopes(scope),
            refreshToken: refreshToken,
            accessTokenExpirationDate: expirationDate(after: expiresIn, from: now),
            refreshTokenExpirationDate: expirationDate(after: refreshTokenExpiresIn, from: now),
            username: username?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func normalizedScopes(_ scope: String?) -> [String] {
        guard let scope else {
            return []
        }

        return scope
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private func expirationDate(after duration: Int?, from now: Date) -> Date? {
        guard let duration, duration > 0 else {
            return nil
        }

        return now.addingTimeInterval(TimeInterval(duration))
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case refreshTokenExpiresIn = "refresh_token_expires_in"
        case interval
        case error
        case errorDescription = "error_description"
        case errorURI = "error_uri"
    }
}

public struct GitHubSession: Codable, Equatable, Sendable {
    public let accessToken: String
    public let tokenType: String
    public let scopes: [String]
    public let refreshToken: String?
    public let accessTokenExpirationDate: Date?
    public let refreshTokenExpirationDate: Date?
    public let username: String?

    public init(
        accessToken: String,
        tokenType: String,
        scopes: [String] = [],
        refreshToken: String? = nil,
        accessTokenExpirationDate: Date? = nil,
        refreshTokenExpirationDate: Date? = nil,
        username: String? = nil
    ) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.scopes = scopes
        self.refreshToken = refreshToken
        self.accessTokenExpirationDate = accessTokenExpirationDate
        self.refreshTokenExpirationDate = refreshTokenExpirationDate
        self.username = username
    }
}

public enum GitHubTokenExchangeError: Equatable, LocalizedError, Sendable {
    case authorizationFailed(error: String, description: String?, documentationURL: URL?)
    case missingAccessToken
    case missingTokenType

    public var errorDescription: String? {
        switch self {
        case .authorizationFailed(let error, let description, let documentationURL):
            let details = [description, documentationURL?.absoluteString]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            if details.isEmpty {
                return "GitHub token exchange failed with \(error)."
            }

            return "GitHub token exchange failed with \(error): \(details)"
        case .missingAccessToken:
            return "GitHub token exchange response did not include an access token."
        case .missingTokenType:
            return "GitHub token exchange response did not include a token type."
        }
    }
}

extension GitHubTokenExchangeRequest {
    func formURLEncodedData() -> Data {
        let queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: codeVerifier),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
        ]

        let payload = queryItems
            .map { item in
                let value = item.value ?? ""
                return "\(item.name.percentEncodedQueryValue)=\(value.percentEncodedQueryValue)"
            }
            .joined(separator: "&")

        return Data(payload.utf8)
    }
}

extension String {
    var percentEncodedQueryValue: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? self
    }
}

extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=/?")
        return allowed
    }()
}
