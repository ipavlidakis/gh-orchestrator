import Foundation
import XCTest
@testable import GHOrchestrator
import GHOrchestratorCore

@MainActor
final class GitHubAuthControllerTests: XCTestCase {
    func testInitialStateIsNotConfiguredWhenClientIDIsMissing() {
        let controller = GitHubAuthController(
            configurationProvider: StubGitHubOAuthConfigurationProvider(clientID: nil),
            apiClient: StubGitHubAPIClient(),
            credentialStore: StubGitHubCredentialStore(),
            urlOpener: RecordingURLOpener()
        )

        XCTAssertEqual(controller.state, .notConfigured)
    }

    func testStartSignInOpensBrowserAndMovesToAuthorizing() throws {
        let urlOpener = RecordingURLOpener()
        let controller = GitHubAuthController(
            configurationProvider: StubGitHubOAuthConfigurationProvider(clientID: "abc123"),
            apiClient: StubGitHubAPIClient(),
            credentialStore: StubGitHubCredentialStore(),
            urlOpener: urlOpener
        )

        controller.startSignIn()

        XCTAssertEqual(controller.state, .authorizing)
        let openedURL = try XCTUnwrap(urlOpener.openedURLs.first)
        let components = try XCTUnwrap(URLComponents(url: openedURL, resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(openedURL.host, "github.com")
        XCTAssertEqual(openedURL.path, "/login/oauth/authorize")
        XCTAssertEqual(queryItems["client_id"], "abc123")
        XCTAssertEqual(queryItems["redirect_uri"], "ghorchestrator://oauth/callback")
        XCTAssertEqual(queryItems["scope"], "repo")
        XCTAssertEqual(queryItems["code_challenge_method"], "S256")
        XCTAssertNotNil(queryItems["state"])
    }

    func testHandleCallbackCompletesOAuthFlow() async throws {
        let urlOpener = RecordingURLOpener()
        let apiClient = StubGitHubAPIClient(
            exchangeResult: .success(
                GitHubSession(
                    accessToken: "access-token",
                    tokenType: "bearer",
                    scopes: ["repo"],
                    username: "octocat"
                )
            )
        )
        let controller = GitHubAuthController(
            configurationProvider: StubGitHubOAuthConfigurationProvider(clientID: "abc123"),
            apiClient: apiClient,
            credentialStore: StubGitHubCredentialStore(),
            urlOpener: urlOpener
        )

        controller.startSignIn()

        let openedURL = try XCTUnwrap(urlOpener.openedURLs.first)
        let stateValue = try XCTUnwrap(
            URLComponents(url: openedURL, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "state" })?
                .value
        )

        controller.handleCallbackURL(
            URL(string: "ghorchestrator://oauth/callback?code=oauth-code&state=\(stateValue)")!
        )

        await waitUntil("authenticated state") {
            controller.state == .authenticated(username: "octocat")
        }

        XCTAssertEqual(apiClient.receivedCallbackCode, "oauth-code")
    }

    func testHandleCallbackWithoutPendingAuthorizationProducesAuthFailure() {
        let controller = GitHubAuthController(
            configurationProvider: StubGitHubOAuthConfigurationProvider(clientID: "abc123"),
            apiClient: StubGitHubAPIClient(),
            credentialStore: StubGitHubCredentialStore(),
            urlOpener: RecordingURLOpener()
        )

        controller.handleCallbackURL(
            URL(string: "ghorchestrator://oauth/callback?code=oauth-code&state=unused")!
        )

        XCTAssertEqual(
            controller.state,
            .authFailure(message: "No GitHub sign-in is currently in progress.")
        )
    }

    func testSignOutDeletesStoredSessionAndReturnsToSignedOut() throws {
        let credentialStore = StubGitHubCredentialStore(
            session: GitHubSession(
                accessToken: "access-token",
                tokenType: "bearer",
                username: "octocat"
            )
        )
        let controller = GitHubAuthController(
            configurationProvider: StubGitHubOAuthConfigurationProvider(clientID: "abc123"),
            apiClient: StubGitHubAPIClient(),
            credentialStore: credentialStore,
            urlOpener: RecordingURLOpener()
        )

        controller.signOut()

        XCTAssertEqual(controller.state, .signedOut)
        XCTAssertTrue(credentialStore.didDeleteSession)
        XCTAssertNil(try credentialStore.loadSession())
    }

    private func waitUntil(
        _ description: String,
        timeoutIterations: Int = 100,
        condition: @escaping () -> Bool
    ) async {
        for _ in 0..<timeoutIterations {
            if condition() {
                return
            }

            await Task.yield()
        }

        XCTFail("Timed out waiting for \(description)")
    }
}

private struct StubGitHubOAuthConfigurationProvider: GitHubOAuthConfigurationProviding {
    let clientID: String?

    func configurationResolution() -> OAuthAppConfiguration.Resolution {
        OAuthAppConfiguration.resolve(clientID: clientID)
    }
}

private final class StubGitHubCredentialStore: GitHubCredentialStore, @unchecked Sendable {
    private var session: GitHubSession?
    private(set) var didDeleteSession = false

    init(session: GitHubSession? = nil) {
        self.session = session
    }

    func loadSession() throws -> GitHubSession? {
        session
    }

    func saveSession(_ session: GitHubSession) throws {
        self.session = session
    }

    func deleteSession() throws {
        didDeleteSession = true
        session = nil
    }
}

private final class RecordingURLOpener: ExternalURLOpening, @unchecked Sendable {
    private(set) var openedURLs: [URL] = []
    var shouldOpen = true

    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        return shouldOpen
    }
}

private final class StubGitHubAPIClient: GitHubAPIClient, @unchecked Sendable {
    enum ExchangeResult {
        case success(GitHubSession)
        case failure(Error)
    }

    var exchangeResult: ExchangeResult
    private(set) var receivedCallbackCode: String?

    init(exchangeResult: ExchangeResult = .success(GitHubSession(accessToken: "token", tokenType: "bearer", username: "octocat"))) {
        self.exchangeResult = exchangeResult
    }

    func get<Response>(_ path: String) async throws -> Response where Response : Decodable {
        fatalError("Unexpected get call for \(path)")
    }

    func graphQL<Response, Variables>(query: String, variables: Variables?) async throws -> Response where Response : Decodable, Variables : Encodable {
        fatalError("Unexpected graphQL call for \(query)")
    }

    func authenticatedUser() async throws -> GitHubAuthenticatedUser {
        GitHubAuthenticatedUser(login: "octocat")
    }

    func exchangeCode(
        configuration: OAuthAppConfiguration,
        callback: OAuthCallback,
        codeVerifier: OAuthCodeVerifier
    ) async throws -> GitHubSession {
        receivedCallbackCode = callback.code

        switch exchangeResult {
        case .success(let session):
            return session
        case .failure(let error):
            throw error
        }
    }
}
