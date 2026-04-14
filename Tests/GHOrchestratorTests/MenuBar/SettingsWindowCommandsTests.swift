import XCTest
@testable import GHOrchestrator

@MainActor
final class SettingsWindowCommandsTests: XCTestCase {
    func testCommandHandlerRoutesEachAction() {
        var actions: [String] = []
        let handler = SettingsWindowCommandHandler(
            showAboutPanelAction: {
                actions.append("about")
            },
            refreshAction: {
                actions.append("refresh")
            },
            openSettingsAction: {
                actions.append("settings")
            },
            openHelpAction: {
                actions.append("help")
            },
            quitAction: {
                actions.append("quit")
            }
        )

        handler.showAboutPanel()
        handler.refresh()
        handler.openSettings()
        handler.openHelp()
        handler.quit()

        XCTAssertEqual(actions, ["about", "refresh", "settings", "help", "quit"])
    }
}
