import AppKit
import Foundation
import Observation
import Synchronization
import SwiftUI
import UserNotifications
import XCTest
@testable import GHOrchestrator
import GHOrchestratorCore

@MainActor
final class AppControllerTests: XCTestCase {
    func testPRDestinationRoutesToReusableWindowAndRestoresDockOnClose() async throws {
        let store = configuredSettingsStore(hideDockIcon: true)
        let dock = RecordingDockIconVisibilityController()
        let auth = MutableAuthController(state: .authenticated(username: "alex"))
        var browserURLs: [URL] = []
        let controller = AppController(settingsStore: store, dataSource: MutableDashboardDataSource(),
            authController: auth, sleeper: CancellingSleeper(),
            dockIconVisibilityController: dock, applicationIconController: RecordingApplicationIconController(),
            startAtLoginController: RecordingStartAtLoginController(), notificationDelivery: AppControllerRecordingNotificationDelivery(),
            softwareUpdateChecker: StubSoftwareUpdateChecker(), softwareUpdateInstaller: RecordingSoftwareUpdateInstaller(),
            startsAutomaticUpdateChecks: false, prDetailService: PRViewerFixtureService(), openURL: { browserURLs.append($0) })
        let url = URL(string: "https://github.com/orbit/nova/pull/42")!
        controller.openURL(url)
        XCTAssertEqual(browserURLs, [url])
        XCTAssertTrue(controller.prViewerWindows.isEmpty)
        controller.settingsModel.pullRequestOpenDestination = .inApp
        controller.openURL(url)
        let viewer = try XCTUnwrap(controller.prViewerWindows.values.first)
        defer { viewer.close() }
        XCTAssertTrue(try XCTUnwrap(viewer.window).isVisible)
        XCTAssertEqual(dock.appliedValues.last, false)
        controller.openURL(URL(string: "https://github.com/ORBIT/NOVA/pull/42#discussion_r1")!)
        XCTAssertEqual(controller.prViewerWindows.count, 1)
        controller.openInBrowser(url)
        XCTAssertEqual(browserURLs, [url, url])
        let job = URL(string: "https://github.com/orbit/nova/actions/runs/1")!
        controller.openURL(job)
        XCTAssertEqual(browserURLs.last, job)
        viewer.close()
        XCTAssertTrue(controller.prViewerWindows.isEmpty)
        XCTAssertEqual(dock.appliedValues.last, true)
        controller.openURL(url)
        let signedInViewer = try XCTUnwrap(controller.prViewerWindows.values.first)
        auth.state = .signedOut
        await waitUntil("PR viewer closes after sign out") { controller.prViewerWindows.isEmpty }
        XCTAssertFalse(try XCTUnwrap(signedInViewer.window).isVisible)
        XCTAssertTrue(signedInViewer.model.loading.isEmpty)
    }

    func testAppControllerSeedsAndPropagatesAuthenticationStateIntoSettingsAndDashboardModels() async {
        let authController = MutableAuthController(state: .authenticated(username: "octocat"))
        let dataSource = MutableDashboardDataSource()
        let controller = AppController(
            settingsStore: configuredSettingsStore(),
            dataSource: dataSource,
            authController: authController,
            sleeper: CancellingSleeper(),
            startAtLoginController: RecordingStartAtLoginController(),
            notificationDelivery: AppControllerRecordingNotificationDelivery(),
            softwareUpdateChecker: StubSoftwareUpdateChecker(),
            softwareUpdateInstaller: RecordingSoftwareUpdateInstaller(),
            startsAutomaticUpdateChecks: false
        )

        XCTAssertEqual(
            controller.settingsModel.authenticationState,
            .authenticated(username: "octocat")
        )
        XCTAssertEqual(
            controller.dashboardModel.authenticationState,
            .authenticated(username: "octocat")
        )

        authController.state = .signedOut

        await waitUntil("settings model authentication state update") {
            controller.settingsModel.authenticationState == .signedOut
        }

        XCTAssertEqual(controller.dashboardModel.authenticationState, .signedOut)
        XCTAssertEqual(controller.dashboardModel.state, .signedOut)
    }

