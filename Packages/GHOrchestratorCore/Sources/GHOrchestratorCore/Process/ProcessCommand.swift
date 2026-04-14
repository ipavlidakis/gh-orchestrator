import Foundation

public struct ProcessCommand: Equatable, Sendable {
    public let command: String
    public let arguments: [String]
    public let environment: [String: String]?
    public let currentDirectoryURL: URL?

    public init(
        command: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectoryURL: URL? = nil
    ) {
        self.command = command
        self.arguments = arguments
        self.environment = environment
        self.currentDirectoryURL = currentDirectoryURL
    }
}

