import AppKit
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
    let requestLogModel: GitHubRequestLogModel
    let notificationMonitor: RepositoryNotificationMonitor
    private let dockIconVisibilityController: any DockIconVisibilityControlling
    private let startAtLoginController: any StartAtLoginControlling
    private let notificationDelivery: any LocalNotificationDelivering
    private var isSettingsWindowVisible = false

    init(
        settingsStore: SettingsStore = SettingsStore(),
        dataSource: (any DashboardDataSource)? = nil,
        authController: (any GitHubAuthControlling)? = nil,
        sleeper: any DashboardSleepProviding = TaskSleepProvider(),
        requestLogModel: GitHubRequestLogModel? = nil,
        dockIconVisibilityController: any DockIconVisibilityControlling = DockIconVisibilityController(),
        startAtLoginController: any StartAtLoginControlling = StartAtLoginController(),
        notificationDelivery: (any LocalNotificationDelivering)? = nil,
        openURL: @escaping @MainActor (URL) -> Void = { url in
            NSWorkspace.shared.open(url)
        }
    ) {
        let resolvedRequestLogModel = requestLogModel ?? GitHubRequestLogModel()
        let resolvedNotificationDelivery = notificationDelivery ?? UserNotificationCenterDelivery(
            responseRouter: NotificationResponseRouter(openURL: openURL)
        )

        self.settingsStore = settingsStore
        self.requestLogModel = resolvedRequestLogModel
        self.dockIconVisibilityController = dockIconVisibilityController
        self.startAtLoginController = startAtLoginController
        self.notificationDelivery = resolvedNotificationDelivery

        let credentialStore = KeychainGitHubCredentialStore()
        let apiClient = URLSessionGitHubAPIClient(
            credentialStore: credentialStore,
            metricsRecorder: resolvedRequestLogModel
        )
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

        let settingsModelBox = WeakSettingsModelBox<SettingsModel>()
        var resolvedSettingsModel: SettingsModel!
        resolvedSettingsModel = SettingsModel(
            store: settingsStore,
            authenticationState: resolvedAuthController.state,
            startAtLoginRegistrationStatus: startAtLoginController.registrationStatus,
            manualRefreshAction: { [dashboardModel] in
                dashboardModel.refresh()
            },
            signInAction: { [resolvedAuthController] in
                resolvedAuthController.startSignIn()
            },
            signOutAction: { [resolvedAuthController] in
                resolvedAuthController.signOut()
            },
            requestNotificationAuthorizationAction: { [resolvedNotificationDelivery, settingsModelBox] in
                Task { @MainActor in
                    do {
                        settingsModelBox.value?.notificationAuthorizationStatus = try await resolvedNotificationDelivery.requestAuthorization()
                    } catch {
                        settingsModelBox.value?.notificationAuthorizationStatus = await resolvedNotificationDelivery.authorizationStatus()
                    }
                }
            },
            openLoginItemsSettingsAction: { [startAtLoginController] in
                startAtLoginController.openSystemSettingsLoginItems()
            },
            workflowListService: ActionsWorkflowListService(client: apiClient),
            workflowJobListService: ActionsWorkflowJobListService(client: apiClient)
        )
        settingsModelBox.value = resolvedSettingsModel
        self.settingsModel = resolvedSettingsModel
        self.notificationMonitor = RepositoryNotificationMonitor(
            settingsStore: settingsStore,
            dataSource: resolvedDataSource,
            sleeper: sleeper,
            delivery: resolvedNotificationDelivery,
            authenticationState: resolvedAuthController.state
        )

        observeAuthenticationState()
        observeDockIconPreference()
        observeStartAtLoginPreference()
        Task { @MainActor [weak self] in
            self?.applyDockIconPreference()
            self?.applyInitialStartAtLoginPreference()
        }
        Task { @MainActor [resolvedNotificationDelivery, resolvedSettingsModel] in
            resolvedSettingsModel?.notificationAuthorizationStatus = await resolvedNotificationDelivery.authorizationStatus()
        }
    }

    func setMenuVisible(_ isVisible: Bool) {
        dashboardModel.setMenuVisible(isVisible)
        notificationMonitor.setMenuVisible(isVisible)
    }

    func setSettingsWindowVisible(_ isVisible: Bool) {
        guard isSettingsWindowVisible != isVisible else {
            return
        }

        isSettingsWindowVisible = isVisible
        applyDockIconPreference()
        if isVisible {
            refreshStartAtLoginStatus()
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
                self.notificationMonitor.setAuthenticationState(state)
                self.observeAuthenticationState()
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

    private func observeStartAtLoginPreference() {
        withObservationTracking {
            _ = settingsStore.settings.startAtLogin
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.applyStartAtLoginPreference()
                self.observeStartAtLoginPreference()
            }
        }
    }

    private func applyDockIconPreference() {
        let shouldHideDockIcon = settingsStore.settings.hideDockIcon && !isSettingsWindowVisible
        dockIconVisibilityController.apply(hideDockIcon: shouldHideDockIcon)
    }

    private func applyStartAtLoginPreference() {
        do {
            try startAtLoginController.setStartAtLoginEnabled(settingsStore.settings.startAtLogin)
            settingsModel.startAtLoginErrorMessage = nil
        } catch {
            settingsModel.startAtLoginErrorMessage = error.localizedDescription
        }

        refreshStartAtLoginStatus()
    }

    private func applyInitialStartAtLoginPreference() {
        refreshStartAtLoginStatus()

        guard settingsStore.settings.startAtLogin else {
            return
        }

        applyStartAtLoginPreference()
    }

    private func refreshStartAtLoginStatus() {
        let status = startAtLoginController.registrationStatus
        settingsModel.startAtLoginRegistrationStatus = status

        if (settingsStore.settings.startAtLogin && status == .enabled) ||
            (!settingsStore.settings.startAtLogin && status == .disabled) {
            settingsModel.startAtLoginErrorMessage = nil
        }
    }
}

private final class WeakSettingsModelBox<Value: AnyObject> {
    weak var value: Value?
}
