import XCTest
@testable import GHOrchestratorCore

final class AppSettingsTests: XCTestCase {
    func testPollingIntervalUsesDefaultWhenNotProvided() {
        let settings = AppSettings()

        XCTAssertEqual(settings.pollingIntervalSeconds, AppSettings.defaultPollingIntervalSeconds)
    }

    func testPollingIntervalIsClampedToAllowedRange() {
        XCTAssertEqual(AppSettings(pollingIntervalSeconds: 1).pollingIntervalSeconds, 15)
        XCTAssertEqual(AppSettings(pollingIntervalSeconds: 60).pollingIntervalSeconds, 60)
        XCTAssertEqual(AppSettings(pollingIntervalSeconds: 9_999).pollingIntervalSeconds, 900)
    }

    func testObservedRepositoriesAreDeduplicatedByNormalizedNameKeepingFirstOccurrence() {
        let settings = AppSettings(
            observedRepositories: [
                ObservedRepository(owner: "openai", name: "codex"),
                ObservedRepository(owner: "OPENAI", name: "CODEX"),
                ObservedRepository(owner: "swiftlang", name: "swift")
            ]
        )

        XCTAssertEqual(
            settings.observedRepositories.map(\.fullName),
            ["openai/codex", "swiftlang/swift"]
        )
    }
}