    func testManualRefreshActionTriggersDashboardRefreshThroughSettingsModel() async {
        let dataSource = MutableDashboardDataSource()
        let controller = AppController(
            settingsStore: configuredSettingsStore(),
            dataSource: dataSource,
            authController: MutableAuthController(state: .authenticated(username: "octocat")),
            sleeper: CancellingSleeper(),
            startAtLoginController: RecordingStartAtLoginController(),
            notificationDelivery: AppControllerRecordingNotificationDelivery(),
            softwareUpdateChecker: StubSoftwareUpdateChecker(),
            softwareUpdateInstaller: RecordingSoftwareUpdateInstaller(),
            startsAutomaticUpdateChecks: false
        )

        await waitUntil("initial dashboard refresh") {
            dataSource.currentLoadCount() == 1
        }

        XCTAssertTrue(controller.settingsModel.hasManualRefreshAction)

        controller.settingsModel.requestManualRefresh()

        await waitUntil("manual refresh to reach dashboard model") {
            dataSource.currentLoadCount() == 2
        }
    }

    func testSettingsAuthActionsDelegateToAuthController() {
        let authController = MutableAuthController(state: .signedOut)
        let controller = AppController(
            settingsStore: configuredSettingsStore(),
            dataSource: MutableDashboardDataSource(),
            authController: authController,
            sleeper: CancellingSleeper(),
            startAtLoginController: RecordingStartAtLoginController(),
            notificationDelivery: AppControllerRecordingNotificationDelivery(),
            softwareUpdateChecker: StubSoftwareUpdateChecker(),
            softwareUpdateInstaller: RecordingSoftwareUpdateInstaller(),
            startsAutomaticUpdateChecks: false
        )

        controller.settingsModel.requestSignIn()
        controller.settingsModel.requestSignOut()

        XCTAssertEqual(authController.signInCount, 1)
        XCTAssertEqual(authController.signOutCount, 1)
    }

#if DEBUG
    func testNotificationDebugPreviewUsesPreviewDeliveryPath() async {
        let notificationDelivery = AppControllerRecordingNotificationDelivery()
        let controller = AppController(
            settingsStore: configuredSettingsStore(),
            dataSource: MutableDashboardDataSource(),
            authController: MutableAuthController(state: .authenticated(username: "octocat")),
            sleeper: CancellingSleeper(),
            startAtLoginController: RecordingStartAtLoginController(),
            notificationDelivery: notificationDelivery,
            softwareUpdateChecker: StubSoftwareUpdateChecker(),
            softwareUpdateInstaller: RecordingSoftwareUpdateInstaller(),
            startsAutomaticUpdateChecks: false
        )

        XCTAssertTrue(controller.settingsModel.canSendNotificationDebugPreview)

        controller.settingsModel.requestNotificationDebugPreview()

        await waitUntil("notification debug preview delivery") {
            notificationDelivery.previewedEvents.count == 1
        }

        XCTAssertTrue(notificationDelivery.deliveredEvents.isEmpty)
        XCTAssertEqual(notificationDelivery.previewedEvents[0].trigger, .pullRequestCreated)
    }
#endif

    func testAppControllerAppliesDockIconPreferenceAtLaunchAndWhenSettingsChange() async {
        let store = configuredSettingsStore(hideDockIcon: true)
        let dockIconController = RecordingDockIconVisibilityController()
        let applicationIconController = RecordingApplicationIconController()
        let controller = AppController(
            settingsStore: store,
            dataSource: MutableDashboardDataSource(),
            authController: MutableAuthController(state: .authenticated(username: "octocat")),
            sleeper: CancellingSleeper(),
            dockIconVisibilityController: dockIconController,
            applicationIconController: applicationIconController,
            startAtLoginController: RecordingStartAtLoginController(),
            notificationDelivery: AppControllerRecordingNotificationDelivery(),
            softwareUpdateChecker: StubSoftwareUpdateChecker(),
            softwareUpdateInstaller: RecordingSoftwareUpdateInstaller(),
            startsAutomaticUpdateChecks: false
        )

        await waitUntil("initial dock icon preference application") {
            dockIconController.appliedValues == [true]
        }
        XCTAssertTrue(controller.settingsModel.hideDockIcon)

        controller.settingsModel.hideDockIcon = false

        await waitUntil("dock icon preference update") {
            dockIconController.appliedValues == [true, false]
        }
        XCTAssertEqual(applicationIconController.applyCurrentSystemAppearanceCallCount, 1)
    }

