public enum GitHubAuthenticationState: Equatable, Sendable {
    case notConfigured
    case signedOut
    case authorizing
    case authenticated(username: String)
    case authFailure(message: String)
}
