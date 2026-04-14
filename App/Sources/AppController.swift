import Foundation
import GHOrchestratorCore
import Observation

@MainActor
@Observable
final class AppController {
    let settingsStore: SettingsStore
    let authController: any GitHubAuthControlling
    let dashboardModel: MenuBarDashboardModel
    let settingsModel: SettingsModel
    private let dockIconVisibilityController: any DockIconVisibilityControlling

    @ObservationIgnored
    private var callbackObserver: NSObjectProtocol?

    init(
        settingsStore: SettingsStore = SettingsStore(),
        dataSource: (any DashboardDataSource)? = nil,
        authController: (any GitHubAuthControlling)? = nil,
        sleeper: any DashboardSleepProviding = TaskSleepProvider(),
        dockIconVisibilityController: any DockIconVisibilityControlling = DockIconVisibilityController()
    ) {
        self.settingsStore = settingsStore
        self.dockIconVisibilityController = dockIconVisibilityController

        let credentialStore = KeychainGitHubCredentialStore()
        let apiClient = URLSessionGitHubAPIClient(credentialStore: credentialStore)
        let resolvedAuthController = authController ?? GitHubAuthController(
            apiClient: apiClient,
            credentialStore: credentialStore
        )
        let resolvedDataSource = dataSource ?? LiveDashboardDataSource(client: apiClient)

        self.authController = resolvedAuthController
        self.dashboardModel = MenuBarDashboardModel(
            settingsStore: settingsStore,
            dataSource: resolvedDataSource,
            sleeper: sleeper,
            authenticationState: resolvedAuthController.state
        )
        self.settingsModel = SettingsModel(
            store: settingsStore,
            authenticationState: resolvedAuthController.state,
            manualRefreshAction: { [dashboardModel] in
                dashboardModel.refresh()
            },
            signInAction: { [resolvedAuthController] in
                resolvedAuthController.startSignIn()
            },
            signOutAction: { [resolvedAuthController] in
                resolvedAuthController.signOut()
            }
        )

        GitHubAuthURLHandler.shared.installIfNeeded()
        observeIncomingURLs()
        observeAuthenticationState()
        observeDockIconPreference()
        Task { @MainActor [weak self] in
            self?.applyDockIconPreference()
        }
    }

    func handleIncomingURL(_ url: URL) {
        authController.handleCallbackURL(url)
    }

    deinit {
        if let callbackObserver {
            NotificationCenter.default.removeObserver(callbackObserver)
        }
    }

    private func observeAuthenticationState() {
        withObservationTracking {
            _ = authController.state
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else {
                    return
                }

                let state = self.authController.state
                self.settingsModel.authenticationState = state
                self.dashboardModel.setAuthenticationState(state)
                self.observeAuthenticationState()
            }
        }
    }

    private func observeIncomingURLs() {
        callbackObserver = NotificationCenter.default.addObserver(
            forName: .gitHubOAuthCallbackReceived,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let url = notification.object as? URL else {
                return
            }

            Task { @MainActor [weak self] in
                self?.handleIncomingURL(url)
            }
        }
    }

    private func observeDockIconPreference() {
        withObservationTracking {
            _ = settingsStore.settings.hideDockIcon
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.applyDockIconPreference()
                self.observeDockIconPreference()
            }
        }
    }

    private func applyDockIconPreference() {
        dockIconVisibilityController.apply(hideDockIcon: settingsStore.settings.hideDockIcon)
    }
}