    func testSettingsWindowVisibilityTemporarilyShowsDockIconWhenPreferenceIsHidden() async {
        let store = configuredSettingsStore(hideDockIcon: true)
        let dockIconController = RecordingDockIconVisibilityController()
        let applicationIconController = RecordingApplicationIconController()
        let controller = AppController(
            settingsStore: store,
            dataSource: MutableDashboardDataSource(),
            authController: MutableAuthController(state: .authenticated(username: "octocat")),
            sleeper: CancellingSleeper(),
            dockIconVisibilityController: dockIconController,
            applicationIconController: applicationIconController,
            startAtLoginController: RecordingStartAtLoginController(),
            notificationDelivery: AppControllerRecordingNotificationDelivery(),
            softwareUpdateChecker: StubSoftwareUpdateChecker(),
            softwareUpdateInstaller: RecordingSoftwareUpdateInstaller(),
            startsAutomaticUpdateChecks: false
        )

        await waitUntil("initial hidden Dock icon preference application") {
            dockIconController.appliedValues == [true]
        }

        controller.setSettingsWindowVisible(true)

        XCTAssertEqual(dockIconController.appliedValues, [true, false])
        XCTAssertEqual(applicationIconController.applyCurrentSystemAppearanceCallCount, 1)

        controller.setSettingsWindowVisible(false)

        XCTAssertEqual(dockIconController.appliedValues, [true, false, true])
        XCTAssertEqual(applicationIconController.applyCurrentSystemAppearanceCallCount, 1)
    }

    func testOpeningDashboardURLReappliesHiddenDockIconPreference() async {
        let store = configuredSettingsStore(hideDockIcon: true)
        let dockIconController = RecordingDockIconVisibilityController()
        var openedURLs: [URL] = []
        let controller = AppController(
            settingsStore: store,
            dataSource: MutableDashboardDataSource(),
            authController: MutableAuthController(state: .authenticated(username: "octocat")),
            sleeper: CancellingSleeper(),
            dockIconVisibilityController: dockIconController,
            applicationIconController: RecordingApplicationIconController(),
            startAtLoginController: RecordingStartAtLoginController(),
            notificationDelivery: AppControllerRecordingNotificationDelivery(),
            softwareUpdateChecker: StubSoftwareUpdateChecker(),
            softwareUpdateInstaller: RecordingSoftwareUpdateInstaller(),
            startsAutomaticUpdateChecks: false,
            openURL: { openedURLs.append($0) }
        )

        await waitUntil("initial hidden Dock icon preference application") {
            dockIconController.appliedValues == [true]
        }

        let url = URL(string: "https://github.com/openai/codex/actions/runs/1/job/2")!
        controller.openURL(url)

        XCTAssertEqual(openedURLs, [url])
        await waitUntil("hidden Dock icon preference reapplication") {
            dockIconController.appliedValues == [true, true]
        }
    }

    func testNotificationClickRestoresDockPreferenceAndPreservesSettingsOverride() async throws {
        let center = UNUserNotificationCenter.current()
        let previousDelegate = center.delegate
        let previousPolicy = NSApp.activationPolicy()
        defer {
            center.delegate = previousDelegate
            NSApp.setActivationPolicy(previousPolicy)
        }

        let store = configuredSettingsStore(hideDockIcon: true)
        var openedURLs: [URL] = []
        let controller = AppController(
            settingsStore: store,
            dataSource: MutableDashboardDataSource(),
            authController: MutableAuthController(state: .signedOut),
            sleeper: CancellingSleeper(),
            applicationIconController: RecordingApplicationIconController(),
            startAtLoginController: RecordingStartAtLoginController(),
            softwareUpdateChecker: StubSoftwareUpdateChecker(),
            softwareUpdateInstaller: RecordingSoftwareUpdateInstaller(),
            startsAutomaticUpdateChecks: false,
            openURL: { url in
                NSApp.setActivationPolicy(.regular)
                openedURLs.append(url)
            }
        )
        await waitUntil("initial hidden Dock policy") {
            NSApp.activationPolicy() == .accessory
        }

        let delivery = try XCTUnwrap(center.delegate as? UserNotificationCenterDelivery)
        let url = URL(string: "https://github.com/openai/codex/actions/runs/1/job/2")!
        let content = UNMutableNotificationContent()
        content.userInfo = [LocalNotificationUserInfo.targetURLKey: url.absoluteString]
        let request = UNNotificationRequest(identifier: "dock-regression", content: content, trigger: nil)
        let notification = try XCTUnwrap(UNNotification(coder: NotificationResponseDecoder(values: [
            "request": request,
            "date": Date()
        ])))
        let response = try XCTUnwrap(UNNotificationResponse(coder: NotificationResponseDecoder(values: [
            "notification": notification,
            "actionIdentifier": UNNotificationDefaultActionIdentifier
        ])))
        for (settingsVisible, hidesDockIcon) in [(false, true), (true, true), (false, false)] {
            controller.setSettingsWindowVisible(settingsVisible)
            store.settings.hideDockIcon = hidesDockIcon
            let expectedPolicy: NSApplication.ActivationPolicy = hidesDockIcon && !settingsVisible ? .accessory : .regular
            await waitUntil("Dock policy before notification click") {
                NSApp.activationPolicy() == expectedPolicy
            }
            let openedCount = openedURLs.count
            await delivery.userNotificationCenter(center, didReceive: response)
            await waitUntil("notification URL and restored Dock policy") {
                openedURLs.count == openedCount + 1 && NSApp.activationPolicy() == expectedPolicy
            }
            XCTAssertEqual(openedURLs.last, url)
            XCTAssertEqual(NSApp.activationPolicy(), expectedPolicy)
        }
    }

