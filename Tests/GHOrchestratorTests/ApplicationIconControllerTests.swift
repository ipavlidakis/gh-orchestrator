import AppKit
import SwiftUI
import XCTest

@testable import GHOrchestrator

@MainActor
final class ApplicationIconControllerTests: XCTestCase {
    func testApplyUsesLightDockIconForLightColorScheme() {
        var appliedImage: NSImage?
        var loadedAssetNames: [String] = []
        let image = NSImage(size: NSSize(width: 16, height: 16))
        let subject = ApplicationIconController(
            setApplicationIconImage: { appliedImage = $0 },
            imageLoader: { name in
                loadedAssetNames.append(name)
                return image
            }
        )

        subject.apply(colorScheme: .light)

        XCTAssertEqual(loadedAssetNames, ["DockIconLight"])
        XCTAssertTrue(appliedImage === image)
    }

    func testApplyUsesDarkDockIconForDarkColorScheme() {
        var appliedImage: NSImage?
        var loadedAssetNames: [String] = []
        let image = NSImage(size: NSSize(width: 16, height: 16))
        let subject = ApplicationIconController(
            setApplicationIconImage: { appliedImage = $0 },
            imageLoader: { name in
                loadedAssetNames.append(name)
                return image
            }
        )

        subject.apply(colorScheme: .dark)

        XCTAssertEqual(loadedAssetNames, ["DockIconDark"])
        XCTAssertTrue(appliedImage === image)
    }

    func testApplyLeavesCurrentIconUntouchedWhenAssetIsMissing() {
        var applyCount = 0
        let subject = ApplicationIconController(
            setApplicationIconImage: { _ in
                applyCount += 1
            },
            imageLoader: { _ in nil }
        )

        subject.apply(colorScheme: .light)

        XCTAssertEqual(applyCount, 0)
    }
}
