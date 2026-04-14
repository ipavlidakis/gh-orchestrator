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

    func testAuthenticationDescriptionAndActionsReflectState() {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        var signInCount = 0
        var signOutCount = 0
        let model = SettingsModel(
            store: store,
            authenticationState: .signedOut,
            signInAction: { signInCount += 1 },
            signOutAction: { signOutCount += 1 }
        )

        XCTAssertEqual(model.authenticationDescription, "Not signed in")
        XCTAssertTrue(model.canStartSignIn)
        XCTAssertFalse(model.canSignOut)

        model.requestSignIn()
        XCTAssertEqual(signInCount, 1)

        model.authenticationState = .authenticated(username: "octocat")
        XCTAssertEqual(model.authenticationDescription, "Signed in as octocat")
        XCTAssertTrue(model.canSignOut)

        model.requestSignOut()
        XCTAssertEqual(signOutCount, 1)
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

    func testAddObservedRepositoryPersistsValidEntry() {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        let model = SettingsModel(store: store)

        let didAdd = model.addObservedRepository(from: "openai/codex")

        XCTAssertTrue(didAdd)
        XCTAssertEqual(store.settings.observedRepositories.map(\.fullName), ["openai/codex"])
        XCTAssertTrue(model.repositoryValidationMessages.isEmpty)
    }

    func testAddObservedRepositoryRejectsInvalidAndDuplicateEntries() {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        store.settings.observedRepositories = [ObservedRepository(owner: "openai", name: "codex")]
        let model = SettingsModel(store: store)

        XCTAssertFalse(model.addObservedRepository(from: "not valid"))
        XCTAssertEqual(model.repositoryValidationMessages, ["Invalid repository entry: not valid"])

        XCTAssertFalse(model.addObservedRepository(from: "OPENAI/CODEX"))
        XCTAssertEqual(model.repositoryValidationMessages, ["Repository already added: OPENAI/CODEX"])
    }

    func testRemoveObservedRepositoriesRemovesSelectedIDs() {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        store.settings.observedRepositories = [
            ObservedRepository(owner: "openai", name: "codex"),
            ObservedRepository(owner: "swiftlang", name: "swift"),
        ]
        let model = SettingsModel(store: store)

        model.removeObservedRepositories(withIDs: ["openai/codex"])

        XCTAssertEqual(store.settings.observedRepositories.map(\.fullName), ["swiftlang/swift"])
    }

    func testRemoveObservedRepositoriesNormalizesSelectedIDs() {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        store.settings.observedRepositories = [
            ObservedRepository(owner: "OpenAI", name: "Codex"),
            ObservedRepository(owner: "swiftlang", name: "swift"),
        ]
        let model = SettingsModel(store: store)

        model.removeObservedRepositories(withIDs: [" OPENAI/CODEX "])

        XCTAssertEqual(store.settings.observedRepositories.map(\.fullName), ["swiftlang/swift"])
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
