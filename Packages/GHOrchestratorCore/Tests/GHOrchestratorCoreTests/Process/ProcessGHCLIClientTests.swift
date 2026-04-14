import XCTest
@testable import GHOrchestratorCore

final class ProcessGHCLIClientTests: XCTestCase {
    func testHealthReturnsMissingWhenGhBinaryCannotBeFound() {
        let runner = MockProcessRunner { command in
            XCTAssertEqual(command.command, "gh")
            XCTAssertEqual(command.arguments, ["--version"])
            return ProcessOutput(
                exitCode: 127,
                standardOutput: "",
                standardError: "env: gh: No such file or directory\n"
            )
        }

        let client = ProcessGHCLIClient(runner: runner)

        XCTAssertEqual(client.health(), .missing)
        XCTAssertEqual(runner.invocations.map(\.arguments), [["--version"]])
    }

    func testHealthReturnsLoggedOutWhenAuthStatusReportsNoLogin() {
        let runner = MockProcessRunner { command in
            switch command.arguments {
            case ["--version"]:
                return ProcessOutput(
                    exitCode: 0,
                    standardOutput: "gh version 2.0.0\n",
                    standardError: ""
                )
            case ["auth", "status", "--hostname", "github.com"]:
                return ProcessOutput(
                    exitCode: 1,
                    standardOutput: "",
                    standardError: """
                    github.com
                      X Not logged into any GitHub hosts. Run gh auth login to authenticate.
                    """
                )
            default:
                XCTFail("Unexpected invocation: \(command)")
                return ProcessOutput(exitCode: 1, standardOutput: "", standardError: "unexpected")
            }
        }

        let client = ProcessGHCLIClient(runner: runner)

        XCTAssertEqual(client.health(), .loggedOut)
        XCTAssertEqual(
            runner.invocations.map(\.arguments),
            [["--version"], ["auth", "status", "--hostname", "github.com"]]
        )
    }

    func testHealthReturnsAuthenticatedUsernameWhenAuthStatusReportsActiveAccount() {
        let runner = MockProcessRunner { command in
            switch command.arguments {
            case ["--version"]:
                return ProcessOutput(
                    exitCode: 0,
                    standardOutput: "gh version 2.0.0\n",
                    standardError: ""
                )
            case ["auth", "status", "--hostname", "github.com"]:
                return ProcessOutput(
                    exitCode: 0,
                    standardOutput: "",
                    standardError: """
                    github.com
                      ✓ Logged in to github.com account octocat (keyring)
                    """
                )
            default:
                XCTFail("Unexpected invocation: \(command)")
                return ProcessOutput(exitCode: 1, standardOutput: "", standardError: "unexpected")
            }
        }

        let client = ProcessGHCLIClient(runner: runner)

        XCTAssertEqual(client.health(), .authenticated(username: "octocat"))
        XCTAssertEqual(
            runner.invocations.map(\.arguments),
            [["--version"], ["auth", "status", "--hostname", "github.com"]]
        )
    }

    func testHealthReturnsCommandFailureForUnrecognizedAuthStatusOutput() {
        let runner = MockProcessRunner { command in
            switch command.arguments {
            case ["--version"]:
                return ProcessOutput(
                    exitCode: 0,
                    standardOutput: "gh version 2.0.0\n",
                    standardError: ""
                )
            case ["auth", "status", "--hostname", "github.com"]:
                return ProcessOutput(
                    exitCode: 2,
                    standardOutput: "",
                    standardError: "github.com\n  X unexpected failure\n"
                )
            default:
                XCTFail("Unexpected invocation: \(command)")
                return ProcessOutput(exitCode: 1, standardOutput: "", standardError: "unexpected")
            }
        }

        let client = ProcessGHCLIClient(runner: runner)

        switch client.health() {
        case .commandFailure(let message):
            XCTAssertTrue(message.contains("gh auth status --hostname github.com exited with code 2"))
            XCTAssertTrue(message.contains("unexpected failure"))
        default:
            XCTFail("Expected command failure")
        }

        XCTAssertEqual(
            runner.invocations.map(\.arguments),
            [["--version"], ["auth", "status", "--hostname", "github.com"]]
        )
    }
}

private final class MockProcessRunner: ProcessRunner, @unchecked Sendable {
    private let handler: (ProcessCommand) throws -> ProcessOutput
    private(set) var invocations: [ProcessCommand] = []

    init(handler: @escaping (ProcessCommand) throws -> ProcessOutput) {
        self.handler = handler
    }

    func run(_ command: ProcessCommand) throws -> ProcessOutput {
        invocations.append(command)
        return try handler(command)
    }
}
