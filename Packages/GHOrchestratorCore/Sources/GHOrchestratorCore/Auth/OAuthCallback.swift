import Foundation

public struct OAuthCallback: Equatable, Sendable {
    public let code: String
    public let state: OAuthState

    public init(
        url: URL,
        expectedState: OAuthState,
        redirectURI: URL = OAuthAppConfiguration.defaultRedirectURI
    ) throws {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let redirectComponents = URLComponents(url: redirectURI, resolvingAgainstBaseURL: false)

        guard
            let components,
            let redirectComponents,
            components.scheme?.caseInsensitiveCompare(redirectComponents.scheme ?? "") == .orderedSame,
            components.host?.caseInsensitiveCompare(redirectComponents.host ?? "") == .orderedSame,
            components.path == redirectComponents.path
        else {
            throw OAuthCallbackError.invalidCallbackURL
        }

        let queryItems = components.queryItems ?? []

        if let errorCode = queryItems.firstValue(named: "error") {
            throw OAuthCallbackError.authorizationRejected(
                error: errorCode,
                description: queryItems.firstValue(named: "error_description")
            )
        }

        guard let code = queryItems.firstValue(named: "code"), !code.isEmpty else {
            throw OAuthCallbackError.missingCode
        }

        guard
            let stateValue = queryItems.firstValue(named: "state"),
            let state = OAuthState(rawValue: stateValue)
        else {
            throw OAuthCallbackError.missingState
        }

        guard state == expectedState else {
            throw OAuthCallbackError.stateMismatch(
                expected: expectedState.rawValue,
                received: state.rawValue
            )
        }

        self.code = code
        self.state = state
    }
}

public enum OAuthCallbackError: Equatable, LocalizedError, Sendable {
    case invalidCallbackURL
    case missingCode
    case missingState
    case stateMismatch(expected: String, received: String)
    case authorizationRejected(error: String, description: String?)

    public var errorDescription: String? {
        switch self {
        case .invalidCallbackURL:
            return "The OAuth callback URL did not match the expected redirect URI."
        case .missingCode:
            return "The OAuth callback URL did not include an authorization code."
        case .missingState:
            return "The OAuth callback URL did not include the expected state value."
        case .stateMismatch(let expected, let received):
            return "The OAuth callback state did not match. Expected \(expected), received \(received)."
        case .authorizationRejected(let error, let description):
            if let description, !description.isEmpty {
                return "GitHub rejected authorization with \(error): \(description)"
            }

            return "GitHub rejected authorization with \(error)."
        }
    }
}

private extension [URLQueryItem] {
    func firstValue(named name: String) -> String? {
        first { $0.name == name }?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
