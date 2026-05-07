import AppKit
import XCTest
@testable import GHOrchestrator

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
}
