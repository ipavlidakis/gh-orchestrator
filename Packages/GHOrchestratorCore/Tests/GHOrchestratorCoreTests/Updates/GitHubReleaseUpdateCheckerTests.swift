import XCTest
@testable import GHOrchestratorCore

final class GitHubReleaseUpdateCheckerTests: XCTestCase {
    func testCheckForUpdatesReturnsLatestDMGReleaseWhenVersionIsNewer() async throws {
        let transport = StubGitHubHTTPTransport(results: [
            .success(
                data: releasePayload(
                    tagName: "v1.2.0",
                    assets: [
                        assetPayload(name: "GHOrchestrator-1.2.0.dmg", url: "https://downloads.example.test/GHOrchestrator-1.2.0.dmg"),
                        assetPayload(name: "GHOrchestrator-1.2.0.dmg.sha256.txt", url: "https://downloads.example.test/GHOrchestrator-1.2.0.dmg.sha256.txt"),
                    ]
                ),
                response: makeHTTPResponse(url: "https://api.example.test/repos/ipavlidakis/gh-orchestrator/releases/latest", statusCode: 200)
            )
        ])
        let checker = GitHubReleaseUpdateChecker(
            owner: "ipavlidakis",
            repository: "gh-orchestrator",
            transport: transport,
            apiBaseURL: URL(string: "https://api.example.test")!
        )

        let result = try await checker.checkForUpdates(currentVersion: "1.1.0")

        guard case .updateAvailable(let update) = result else {
            return XCTFail("Expected an available update.")
        }

        XCTAssertEqual(update.version, "1.2.0")
        XCTAssertEqual(update.releaseName, "GHOrchestrator 1.2.0")
        XCTAssertEqual(update.releaseNotes, "Release notes")
        XCTAssertEqual(update.downloadAsset.name, "GHOrchestrator-1.2.0.dmg")
        XCTAssertEqual(update.checksumAsset.name, "GHOrchestrator-1.2.0.dmg.sha256.txt")

        let request = await transport.recordedRequests().first
        XCTAssertEqual(
            request?.url?.absoluteString,
            "https://api.example.test/repos/ipavlidakis/gh-orchestrator/releases/latest"
        )
        XCTAssertEqual(request?.httpMethod, "GET")
        XCTAssertNil(request?.value(forHTTPHeaderField: "Authorization"))
    }

    func testCheckForUpdatesReturnsUpToDateWhenLatestVersionIsNotNewer() async throws {
        let transport = StubGitHubHTTPTransport(results: [
            .success(
                data: releasePayload(tagName: "1.2.0", assets: []),
                response: makeHTTPResponse(url: "https://api.example.test/repos/ipavlidakis/gh-orchestrator/releases/latest", statusCode: 200)
            )
        ])
        let checker = GitHubReleaseUpdateChecker(
            transport: transport,
            apiBaseURL: URL(string: "https://api.example.test")!
        )

        let result = try await checker.checkForUpdates(currentVersion: "1.2.0")

        XCTAssertEqual(result, .upToDate(currentVersion: "1.2.0"))
    }

    func testCheckForUpdatesRequiresChecksumAssetForNewerRelease() async throws {
        let transport = StubGitHubHTTPTransport(results: [
            .success(
                data: releasePayload(
                    tagName: "1.2.0",
                    assets: [
                        assetPayload(name: "GHOrchestrator-1.2.0.dmg", url: "https://downloads.example.test/GHOrchestrator-1.2.0.dmg")
                    ]
                ),
                response: makeHTTPResponse(url: "https://api.example.test/repos/ipavlidakis/gh-orchestrator/releases/latest", statusCode: 200)
            )
        ])
        let checker = GitHubReleaseUpdateChecker(
            transport: transport,
            apiBaseURL: URL(string: "https://api.example.test")!
        )

        do {
            _ = try await checker.checkForUpdates(currentVersion: "1.1.0")
            XCTFail("Expected missing checksum failure.")
        } catch let error as SoftwareUpdateCheckError {
            XCTAssertEqual(error, .missingChecksumAsset("GHOrchestrator-1.2.0.dmg"))
        }
    }

    func testCheckForUpdatesRejectsInvalidCurrentVersion() async {
        let checker = GitHubReleaseUpdateChecker()

        do {
            _ = try await checker.checkForUpdates(currentVersion: "debug")
            XCTFail("Expected invalid current version failure.")
        } catch let error as SoftwareUpdateCheckError {
            XCTAssertEqual(error, .invalidCurrentVersion("debug"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func releasePayload(
        tagName: String,
        assets: [String]
    ) -> Data {
        let payload = """
        {
          "tag_name": "\(tagName)",
          "name": "GHOrchestrator \(tagName.trimmingPrefix("v"))",
          "body": "Release notes",
          "html_url": "https://github.com/ipavlidakis/gh-orchestrator/releases/tag/\(tagName)",
          "published_at": "2026-04-15T08:00:00Z",
          "assets": [
            \(assets.joined(separator: ",\n"))
          ]
        }
        """

        return Data(payload.utf8)
    }

    private func assetPayload(
        name: String,
        url: String
    ) -> String {
        """
        {
          "name": "\(name)",
          "browser_download_url": "\(url)",
          "size": 2048,
          "content_type": "application/octet-stream"
        }
        """
    }
}

private extension String {
    func trimmingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
