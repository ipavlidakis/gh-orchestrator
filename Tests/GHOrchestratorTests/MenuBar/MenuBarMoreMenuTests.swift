import XCTest
@testable import GHOrchestrator
import GHOrchestratorCore

@MainActor
final class MenuBarMoreMenuTests: XCTestCase {
    func testActionHandlerRoutesEachAction() {
        var actions: [String] = []
        let handler = MenuBarMoreMenuActionHandler(
            refreshAction: {
                actions.append("refresh")
            },
            installUpdateAction: {
                actions.append("update")
            },
            openSettingsAction: {
                actions.append("settings")
            },
            quitAction: {
                actions.append("quit")
            }
        )

        handler.refresh()
        handler.installUpdate()
        handler.openSettings()
        handler.quit()

        XCTAssertEqual(actions, ["refresh", "update", "settings", "quit"])
    }

    func testUpdateActionIsHiddenWhenNoUpdateIsAvailable() {
        let model = makeSoftwareUpdateModel()

        XCTAssertNil(MenuBarMoreMenuUpdateAction(softwareUpdateModel: model))
    }

    func testUpdateActionUsesUpdateTitleWhenUpdateIsAvailable() throws {
        let update = makeUpdate(version: "1.1.0")
        let model = makeSoftwareUpdateModel()
        model.state = .updateAvailable(update)

        let action = try XCTUnwrap(MenuBarMoreMenuUpdateAction(softwareUpdateModel: model))

        XCTAssertEqual(action.title, "Update")
        XCTAssertTrue(action.isEnabled)
    }

    func testUpdateActionRemainsVisibleButDisabledWhileInstalling() throws {
        let update = makeUpdate(version: "1.1.0")
        let model = makeSoftwareUpdateModel()
        model.state = .installing(update)

        let action = try XCTUnwrap(MenuBarMoreMenuUpdateAction(softwareUpdateModel: model))

        XCTAssertEqual(action.title, "Updating...")
        XCTAssertFalse(action.isEnabled)
    }

    private func makeSoftwareUpdateModel() -> SoftwareUpdateModel {
        SoftwareUpdateModel(
            store: SettingsStore(storageURL: makeIsolatedStorageURL()),
            checker: StubSoftwareUpdateChecker(),
            installer: RecordingSoftwareUpdateInstaller(),
            currentVersionProvider: { "1.0.0" }
        )
    }

    private func makeIsolatedStorageURL() -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GHOrchestrator.MenuBarMoreMenuTests.\(UUID().uuidString)", isDirectory: true)
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
