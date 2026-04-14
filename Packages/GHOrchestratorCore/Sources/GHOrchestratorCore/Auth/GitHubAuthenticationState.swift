import Foundation

public enum GitHubAuthenticationState: Equatable, Sendable {
    case notConfigured
    case signedOut
    case authorizing(userCode: String?, verificationURI: URL?)
    case authenticated(username: String)
    case authFailure(message: String)
}
