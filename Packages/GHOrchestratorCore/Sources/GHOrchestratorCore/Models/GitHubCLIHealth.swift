public enum GitHubCLIHealth: Equatable, Sendable {
    case missing
    case loggedOut
    case authenticated(username: String)
    case commandFailure(message: String)
}