    func testVisibleDockIconPreferenceReappliesCustomDockIconAtLaunch() async {
        let dockIconController = RecordingDockIconVisibilityController()
        let applicationIconController = RecordingApplicationIconController()
        let controller = AppController(
            settingsStore: configuredSettingsStore(hideDockIcon: false),
            dataSource: MutableDashboardDataSource(),
            authController: MutableAuthController(state: .authenticated(username: "octocat")),
            sleeper: CancellingSleeper(),
            dockIconVisibilityController: dockIconController,
            applicationIconController: applicationIconController,
            startAtLoginController: RecordingStartAtLoginController(),
            notificationDelivery: AppControllerRecordingNotificationDelivery(),
            softwareUpdateChecker: StubSoftwareUpdateChecker(),
            softwareUpdateInstaller: RecordingSoftwareUpdateInstaller(),
            startsAutomaticUpdateChecks: false
        )

        await waitUntil("initial visible Dock icon preference application") {
            dockIconController.appliedValues == [false]
        }

        XCTAssertFalse(controller.settingsModel.hideDockIcon)
        XCTAssertEqual(applicationIconController.applyCurrentSystemAppearanceCallCount, 1)
    }

    func testAppControllerAppliesStartAtLoginPreferenceAtLaunchAndWhenSettingsChange() async {
        let store = configuredSettingsStore(startAtLogin: true)
        let startAtLoginController = RecordingStartAtLoginController(status: .disabled)
        let controller = AppController(
            settingsStore: store,
            dataSource: MutableDashboardDataSource(),
            authController: MutableAuthController(state: .authenticated(username: "octocat")),
            sleeper: CancellingSleeper(),
            startAtLoginController: startAtLoginController,
            notificationDelivery: AppControllerRecordingNotificationDelivery(),
            softwareUpdateChecker: StubSoftwareUpdateChecker(),
            softwareUpdateInstaller: RecordingSoftwareUpdateInstaller(),
            startsAutomaticUpdateChecks: false
        )

        await waitUntil("initial start at login preference application") {
            startAtLoginController.appliedValues == [true]
        }
        XCTAssertTrue(controller.settingsModel.startAtLogin)
        XCTAssertEqual(controller.settingsModel.startAtLoginRegistrationStatus, .enabled)

        controller.settingsModel.startAtLogin = false

        await waitUntil("start at login preference update") {
            startAtLoginController.appliedValues == [true, false]
        }
        XCTAssertEqual(controller.settingsModel.startAtLoginRegistrationStatus, .disabled)
    }

    func testSettingsStartAtLoginSystemSettingsActionDelegatesToController() {
        let startAtLoginController = RecordingStartAtLoginController(
            status: .requiresApproval,
            updatesStatusOnSet: false
        )
        let controller = AppController(
            settingsStore: configuredSettingsStore(startAtLogin: true),
            dataSource: MutableDashboardDataSource(),
            authController: MutableAuthController(state: .authenticated(username: "octocat")),
            sleeper: CancellingSleeper(),
            startAtLoginController: startAtLoginController,
            notificationDelivery: AppControllerRecordingNotificationDelivery(),
            softwareUpdateChecker: StubSoftwareUpdateChecker(),
            softwareUpdateInstaller: RecordingSoftwareUpdateInstaller(),
            startsAutomaticUpdateChecks: false
        )

        XCTAssertTrue(controller.settingsModel.canOpenLoginItemsSettings)

        controller.settingsModel.requestOpenLoginItemsSettings()

        XCTAssertEqual(startAtLoginController.openSystemSettingsCallCount, 1)
    }

