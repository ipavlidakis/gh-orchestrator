import AppKit
import GHOrchestratorCore
import Observation

@MainActor
protocol GitHubAuthControlling: AnyObject {
    var state: GitHubAuthenticationState { get }
    func startSignIn()
    func handleCallbackURL(_ url: URL)
    func signOut()
}

@MainActor
@Observable
final class GitHubAuthController: GitHubAuthControlling {
    private let configurationProvider: any GitHubOAuthConfigurationProviding
    private let apiClient: any GitHubAPIClient
    private let credentialStore: any GitHubCredentialStore
    private let urlOpener: any ExternalURLOpening

    @ObservationIgnored
    private var pendingAuthorization: PendingAuthorization?

    var state: GitHubAuthenticationState

    init(
        configurationProvider: any GitHubOAuthConfigurationProviding = BundleGitHubOAuthConfigurationProvider(),
        apiClient: any GitHubAPIClient = URLSessionGitHubAPIClient(),
        credentialStore: any GitHubCredentialStore = KeychainGitHubCredentialStore(),
        urlOpener: any ExternalURLOpening = WorkspaceExternalURLOpener()
    ) {
        self.configurationProvider = configurationProvider
        self.apiClient = apiClient
        self.credentialStore = credentialStore
        self.urlOpener = urlOpener
        self.state = Self.initialState(
            configurationResolution: configurationProvider.configurationResolution(),
            credentialStore: credentialStore
        )
    }

    func startSignIn() {
        guard case .configured(let configuration) = configurationProvider.configurationResolution() else {
            pendingAuthorization = nil
            state = .notConfigured
            return
        }

        let verifier = OAuthCodeVerifier.generate()
        let authState = OAuthState.generate()
        let authorizationURL = configuration.authorizationURL(
            state: authState,
            codeChallenge: verifier.codeChallenge
        )

        pendingAuthorization = PendingAuthorization(
            configuration: configuration,
            state: authState,
            verifier: verifier
        )

        guard urlOpener.open(authorizationURL) else {
            pendingAuthorization = nil
            state = .authFailure(message: "Unable to open GitHub sign-in in the browser.")
            return
        }

        state = .authorizing
    }

    func handleCallbackURL(_ url: URL) {
        guard let pendingAuthorization else {
            state = .authFailure(message: "No GitHub sign-in is currently in progress.")
            return
        }

        let callback: OAuthCallback
        do {
            callback = try OAuthCallback(
                url: url,
                expectedState: pendingAuthorization.state,
                redirectURI: pendingAuthorization.configuration.redirectURI
            )
        } catch {
            self.pendingAuthorization = nil
            state = .authFailure(message: error.localizedDescription)
            return
        }

        state = .authorizing

        Task { @MainActor in
            await exchangeCode(
                with: pendingAuthorization.configuration,
                callback: callback,
                verifier: pendingAuthorization.verifier
            )
        }
    }

    func signOut() {
        pendingAuthorization = nil

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
    func exchangeCode(
        with configuration: OAuthAppConfiguration,
        callback: OAuthCallback,
        verifier: OAuthCodeVerifier
    ) async {
        defer {
            pendingAuthorization = nil
        }

        do {
            let session = try await apiClient.exchangeCode(
                configuration: configuration,
                callback: callback,
                codeVerifier: verifier
            )

            if let username = session.username, !username.isEmpty {
                state = .authenticated(username: username)
            } else {
                state = .authFailure(message: "GitHub login succeeded, but the connected account name could not be resolved.")
            }
        } catch {
            state = .authFailure(message: error.localizedDescription)
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

private struct PendingAuthorization {
    let configuration: OAuthAppConfiguration
    let state: OAuthState
    let verifier: OAuthCodeVerifier
}

protocol GitHubOAuthConfigurationProviding: Sendable {
    func configurationResolution() -> OAuthAppConfiguration.Resolution
}

struct BundleGitHubOAuthConfigurationProvider: GitHubOAuthConfigurationProviding {
    static let clientIDInfoKey = "GitHubOAuthClientID"
    static let clientSecretInfoKey = "GitHubOAuthClientSecret"
    static let clientIDEnvironmentKey = "GH_ORCHESTRATOR_GITHUB_CLIENT_ID"
    static let clientSecretEnvironmentKey = "GH_ORCHESTRATOR_GITHUB_CLIENT_SECRET"

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
        let environmentClientSecret = environment[Self.clientSecretEnvironmentKey]
        let bundleClientID = bundle.object(forInfoDictionaryKey: Self.clientIDInfoKey) as? String
        let bundleClientSecret = bundle.object(forInfoDictionaryKey: Self.clientSecretInfoKey) as? String

        return OAuthAppConfiguration.resolve(
            clientID: environmentClientID ?? bundleClientID,
            clientSecret: environmentClientSecret ?? bundleClientSecret
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
