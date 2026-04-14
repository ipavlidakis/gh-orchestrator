import XCTest
@testable import GHOrchestratorCore

final class OAuthAppConfigurationTests: XCTestCase {
    func testResolveReturnsNotConfiguredWhenClientIDIsMissing() {
        XCTAssertEqual(OAuthAppConfiguration.resolve(clientID: nil, clientSecret: "secret"), .notConfigured)
        XCTAssertEqual(OAuthAppConfiguration.resolve(clientID: "   ", clientSecret: "secret"), .notConfigured)
        XCTAssertEqual(OAuthAppConfiguration.resolve(clientID: "client", clientSecret: nil), .notConfigured)
    }

    func testResolveConfiguredNormalizesClientIDAndScopes() {
        let resolution = OAuthAppConfiguration.resolve(
            clientID: "  abc123  ",
            clientSecret: "  secret456  ",
            scopes: ["repo", "workflow", "repo", " "]
        )

        guard case .configured(let configuration) = resolution else {
            return XCTFail("Expected configured OAuth app configuration")
        }

        XCTAssertEqual(configuration.clientID, "abc123")
        XCTAssertEqual(configuration.clientSecret, "secret456")
        XCTAssertEqual(configuration.scopes, ["repo", "workflow"])
        XCTAssertEqual(configuration.redirectURI, OAuthAppConfiguration.defaultRedirectURI)
    }

    func testAuthorizationURLIncludesPKCEAndRedirectParameters() throws {
        let configuration = try XCTUnwrap(
            OAuthAppConfiguration.resolve(clientID: "abc123", clientSecret: "secret456").configuration
        )
        let state = try XCTUnwrap(OAuthState(rawValue: "state-token"))
        let challenge = OAuthCodeChallenge(rawValue: "challenge-token")

        let url = configuration.authorizationURL(state: state, codeChallenge: challenge)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/login/oauth/authorize")
        XCTAssertEqual(items["client_id"]!, "abc123")
        XCTAssertEqual(items["redirect_uri"]!, "ghorchestrator://oauth/callback")
        XCTAssertEqual(items["scope"]!, "repo")
        XCTAssertEqual(items["state"]!, "state-token")
        XCTAssertEqual(items["code_challenge"]!, "challenge-token")
        XCTAssertEqual(items["code_challenge_method"]!, "S256")
    }
}
