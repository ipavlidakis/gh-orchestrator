import AppKit
import GHOrchestratorCore
import Observation

@MainActor
protocol GitHubAuthControlling: AnyObject {
    var state: GitHubAuthenticationState { get }
    func startSignIn()
    func signOut()
}

@MainActor
@Observable
final class GitHubAuthController: GitHubAuthControlling {
    private let configurationProvider: any GitHubOAuthConfigurationProviding
    private let apiClient: any GitHubAPIClient
    private let credentialStore: any GitHubCredentialStore
    private let urlOpener: any ExternalURLOpening
    private let sleeper: any DeviceAuthorizationSleepProviding

    @ObservationIgnored
    private var authorizationTask: Task<Void, Never>?

    var state: GitHubAuthenticationState

    init(
        configurationProvider: any GitHubOAuthConfigurationProviding = BundleGitHubOAuthConfigurationProvider(),
        apiClient: any GitHubAPIClient = URLSessionGitHubAPIClient(),
        credentialStore: any GitHubCredentialStore = KeychainGitHubCredentialStore(),
        urlOpener: any ExternalURLOpening = WorkspaceExternalURLOpener(),
        sleeper: any DeviceAuthorizationSleepProviding = TaskDeviceAuthorizationSleeper()
    ) {
        self.configurationProvider = configurationProvider
        self.apiClient = apiClient
        self.credentialStore = credentialStore
        self.urlOpener = urlOpener
        self.sleeper = sleeper
        self.state = Self.initialState(
            configurationResolution: configurationProvider.configurationResolution(),
            credentialStore: credentialStore
        )
    }

    deinit {
        authorizationTask?.cancel()
    }

    func startSignIn() {
        guard case .configured(let configuration) = configurationProvider.configurationResolution() else {
            authorizationTask?.cancel()
            state = .notConfigured
            return
        }

        authorizationTask?.cancel()
        state = .authorizing(userCode: nil, verificationURI: nil)

        authorizationTask = Task { @MainActor [weak self] in
            await self?.runDeviceAuthorization(with: configuration)
        }
    }

    func signOut() {
        authorizationTask?.cancel()

        do {
            try credentialStore.deleteSession()
        } catch {
            state = .authFailure(message: error.localizedDescription)
            return
        }

        guard case .configured = configurationProvider.configurationResolution() else {
            state = .notConfigured
            return
        }

        state = .signedOut
    }
}

private extension GitHubAuthController {
    func runDeviceAuthorization(with configuration: OAuthAppConfiguration) async {
        do {
            let authorization = try await apiClient.startDeviceAuthorization(
                configuration: configuration
            )
            guard !Task.isCancelled else {
                return
            }

            state = .authorizing(
                userCode: authorization.userCode,
                verificationURI: authorization.verificationURI
            )
            _ = urlOpener.open(authorization.verificationURI)

            try await pollDeviceAuthorization(
                configuration: configuration,
                authorization: authorization
            )
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }

            state = .authFailure(message: error.localizedDescription)
        }
    }

    func pollDeviceAuthorization(
        configuration: OAuthAppConfiguration,
        authorization: GitHubDeviceAuthorization
    ) async throws {
        var interval = authorization.interval
        let expirationDate = authorization.expirationDate()

        while !Task.isCancelled {
            if Date() >= expirationDate {
                state = .authFailure(message: GitHubDeviceAuthorizationError.expiredToken.localizedDescription)
                return
            }

            try await sleeper.sleep(for: .seconds(interval))
            guard !Task.isCancelled else {
                return
            }

            switch try await apiClient.pollDeviceAuthorization(
                configuration: configuration,
                deviceCode: authorization.deviceCode,
                interval: interval
            ) {
            case .pending(let nextInterval):
                interval = nextInterval
            case .success(let session):
                guard let username = session.username, !username.isEmpty else {
                    state = .authFailure(message: "GitHub login succeeded, but the connected account name could not be resolved.")
                    return
                }

                state = .authenticated(username: username)
                return
            }
        }
    }

    static func initialState(
        configurationResolution: OAuthAppConfiguration.Resolution,
        credentialStore: any GitHubCredentialStore
    ) -> GitHubAuthenticationState {
        guard case .configured = configurationResolution else {
            return .notConfigured
        }

        do {
            guard let session = try credentialStore.loadSession() else {
                return .signedOut
            }

            guard let username = session.username?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty else {
                return .signedOut
            }

            return .authenticated(username: username)
        } catch {
            return .authFailure(message: error.localizedDescription)
        }
    }
}

protocol GitHubOAuthConfigurationProviding: Sendable {
    func configurationResolution() -> OAuthAppConfiguration.Resolution
}

struct BundleGitHubOAuthConfigurationProvider: GitHubOAuthConfigurationProviding {
    static let clientIDInfoKey = "GitHubOAuthClientID"
    static let clientIDEnvironmentKey = "GH_ORCHESTRATOR_GITHUB_CLIENT_ID"

    let bundle: Bundle
    let environment: [String: String]

    init(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.bundle = bundle
        self.environment = environment
    }

    func configurationResolution() -> OAuthAppConfiguration.Resolution {
        let environmentClientID = environment[Self.clientIDEnvironmentKey]
        let bundleClientID = bundle.object(forInfoDictionaryKey: Self.clientIDInfoKey) as? String

        return OAuthAppConfiguration.resolve(
            clientID: environmentClientID ?? bundleClientID
        )
    }
}

protocol ExternalURLOpening: Sendable {
    func open(_ url: URL) -> Bool
}

struct WorkspaceExternalURLOpener: ExternalURLOpening {
    func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}

protocol DeviceAuthorizationSleepProviding: Sendable {
    func sleep(for duration: Duration) async throws
}

struct TaskDeviceAuthorizationSleeper: DeviceAuthorizationSleepProviding {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
