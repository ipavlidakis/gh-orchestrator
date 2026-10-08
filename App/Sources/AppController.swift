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
    let softwareUpdateModel: SoftwareUpdateModel
    private(set) var prViewerWindows: [PullRequestAddress: PRViewerWindowController] = [:]
    private let prDetailService: any PullRequestDetailLoading
    private let dockIconVisibilityController: any DockIconVisibilityControlling
    private let applicationIconController: any ApplicationIconControlling
    private let startAtLoginController: any StartAtLoginControlling
    private let notificationDelivery: any LocalNotificationDelivering
    private let openURLAction: @MainActor (URL) -> Void
    private var isSettingsWindowVisible = false

    init(
        settingsStore: SettingsStore = SettingsStore(),
        dataSource: (any DashboardDataSource)? = nil,
        authController: (any GitHubAuthControlling)? = nil,
        sleeper: any DashboardSleepProviding = TaskSleepProvider(),
        requestLogModel: GitHubRequestLogModel? = nil,
        dockIconVisibilityController: any DockIconVisibilityControlling = DockIconVisibilityController(),
        applicationIconController: (any ApplicationIconControlling)? = nil,
        startAtLoginController: any StartAtLoginControlling = StartAtLoginController(),
        notificationDelivery: (any LocalNotificationDelivering)? = nil,
        softwareUpdateChecker: (any SoftwareUpdateChecking)? = nil,
        softwareUpdateInstaller: (any SoftwareUpdateInstalling)? = nil,
        startsAutomaticUpdateChecks: Bool = true,
        prDetailService: (any PullRequestDetailLoading)? = nil,
        openURL: @escaping @MainActor (URL) -> Void = { url in
            NSWorkspace.shared.open(url)
        }
    ) {
        let resolvedRequestLogModel = requestLogModel ?? GitHubRequestLogModel()
        let appControllerBox = WeakObjectBox<AppController>()
        let resolvedNotificationDelivery = notificationDelivery ?? UserNotificationCenterDelivery(
            responseRouter: NotificationResponseRouter { url in
                appControllerBox.value?.openURL(url)
            }
        )

        self.settingsStore = settingsStore
        self.requestLogModel = resolvedRequestLogModel
        self.dockIconVisibilityController = dockIconVisibilityController
        self.applicationIconController = applicationIconController ?? ApplicationIconController()
        self.startAtLoginController = startAtLoginController
        self.notificationDelivery = resolvedNotificationDelivery
        self.openURLAction = openURL

        let credentialStore = KeychainGitHubCredentialStore()
        let apiClient = URLSessionGitHubAPIClient(
            credentialStore: credentialStore,
            metricsRecorder: resolvedRequestLogModel
        )
        let resolvedAuthController = authController ?? GitHubAuthController(
            apiClient: apiClient,
            credentialStore: credentialStore
        )
        self.prDetailService = prDetailService ?? PullRequestDetailService(client: apiClient)
        let resolvedDataSource = dataSource ?? LiveDashboardDataSource(client: apiClient)
        let resolvedSoftwareUpdateChecker = softwareUpdateChecker ?? GitHubReleaseUpdateChecker(
            owner: AppMetadata.releaseRepositoryOwner,
            repository: AppMetadata.releaseRepositoryName
        )
        let resolvedSoftwareUpdateInstaller = softwareUpdateInstaller ?? DMGSoftwareUpdateInstaller()

        self.authController = resolvedAuthController
        self.dashboardModel = MenuBarDashboardModel(
            settingsStore: settingsStore,
            dataSource: resolvedDataSource,
            sleeper: sleeper,
            authenticationState: resolvedAuthController.state
        )
        self.softwareUpdateModel = SoftwareUpdateModel(
            store: settingsStore,
            checker: resolvedSoftwareUpdateChecker,
            installer: resolvedSoftwareUpdateInstaller
        )

        let settingsModelBox = WeakObjectBox<SettingsModel>()
#if DEBUG
        let notificationPreviewAction: (@MainActor (RepositoryNotificationEvent) async throws -> Void)? = { [resolvedNotificationDelivery] event in
            try await resolvedNotificationDelivery.deliverPreview(event)
        }
#else
        let notificationPreviewAction: (@MainActor (RepositoryNotificationEvent) async throws -> Void)? = nil
#endif
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
            workflowJobListService: ActionsWorkflowJobListService(client: apiClient),
            actionsInsightsService: ActionsInsightsService(client: apiClient),
            repositoryListService: RepositoryListService(client: apiClient),
            repositorySuggestions: { [dashboardModel] in dashboardModel.availableRepositories },
            sendNotificationPreviewAction: notificationPreviewAction
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
        appControllerBox.value = self

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
        if startsAutomaticUpdateChecks {
            let updateModel = softwareUpdateModel
            Task { @MainActor [updateModel] in
                updateModel.startAutomaticChecks()
            }
        }
    }

    func setMenuVisible(_ isVisible: Bool) {
        dashboardModel.setMenuVisible(isVisible)
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

    func openURL(_ url: URL) {
        if settingsStore.settings.pullRequestOpenDestination == .inApp,
           let address = PullRequestAddress(url: url) {
            let viewer: PRViewerWindowController
            if let existing = prViewerWindows[address] {
                viewer = existing
            } else {
                viewer = PRViewerWindowController(address: address, service: prDetailService,
                    openBrowser: { [weak self] url in self?.openInBrowser(url) },
                    openContentURL: { [weak self] url in self?.openURL(url) },
                    onClose: { [weak self] in
                        self?.prViewerWindows[address] = nil
                        self?.applyDockIconPreference()
                    })
                prViewerWindows[address] = viewer
            }
            applyDockIconPreference()
            viewer.present(url: url)
            return
        }
        openInBrowser(url)
    }

    func openInBrowser(_ url: URL) {
        openURLAction(url)
        Task { @MainActor [weak self] in
            self?.applyDockIconPreference()
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
                for viewer in Array(self.prViewerWindows.values) { viewer.close() }
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
        let shouldHideDockIcon = settingsStore.settings.hideDockIcon && !isSettingsWindowVisible && prViewerWindows.isEmpty
        dockIconVisibilityController.apply(hideDockIcon: shouldHideDockIcon)

        guard !shouldHideDockIcon else {
            return
        }

        applicationIconController.applyCurrentSystemAppearance()
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

private final class WeakObjectBox<Value: AnyObject> {
    weak var value: Value?
}
