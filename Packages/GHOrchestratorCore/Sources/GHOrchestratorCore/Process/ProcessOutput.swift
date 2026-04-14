import Foundation

public struct ProcessOutput: Equatable, Sendable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String

    public var combinedOutput: String {
        let output = [standardOutput, standardError]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return output.joined(separator: "\n")
    }

    public init(
        exitCode: Int32,
        standardOutput: String,
        standardError: String
    ) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public enum ProcessRunnerError: Error, Equatable, Sendable {
    case executableNotFound(command: String)
    case launchFailure(command: String, message: String)
}

