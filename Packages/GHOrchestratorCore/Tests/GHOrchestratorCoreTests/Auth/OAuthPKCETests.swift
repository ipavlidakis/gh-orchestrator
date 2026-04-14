import XCTest
@testable import GHOrchestratorCore

final class OAuthPKCETests: XCTestCase {
    func testGeneratedCodeVerifierUsesRFC7636AllowedCharacters() {
        let verifier = OAuthCodeVerifier.generate()

        XCTAssertTrue((43...128).contains(verifier.rawValue.count))
        XCTAssertTrue(
            verifier.rawValue.unicodeScalars.allSatisfy { scalar in
                switch scalar.value {
                case 45, 46, 95, 126:
                    return true
                case 48...57, 65...90, 97...122:
                    return true
                default:
                    return false
                }
            }
        )
    }

    func testCodeChallengeMatchesRFC7636Example() throws {
        let verifier = try XCTUnwrap(
            OAuthCodeVerifier(rawValue: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        )

        XCTAssertEqual(
            verifier.codeChallenge.rawValue,
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )
    }

    func testGeneratedStateIsNonEmptyAndUnique() {
        let firstState = OAuthState.generate()
        let secondState = OAuthState.generate()

        XCTAssertFalse(firstState.rawValue.isEmpty)
        XCTAssertFalse(secondState.rawValue.isEmpty)
        XCTAssertNotEqual(firstState, secondState)
    }
}
