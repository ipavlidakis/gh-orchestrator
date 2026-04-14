import Foundation

public protocol GHCLIClient: Sendable {
    func run(arguments: [String]) throws -> ProcessOutput
    func health() -> GitHubCLIHealth
}

public struct ProcessGHCLIClient: GHCLIClient {
    public let runner: any ProcessRunner
    public let command: String

    public init(
        runner: any ProcessRunner = FoundationProcessRunner(),
        command: String = "gh"
    ) {
        self.runner = runner
        self.command = command
    }

    public func run(arguments: [String]) throws -> ProcessOutput {
        try runner.run(
            ProcessCommand(
                command: command,
                arguments: arguments
            )
        )
    }

    public func health() -> GitHubCLIHealth {
        do {
            let versionOutput = try run(arguments: ["--version"])

            if versionOutput.exitCode != 0 {
                return Self.healthForVersionFailure(versionOutput)
            }
        } catch let error as ProcessRunnerError {
            return Self.mapRunnerError(error)
        } catch {
            return .commandFailure(message: error.localizedDescription)
        }

        do {
            let statusOutput = try run(arguments: ["auth", "status", "--hostname", "github.com"])
            return Self.healthForAuthStatus(statusOutput)
        } catch let error as ProcessRunnerError {
            return Self.mapRunnerError(error)
        } catch {
            return .commandFailure(message: error.localizedDescription)
        }
    }
}

extension ProcessGHCLIClient {
    private static func mapRunnerError(_ error: ProcessRunnerError) -> GitHubCLIHealth {
        switch error {
        case .executableNotFound:
            return .missing
        case .launchFailure(_, let message):
            return .commandFailure(message: message)
        }
    }

    private static func healthForVersionFailure(_ output: ProcessOutput) -> GitHubCLIHealth {
        if isMissingBinary(output) {
            return .missing
        }

        return .commandFailure(message: failureMessage(for: "gh --version", output: output))
    }

    private static func healthForAuthStatus(_ output: ProcessOutput) -> GitHubCLIHealth {
        let text = output.combinedOutput

        if isLoggedOut(text) {
            return .loggedOut
        }

        if output.exitCode == 0, let username = authenticatedUsername(from: text) {
            return .authenticated(username: username)
        }

        return .commandFailure(message: failureMessage(for: "gh auth status --hostname github.com", output: output))
    }

    private static func isMissingBinary(_ output: ProcessOutput) -> Bool {
        if output.exitCode == 127 || output.exitCode == 126 {
            return true
        }

        let text = output.combinedOutput.lowercased()
        return text.contains("no such file or directory") || text.contains("not found")
    }

    private static func isLoggedOut(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.contains("not logged into any github hosts")
            || lowercased.contains("not logged in")
    }

    private static func authenticatedUsername(from text: String) -> String? {
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.localizedCaseInsensitiveContains("logged in to") else {
                continue
            }

            guard let accountRange = line.range(of: "account ", options: [.caseInsensitive]) else {
                continue
            }

            let suffix = line[accountRange.upperBound...]
            let username = suffix.split(whereSeparator: { $0.isWhitespace || $0 == "(" || $0 == "[" }).first.map(String.init)

            if let username, !username.isEmpty {
                return username
            }
        }

        return nil
    }

    private static func failureMessage(for command: String, output: ProcessOutput) -> String {
        let combinedOutput = output.combinedOutput

        if combinedOutput.isEmpty {
            return "\(command) exited with code \(output.exitCode)"
        }

        return "\(command) exited with code \(output.exitCode): \(combinedOutput)"
    }
}
