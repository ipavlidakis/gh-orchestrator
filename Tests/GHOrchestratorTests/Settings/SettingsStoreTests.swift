import XCTest
@testable import GHOrchestrator
import GHOrchestratorCore

final class SettingsStoreTests: XCTestCase {
    func testSettingsStoreRoundTripsThroughApplicationSupportFile() {
        let storageURL = makeIsolatedStorageURL()
        let expected = AppSettings(
            observedRepositories: [
                ObservedRepository(owner: "openai", name: "codex"),
                ObservedRepository(owner: "swiftlang", name: "swift")
            ],
            pollingIntervalSeconds: 120
        )

        let writer = SettingsStore(storageURL: storageURL)
        writer.settings = expected

        let reader = SettingsStore(storageURL: storageURL)

        XCTAssertEqual(reader.settings, expected)
    }

    private func makeIsolatedStorageURL() -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GHOrchestrator.SettingsStoreTests.\(UUID().uuidString)", isDirectory: true)
        let storageURL = rootURL
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("GHOrchestrator", isDirectory: true)
            .appendingPathComponent("settings.json", isDirectory: false)

        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        return storageURL
    }
}
