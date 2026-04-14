public struct GitHubAuthenticatedUser: Codable, Equatable, Sendable {
    public let login: String

    public init(login: String) {
        self.login = login
    }
}
