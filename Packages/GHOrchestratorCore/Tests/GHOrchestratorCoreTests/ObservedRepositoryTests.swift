import XCTest
@testable import GHOrchestratorCore

final class ObservedRepositoryTests: XCTestCase {
    func testInitRawValueTrimsWhitespaceAroundOwnerAndRepository() {
        let repository = ObservedRepository(rawValue: "  openai / codex  ")

        XCTAssertEqual(repository?.owner, "openai")
        XCTAssertEqual(repository?.name, "codex")
        XCTAssertEqual(repository?.fullName, "openai/codex")
    }

    func testInitRawValueRejectsMalformedEntries() {
        XCTAssertNil(ObservedRepository(rawValue: ""))
        XCTAssertNil(ObservedRepository(rawValue: "openai"))
        XCTAssertNil(ObservedRepository(rawValue: "/codex"))
        XCTAssertNil(ObservedRepository(rawValue: "openai/"))
        XCTAssertNil(ObservedRepository(rawValue: "openai/codex/issues"))
        XCTAssertNil(ObservedRepository(rawValue: "open ai/codex"))
    }

    func testParseListIgnoresBlankLinesDeduplicatesAndCollectsInvalidEntries() {
        let result = ObservedRepository.parseList(
            from: """
              openai / codex

            OPENAI/CODEX
            swiftlang/swift
            invalid
            /missing-owner
            """
        )

        XCTAssertEqual(
            result.repositories.map(\.fullName),
            ["openai/codex", "swiftlang/swift"]
        )
        XCTAssertEqual(result.invalidEntries, ["invalid", "/missing-owner"])
    }
}
