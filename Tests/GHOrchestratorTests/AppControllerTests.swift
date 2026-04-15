import Foundation
import Observation
import Synchronization
import XCTest
@testable import GHOrchestrator
import GHOrchestratorCore

@MainActor
final class AppControllerTests: XCTestCase {
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

    func testAppControllerAppliesDockIconPreferenceAtLaunchAndWhenSettingsChange() async {
        let store = configuredSettingsStore(hideDockIcon: true)
        let dockIconController = RecordingDockIconVisibilityController()
        let controller = AppController(
            settingsStore: store,
            dataSource: MutableDashboardDataSource(),
            authController: MutableAuthController(state: .authenticated(username: "octocat")),
            sleeper: CancellingSleeper(),
            dockIconVisibilityController: dockIconController,
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
    }

    func testSettingsWindowVisibilityTemporarilyShowsDockIconWhenPreferenceIsHidden() async {
        let store = configuredSettingsStore(hideDockIcon: true)
        let dockIconController = RecordingDockIconVisibilityController()
        let controller = AppController(
            settingsStore: store,
            dataSource: MutableDashboardDataSource(),
            authController: MutableAuthController(state: .authenticated(username: "octocat")),
            sleeper: CancellingSleeper(),
            dockIconVisibilityController: dockIconController,
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

        controller.setSettingsWindowVisible(false)

        XCTAssertEqual(dockIconController.appliedValues, [true, false, true])
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
    func authorizationStatus() async -> LocalNotificationAuthorizationStatus {
        .authorized
    }

    func requestAuthorization() async throws -> LocalNotificationAuthorizationStatus {
        .authorized
    }

    func deliver(_: RepositoryNotificationEvent) async throws {}
}

@MainActor
private final class RecordingDockIconVisibilityController: DockIconVisibilityControlling {
    private(set) var appliedValues: [Bool] = []

    func apply(hideDockIcon: Bool) {
        appliedValues.append(hideDockIcon)
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
