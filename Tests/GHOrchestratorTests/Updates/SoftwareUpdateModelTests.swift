import XCTest
@testable import GHOrchestrator
import GHOrchestratorCore

@MainActor
final class SoftwareUpdateModelTests: XCTestCase {
    func testCheckForUpdatesStoresAvailableUpdate() async {
        let update = makeUpdate(version: "1.1.0")
        let model = SoftwareUpdateModel(
            store: SettingsStore(storageURL: makeIsolatedStorageURL()),
            checker: StubSoftwareUpdateChecker(result: .updateAvailable(update)),
            installer: RecordingSoftwareUpdateInstaller(),
            currentVersionProvider: { "1.0.0" }
        )

        await model.checkForUpdatesNow()

        XCTAssertEqual(model.state, .updateAvailable(update))
        XCTAssertNotNil(model.lastCheckedAt)
        XCTAssertTrue(model.canInstallUpdate)
    }

    func testCheckForUpdatesStoresFailureMessage() async {
        let model = SoftwareUpdateModel(
            store: SettingsStore(storageURL: makeIsolatedStorageURL()),
            checker: StubSoftwareUpdateChecker(error: SoftwareUpdateCheckError.invalidCurrentVersion("debug")),
            installer: RecordingSoftwareUpdateInstaller(),
            currentVersionProvider: { "debug" }
        )

        await model.checkForUpdatesNow()

        guard case .failed(let message) = model.state else {
            return XCTFail("Expected failed state.")
        }

        XCTAssertTrue(message.contains("current app version"))
    }

    func testInstallAvailableUpdateDelegatesToInstaller() async {
        let update = makeUpdate(version: "1.1.0")
        let installer = RecordingSoftwareUpdateInstaller()
        let model = SoftwareUpdateModel(
            store: SettingsStore(storageURL: makeIsolatedStorageURL()),
            checker: StubSoftwareUpdateChecker(result: .updateAvailable(update)),
            installer: installer,
            currentVersionProvider: { "1.0.0" }
        )

        await model.checkForUpdatesNow()
        await model.installAvailableUpdateNow()

        XCTAssertEqual(installer.installedUpdates, [update])
        XCTAssertEqual(model.state, .upToDate(version: "1.1.0"))
    }

    private func makeIsolatedStorageURL() -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GHOrchestrator.SoftwareUpdateModelTests.\(UUID().uuidString)", isDirectory: true)
        let storageURL = rootURL
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("GHOrchestrator", isDirectory: true)
            .appendingPathComponent("settings.json", isDirectory: false)

        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        return storageURL
    }

    private func makeUpdate(version: String) -> SoftwareUpdate {
        SoftwareUpdate(
            version: version,
            releaseName: "GHOrchestrator \(version)",
            releaseURL: URL(string: "https://github.com/ipavlidakis/gh-orchestrator/releases/tag/\(version)")!,
            downloadAsset: SoftwareUpdateAsset(
                name: "GHOrchestrator-\(version).dmg",
                url: URL(string: "https://downloads.example.test/GHOrchestrator-\(version).dmg")!,
                size: 1_024
            ),
            checksumAsset: SoftwareUpdateAsset(
                name: "GHOrchestrator-\(version).dmg.sha256.txt",
                url: URL(string: "https://downloads.example.test/GHOrchestrator-\(version).dmg.sha256.txt")!,
                size: 128
            )
        )
    }
}

struct StubSoftwareUpdateChecker: SoftwareUpdateChecking, @unchecked Sendable {
    let result: SoftwareUpdateCheckResult?
    let error: (any Error)?

    init(
        result: SoftwareUpdateCheckResult? = nil,
        error: (any Error)? = nil
    ) {
        self.result = result
        self.error = error
    }

    func checkForUpdates(currentVersion: String) async throws -> SoftwareUpdateCheckResult {
        if let error {
            throw error
        }

        return result ?? .upToDate(currentVersion: currentVersion)
    }
}

@MainActor
final class RecordingSoftwareUpdateInstaller: SoftwareUpdateInstalling {
    private(set) var installedUpdates: [SoftwareUpdate] = []
    var error: (any Error)?

    func install(_ update: SoftwareUpdate) async throws {
        if let error {
            throw error
        }

        installedUpdates.append(update)
    }
}
