import AppKit
import XCTest
@testable import GHOrchestrator

@MainActor
final class SettingsWindowMenuVisibilityControllerTests: XCTestCase {
    func testHidesAndRestoresOnlyTargetedTopLevelMenus() {
        let mainMenu = NSMenu(title: "Main")
        let appItem = NSMenuItem(title: AppMetadata.menuBarTitle, action: nil, keyEquivalent: "")
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let viewItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let helpItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")

        [appItem, fileItem, editItem, viewItem, windowItem, helpItem].forEach { item in
            mainMenu.addItem(item)
        }

        let controller = SettingsWindowMenuVisibilityController(
            mainMenuProvider: { mainMenu }
        )

        controller.setSettingsWindowActive(true)

        XCTAssertFalse(appItem.isHidden)
        XCTAssertFalse(fileItem.isHidden)
        XCTAssertTrue(editItem.isHidden)
        XCTAssertTrue(viewItem.isHidden)
        XCTAssertTrue(windowItem.isHidden)
        XCTAssertFalse(helpItem.isHidden)

        controller.setSettingsWindowActive(false)

        XCTAssertFalse(editItem.isHidden)
        XCTAssertFalse(viewItem.isHidden)
        XCTAssertFalse(windowItem.isHidden)
    }
}
