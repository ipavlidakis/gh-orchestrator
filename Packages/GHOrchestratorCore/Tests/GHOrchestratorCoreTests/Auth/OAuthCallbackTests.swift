import XCTest
@testable import GHOrchestratorCore

final class OAuthCallbackTests: XCTestCase {
    func testCallbackParsesMatchingCodeAndState() throws {
        let expectedState = try XCTUnwrap(OAuthState(rawValue: "state-123"))
        let callback = try OAuthCallback(
            url: URL(string: "ghorchestrator://oauth/callback?code=abc&state=state-123")!,
            expectedState: expectedState
        )

        XCTAssertEqual(callback.code, "abc")
        XCTAssertEqual(callback.state, expectedState)
    }

    func testCallbackRejectsInvalidRedirectURL() throws {
        let expectedState = try XCTUnwrap(OAuthState(rawValue: "state-123"))

        XCTAssertThrowsError(
            try OAuthCallback(
                url: URL(string: "ghorchestrator://wrong/callback?code=abc&state=state-123")!,
                expectedState: expectedState
            )
        ) { error in
            XCTAssertEqual(error as? OAuthCallbackError, .invalidCallbackURL)
        }
    }

    func testCallbackRejectsMissingCode() throws {
        let expectedState = try XCTUnwrap(OAuthState(rawValue: "state-123"))

        XCTAssertThrowsError(
            try OAuthCallback(
                url: URL(string: "ghorchestrator://oauth/callback?state=state-123")!,
                expectedState: expectedState
            )
        ) { error in
            XCTAssertEqual(error as? OAuthCallbackError, .missingCode)
        }
    }

    func testCallbackRejectsMismatchedState() throws {
        let expectedState = try XCTUnwrap(OAuthState(rawValue: "expected-state"))

        XCTAssertThrowsError(
            try OAuthCallback(
                url: URL(string: "ghorchestrator://oauth/callback?code=abc&state=received-state")!,
                expectedState: expectedState
            )
        ) { error in
            XCTAssertEqual(
                error as? OAuthCallbackError,
                .stateMismatch(expected: "expected-state", received: "received-state")
            )
        }
    }

    func testCallbackRejectsAuthorizationError() throws {
        let expectedState = try XCTUnwrap(OAuthState(rawValue: "state-123"))

        XCTAssertThrowsError(
            try OAuthCallback(
                url: URL(string: "ghorchestrator://oauth/callback?error=access_denied&error_description=User%20cancelled&state=state-123")!,
                expectedState: expectedState
            )
        ) { error in
            XCTAssertEqual(
                error as? OAuthCallbackError,
                .authorizationRejected(error: "access_denied", description: "User cancelled")
            )
        }
    }
}
