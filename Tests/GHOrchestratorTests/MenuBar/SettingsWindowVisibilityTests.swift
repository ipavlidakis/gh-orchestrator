import AppKit
import GHOrchestratorCore
import SwiftUI
import XCTest
@testable import GHOrchestrator

@MainActor
final class SettingsWindowVisibilityTests: XCTestCase {
    func testClosingRetainedSettingsWindowReportsHiddenAndReopeningReportsVisible() async throws {
        let storageURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storageURL) }
        let store = SettingsStore(storageURL: storageURL)
        let model = SettingsModel(store: store)
        let updates = SoftwareUpdateModel(store: store, checker: GitHubReleaseUpdateChecker(), installer: DMGSoftwareUpdateInstaller())
        var visibility: [Bool] = []
        func waitForVisibility(_ expected: Bool) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(1))
            while visibility.last != expected && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        let hostingView = NSHostingView(rootView: SettingsWindowView(
            model: model,
            softwareUpdateModel: updates,
            requestLogModel: GitHubRequestLogModel(),
            menuVisibilityController: SettingsWindowMenuVisibilityController(mainMenuProvider: { nil }),
            onSettingsWindowVisibilityChange: { visibility.append($0) }
        ).environment(\.settingsGlassDisabled, true))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 820, height: 620), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        defer { window.orderOut(nil) }

        window.makeKeyAndOrderFront(nil)
        try await waitForVisibility(true)
        XCTAssertEqual(visibility.last, true)

        window.close()
        try await waitForVisibility(false)
        XCTAssertFalse(window.isVisible)
        XCTAssertTrue(window.contentView === hostingView, "SwiftUI may retain the Settings view after closing")
        XCTAssertEqual(visibility.last, false, "Closing a retained Settings view must end the Dock override")

        window.makeKeyAndOrderFront(nil)
        try await waitForVisibility(true)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(visibility.last, true, "Reopening the same Settings window must restore its Dock affordance")

        window.orderOut(nil)
        try await waitForVisibility(false)
        XCTAssertEqual(visibility.last, false, "Ordering Settings out must also end the Dock override")

        window.makeKeyAndOrderFront(nil)
        try await waitForVisibility(true)
        XCTAssertEqual(visibility.last, true)
        window.close()
        try await waitForVisibility(false)
        XCTAssertEqual(visibility.last, false)
    }
}
