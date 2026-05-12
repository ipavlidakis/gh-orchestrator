import AppKit
@testable import GHOrchestrator
import XCTest

@MainActor
final class MenuBarPopoverPresenterTests: XCTestCase {
    func testDashboardConfigurationPinsContentSize() {
        XCTAssertEqual(
            MenuBarPopoverConfiguration.dashboard.contentSize,
            CGSize(width: 440, height: 620)
        )
    }

    func testConfigurationAppliesStablePopoverSizing() {
        let popover = NSPopover()
        let configuration = MenuBarPopoverConfiguration(
            contentSize: CGSize(width: 440, height: 620)
        )

        configuration.apply(to: popover)

        XCTAssertEqual(popover.behavior, .transient)
        XCTAssertTrue(popover.animates)
        XCTAssertEqual(popover.contentSize, CGSize(width: 440, height: 620))
    }

    func testPerformSettingsMenuItemActionTriggersMainMenuSettingsCommand() {
        let target = RecordingSettingsMenuTarget()
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem(title: "GHOrchestrator", action: nil, keyEquivalent: "")
        let appMenu = NSMenu()
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(RecordingSettingsMenuTarget.openSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = target
        mainMenu.addItem(appMenuItem)
        mainMenu.setSubmenu(appMenu, for: appMenuItem)
        appMenu.addItem(settingsItem)

        XCTAssertTrue(MenuBarPopoverPresenter.performSettingsMenuItemAction(in: mainMenu))
        XCTAssertEqual(target.openSettingsCallCount, 1)
    }

    func testPerformSettingsMenuItemActionReturnsFalseWhenMainMenuHasNoSettingsCommand() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem(title: "GHOrchestrator", action: nil, keyEquivalent: "")
        mainMenu.addItem(appMenuItem)
        mainMenu.setSubmenu(NSMenu(), for: appMenuItem)

        XCTAssertFalse(MenuBarPopoverPresenter.performSettingsMenuItemAction(in: mainMenu))
    }
}

private final class RecordingSettingsMenuTarget: NSObject {
    private(set) var openSettingsCallCount = 0

    @objc
    func openSettings(_: Any?) {
        openSettingsCallCount += 1
    }
}
