import Foundation

public struct OAuthAppConfiguration: Equatable, Sendable {
    public enum Resolution: Equatable, Sendable {
        case notConfigured
        case configured(OAuthAppConfiguration)

        public var configuration: OAuthAppConfiguration? {
            switch self {
            case .notConfigured:
                return nil
            case .configured(let configuration):
                return configuration
            }
        }
    }

    public static let githubAuthorizeURL = URL(string: "https://github.com/login/oauth/authorize")!
    public static let githubAccessTokenURL = URL(string: "https://github.com/login/oauth/access_token")!
    public static let defaultRedirectURI = URL(string: "ghorchestrator://oauth/callback")!
    public static let defaultScopes = ["repo"]

    public let clientID: String
    public let clientSecret: String
    public let authorizeURL: URL
    public let accessTokenURL: URL
    public let redirectURI: URL
    public let scopes: [String]

    public init(
        clientID: String,
        clientSecret: String,
        authorizeURL: URL = OAuthAppConfiguration.githubAuthorizeURL,
        accessTokenURL: URL = OAuthAppConfiguration.githubAccessTokenURL,
        redirectURI: URL = OAuthAppConfiguration.defaultRedirectURI,
        scopes: [String] = OAuthAppConfiguration.defaultScopes
    ) {
        self.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.clientSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        self.authorizeURL = authorizeURL
        self.accessTokenURL = accessTokenURL
        self.redirectURI = redirectURI
        self.scopes = Self.normalizedScopes(scopes)
    }

    public static func resolve(
        clientID: String?,
        clientSecret: String?,
        authorizeURL: URL = OAuthAppConfiguration.githubAuthorizeURL,
        accessTokenURL: URL = OAuthAppConfiguration.githubAccessTokenURL,
        redirectURI: URL = OAuthAppConfiguration.defaultRedirectURI,
        scopes: [String] = OAuthAppConfiguration.defaultScopes
    ) -> Resolution {
        let normalizedClientID = clientID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedClientSecret = clientSecret?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !normalizedClientID.isEmpty, !normalizedClientSecret.isEmpty else {
            return .notConfigured
        }

        return .configured(
            OAuthAppConfiguration(
                clientID: normalizedClientID,
                clientSecret: normalizedClientSecret,
                authorizeURL: authorizeURL,
                accessTokenURL: accessTokenURL,
                redirectURI: redirectURI,
                scopes: scopes
            )
        )
    }

    public func authorizationURL(
        state: OAuthState,
        codeChallenge: OAuthCodeChallenge
    ) -> URL {
        var components = URLComponents(
            url: authorizeURL,
            resolvingAgainstBaseURL: false
        ) ?? URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state.rawValue),
            URLQueryItem(name: "code_challenge", value: codeChallenge.rawValue),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        return components.url ?? authorizeURL
    }

    private static func normalizedScopes(_ scopes: [String]) -> [String] {
        let normalized = scopes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !normalized.isEmpty else {
            return defaultScopes
        }

        var deduplicated: [String] = []
        var seen = Set<String>()

        for scope in normalized where seen.insert(scope).inserted {
            deduplicated.append(scope)
        }

        return deduplicated
    }
}
