import XCTest
@testable import GHOrchestratorCore

final class FoundationProcessRunnerTests: XCTestCase {
    func testRunFindsExecutableInFallbackSearchPathsWhenPATHDoesNotContainIt() throws {
        let toolDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FoundationProcessRunnerTests.\(UUID().uuidString)", isDirectory: true)
        let toolURL = toolDirectory.appendingPathComponent("fake-gh")

        try FileManager.default.createDirectory(at: toolDirectory, withIntermediateDirectories: true)
        try """
        #!/bin/sh
        echo "fallback-runner"
        """.write(to: toolURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: toolURL.path
        )

        addTeardownBlock {
            try? FileManager.default.removeItem(at: toolDirectory)
        }

        let runner = FoundationProcessRunner(fallbackSearchPaths: [toolDirectory.path])
        let output = try runner.run(
            ProcessCommand(
                command: "fake-gh",
                environment: ["PATH": "/usr/bin:/bin"]
            )
        )

        XCTAssertEqual(output.exitCode, 0)
        XCTAssertEqual(output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines), "fallback-runner")
    }
}