    private func configuredSettingsStore(
        hideDockIcon: Bool = false,
        startAtLogin: Bool = false
    ) -> SettingsStore {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        store.settings = AppSettings(
            observedRepositories: [
                ObservedRepository(owner: "openai", name: "codex")
            ],
            hideDockIcon: hideDockIcon,
            startAtLogin: startAtLogin
        )
        return store
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

    private func makeIsolatedStorageURL() -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GHOrchestrator.AppControllerTests.\(UUID().uuidString)", isDirectory: true)
        let storageURL = rootURL
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("GHOrchestrator", isDirectory: true)
            .appendingPathComponent("settings.json", isDirectory: false)

        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        return storageURL
    }
}

private final class MutableDashboardDataSource: DashboardDataSource, @unchecked Sendable {
    private let loadCount = Mutex(0)
    private let sections: [RepositorySection]

    init(sections: [RepositorySection] = []) {
        self.sections = sections
    }

    func loadSections(
        for _: AppSettings,
        filter _: DashboardFilter
    ) async throws -> [RepositorySection] {
        loadCount.withLock { count in
            count += 1
        }

        return sections
    }

    func rerunWorkflowJob(
        repository _: ObservedRepository,
        jobID _: Int
    ) async throws {}

    func currentLoadCount() -> Int {
        loadCount.withLock { count in
            count
        }
    }
}

@MainActor
@Observable
private final class MutableAuthController: GitHubAuthControlling {
    var state: GitHubAuthenticationState
    private(set) var signInCount = 0
    private(set) var signOutCount = 0

    init(state: GitHubAuthenticationState) {
        self.state = state
    }

    func startSignIn() {
        signInCount += 1
    }

    func signOut() {
        signOutCount += 1
    }
}

private struct CancellingSleeper: DashboardSleepProviding {
    func sleep(for _: Duration) async throws {
        throw CancellationError()
    }
}

@MainActor
private final class AppControllerRecordingNotificationDelivery: LocalNotificationDelivering {
    private(set) var deliveredEvents: [RepositoryNotificationEvent] = []
    private(set) var previewedEvents: [RepositoryNotificationEvent] = []

    func authorizationStatus() async -> LocalNotificationAuthorizationStatus {
        .authorized
    }

    func requestAuthorization() async throws -> LocalNotificationAuthorizationStatus {
        .authorized
    }

    func deliver(_ event: RepositoryNotificationEvent) async throws {
        deliveredEvents.append(event)
    }

    func deliverPreview(_ event: RepositoryNotificationEvent) async throws {
        previewedEvents.append(event)
    }
}

private final class NotificationResponseDecoder: NSCoder {
    private let values: [String: Any]

    init(values: [String: Any]) {
        self.values = values
        super.init()
    }

    override var allowsKeyedCoding: Bool { true }

    override func decodeObject(forKey key: String) -> Any? {
        values[key]
    }
}

@MainActor
private final class RecordingDockIconVisibilityController: DockIconVisibilityControlling {
    private(set) var appliedValues: [Bool] = []

    func apply(hideDockIcon: Bool) {
        appliedValues.append(hideDockIcon)
    }
}

@MainActor
private final class RecordingApplicationIconController: ApplicationIconControlling {
    private(set) var applyColorSchemeCallCount = 0
    private(set) var applyCurrentSystemAppearanceCallCount = 0

    func apply(colorScheme _: ColorScheme) {
        applyColorSchemeCallCount += 1
    }

    func applyCurrentSystemAppearance() {
        applyCurrentSystemAppearanceCallCount += 1
    }
}

@MainActor
private final class RecordingStartAtLoginController: StartAtLoginControlling {
    var registrationStatus: StartAtLoginRegistrationStatus
    private(set) var appliedValues: [Bool] = []
    private(set) var openSystemSettingsCallCount = 0
    var errorToThrow: Error?
    private let updatesStatusOnSet: Bool

    init(
        status: StartAtLoginRegistrationStatus = .disabled,
        updatesStatusOnSet: Bool = true
    ) {
        self.registrationStatus = status
        self.updatesStatusOnSet = updatesStatusOnSet
    }

    func setStartAtLoginEnabled(_ isEnabled: Bool) throws {
        appliedValues.append(isEnabled)

        if let errorToThrow {
            throw errorToThrow
        }

        if updatesStatusOnSet {
            registrationStatus = isEnabled ? .enabled : .disabled
        }
    }

    func openSystemSettingsLoginItems() {
        openSystemSettingsCallCount += 1
    }
}
