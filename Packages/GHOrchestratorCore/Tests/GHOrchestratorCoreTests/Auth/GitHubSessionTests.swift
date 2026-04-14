import Foundation
import XCTest
@testable import GHOrchestratorCore

final class GitHubSessionTests: XCTestCase {
    func testTokenExchangeResponseMapsIntoSession() throws {
        let now = Date(timeIntervalSince1970: 1_710_000_000)
        let response = GitHubTokenExchangeResponse(
            accessToken: "access-token",
            tokenType: "bearer",
            scope: "repo,workflow",
            refreshToken: "refresh-token",
            expiresIn: 600,
            refreshTokenExpiresIn: 1_200
        )

        let session = try response.session(username: "octocat", now: now)

        XCTAssertEqual(session.accessToken, "access-token")
        XCTAssertEqual(session.tokenType, "bearer")
        XCTAssertEqual(session.scopes, ["repo", "workflow"])
        XCTAssertEqual(session.refreshToken, "refresh-token")
        XCTAssertEqual(session.accessTokenExpirationDate, now.addingTimeInterval(600))
        XCTAssertEqual(session.refreshTokenExpirationDate, now.addingTimeInterval(1_200))
        XCTAssertEqual(session.username, "octocat")
    }

    func testSessionRoundTripsThroughJSONCoding() throws {
        let session = GitHubSession(
            accessToken: "access-token",
            tokenType: "bearer",
            scopes: ["repo"],
            refreshToken: "refresh-token",
            accessTokenExpirationDate: Date(timeIntervalSince1970: 100),
            refreshTokenExpirationDate: Date(timeIntervalSince1970: 200),
            username: "octocat"
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(session)
        let decoded = try decoder.decode(GitHubSession.self, from: data)

        XCTAssertEqual(decoded, session)
    }

    func testTokenExchangeResponseRejectsMissingAccessToken() {
        let response = GitHubTokenExchangeResponse(tokenType: "bearer")

        XCTAssertThrowsError(try response.session()) { error in
            XCTAssertEqual(error as? GitHubTokenExchangeError, .missingAccessToken)
        }
    }
}
