import XCTest
@testable import GHOrchestrator
import GHOrchestratorCore

final class GHOrchestratorTests: XCTestCase {
    func testAppMetadataMatchesAppName() {
        XCTAssertEqual(AppMetadata.menuBarTitle, "GHOrchestrator")
    }

    func testCoreModuleExportsPlaceholderMessage() {
        XCTAssertEqual(GHOrchestratorCore.placeholderMessage, "GHOrchestratorCore")
    }
}
