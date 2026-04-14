import XCTest
@testable import GHOrchestrator
import GHOrchestratorCore

final class SettingsModelTests: XCTestCase {
    func testManualRefreshHookInvokesAssignedAction() {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        var refreshCount = 0
        let model = SettingsModel(store: store, manualRefreshAction: {
            refreshCount += 1
        })

        XCTAssertTrue(model.hasManualRefreshAction)

        model.requestManualRefresh()

        XCTAssertEqual(refreshCount, 1)
    }

    func testInvalidRepositoryInputSurfacesValidationMessagesAndPersistsValidEntries() {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        let model = SettingsModel(store: store)

        model.repositoryText = """
        openai/codex
        invalid entry
        swiftlang/swift
        """

        XCTAssertEqual(
            store.settings.observedRepositories.map(\.fullName),
            ["openai/codex", "swiftlang/swift"]
        )
        XCTAssertEqual(
            model.repositoryValidationMessages,
            ["Invalid repository entry: invalid entry"]
        )
    }

    func testPollingIntervalPersistenceClampsAndWritesImmediately() {
        let storageURL = makeIsolatedStorageURL()
        let store = SettingsStore(storageURL: storageURL)
        let model = SettingsModel(store: store)

        model.pollingIntervalText = "1"

        XCTAssertEqual(model.pollingIntervalText, "15")
        XCTAssertEqual(store.settings.pollingIntervalSeconds, 15)

        let reloadedStore = SettingsStore(storageURL: storageURL)

        XCTAssertEqual(reloadedStore.settings.pollingIntervalSeconds, 15)
    }

    func testHideDockIconPersistenceWritesImmediately() {
        let storageURL = makeIsolatedStorageURL()
        let store = SettingsStore(storageURL: storageURL)
        let model = SettingsModel(store: store)

        XCTAssertFalse(model.hideDockIcon)

        model.hideDockIcon = true

        XCTAssertTrue(store.settings.hideDockIcon)

        let reloadedStore = SettingsStore(storageURL: storageURL)

        XCTAssertTrue(reloadedStore.settings.hideDockIcon)
    }

    private func makeIsolatedStorageURL() -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GHOrchestrator.SettingsModelTests.\(UUID().uuidString)", isDirectory: true)
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
