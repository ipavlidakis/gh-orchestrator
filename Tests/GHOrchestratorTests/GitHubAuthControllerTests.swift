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

    func testStartSignInRequestsDeviceCodeAndOpensVerificationPage() async throws {
        let urlOpener = RecordingURLOpener()
        let apiClient = StubGitHubAPIClient(
            deviceAuthorization: GitHubDeviceAuthorization(
                deviceCode: "device-code",
                userCode: "WDJB-MJHT",
                verificationURI: URL(string: "https://github.com/login/device")!,
                expiresIn: 900,
                interval: 5
            ),
            pollResults: [.pending(nextInterval: 5)]
        )
        let controller = GitHubAuthController(
            configurationProvider: StubGitHubOAuthConfigurationProvider(clientID: "abc123"),
            apiClient: apiClient,
            credentialStore: StubGitHubCredentialStore(),
            urlOpener: urlOpener,
            sleeper: CancellingDeviceAuthorizationSleeper()
        )

        controller.startSignIn()

        await waitUntil("device authorization state") {
            controller.state == .authorizing(
                userCode: "WDJB-MJHT",
                verificationURI: URL(string: "https://github.com/login/device")!
            )
        }

        XCTAssertEqual(
            urlOpener.openedURLs,
            [URL(string: "https://github.com/login/device")!]
        )
        XCTAssertEqual(apiClient.startDeviceAuthorizationCallCount, 1)
    }

    func testStartSignInPollsUntilAuthenticated() async throws {
        let apiClient = StubGitHubAPIClient(
            deviceAuthorization: GitHubDeviceAuthorization(
                deviceCode: "device-code",
                userCode: "WDJB-MJHT",
                verificationURI: URL(string: "https://github.com/login/device")!,
                expiresIn: 900,
                interval: 5
            ),
            pollResults: [
                .pending(nextInterval: 5),
                .success(
                    GitHubSession(
                        accessToken: "access-token",
                        tokenType: "bearer",
                        scopes: ["repo"],
                        username: "octocat"
                    )
                )
            ]
        )
        let sleeper = RecordingDeviceAuthorizationSleeper()
        let controller = GitHubAuthController(
            configurationProvider: StubGitHubOAuthConfigurationProvider(clientID: "abc123"),
            apiClient: apiClient,
            credentialStore: StubGitHubCredentialStore(),
            urlOpener: RecordingURLOpener(),
            sleeper: sleeper
        )

        controller.startSignIn()

        await waitUntil("authenticated state") {
            controller.state == .authenticated(username: "octocat")
        }

        XCTAssertEqual(apiClient.polledDeviceCodes, ["device-code", "device-code"])
        let recordedDurations = await sleeper.recordedDurations
        XCTAssertEqual(recordedDurations, [.seconds(5), .seconds(5)])
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

    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        return true
    }
}

private actor RecordingDeviceAuthorizationSleeper: DeviceAuthorizationSleepProviding {
    private(set) var recordedDurations: [Duration] = []

    func sleep(for duration: Duration) async throws {
        recordedDurations.append(duration)
    }
}

private struct CancellingDeviceAuthorizationSleeper: DeviceAuthorizationSleepProviding {
    func sleep(for duration: Duration) async throws {
        _ = duration
        throw CancellationError()
    }
}

private final class StubGitHubAPIClient: GitHubAPIClient, @unchecked Sendable {
    let deviceAuthorization: GitHubDeviceAuthorization
    private var pollResults: [GitHubDeviceAuthorizationPollResult]
    private(set) var startDeviceAuthorizationCallCount = 0
    private(set) var polledDeviceCodes: [String] = []

    init(
        deviceAuthorization: GitHubDeviceAuthorization = GitHubDeviceAuthorization(
            deviceCode: "device-code",
            userCode: "WDJB-MJHT",
            verificationURI: URL(string: "https://github.com/login/device")!,
            expiresIn: 900,
            interval: 5
        ),
        pollResults: [GitHubDeviceAuthorizationPollResult] = []
    ) {
        self.deviceAuthorization = deviceAuthorization
        self.pollResults = pollResults
    }

    func get<Response>(_ path: String) async throws -> Response where Response: Decodable {
        fatalError("Unexpected get call for \(path)")
    }

    func graphQL<Response, Variables>(query: String, variables: Variables?) async throws -> Response where Response: Decodable, Variables: Encodable {
        fatalError("Unexpected graphQL call for \(query)")
    }

    func rerunWorkflowJob(
        repository _: ObservedRepository,
        jobID _: Int
    ) async throws {
        fatalError("Unexpected rerunWorkflowJob call")
    }

    func authenticatedUser() async throws -> GitHubAuthenticatedUser {
        GitHubAuthenticatedUser(login: "octocat")
    }

    func startDeviceAuthorization(
        configuration: OAuthAppConfiguration
    ) async throws -> GitHubDeviceAuthorization {
        startDeviceAuthorizationCallCount += 1
        XCTAssertEqual(configuration.clientID, "abc123")
        return deviceAuthorization
    }

    func pollDeviceAuthorization(
        configuration: OAuthAppConfiguration,
        deviceCode: String,
        interval: Int
    ) async throws -> GitHubDeviceAuthorizationPollResult {
        polledDeviceCodes.append(deviceCode)
        XCTAssertEqual(configuration.clientID, "abc123")
        XCTAssertEqual(interval, 5)

        guard !pollResults.isEmpty else {
            return .pending(nextInterval: interval)
        }

        return pollResults.removeFirst()
    }

    func exchangeCode(
        configuration: OAuthAppConfiguration,
        callback: OAuthCallback,
        codeVerifier: OAuthCodeVerifier
    ) async throws -> GitHubSession {
        fatalError("Unexpected exchangeCode call for \(configuration.clientID) \(callback.code) \(codeVerifier.rawValue)")
    }
}
