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

    func testAppMetadataHelpURLTargetsRepository() {
        XCTAssertEqual(
            AppMetadata.helpURL.absoluteString,
            "https://github.com/ipavlidakis/gh-orchestrator"
        )
    }

    func testAppMetadataOAuthSetupURLsTargetGitHubRegistrationAndDocs() {
        XCTAssertEqual(
            AppMetadata.gitHubOAuthAppRegistrationURL.absoluteString,
            "https://github.com/settings/applications/new"
        )
        XCTAssertEqual(
            AppMetadata.gitHubOAuthAppDocsURL.absoluteString,
            "https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app"
        )
    }
}
