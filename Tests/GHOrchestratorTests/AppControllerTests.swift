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
            sleeper: CancellingSleeper()
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
            sleeper: CancellingSleeper()
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
            sleeper: CancellingSleeper()
        )

        controller.settingsModel.requestSignIn()
        controller.settingsModel.requestSignOut()

        XCTAssertEqual(authController.signInCount, 1)
        XCTAssertEqual(authController.signOutCount, 1)
    }

    func testAppControllerForwardsIncomingURLsToAuthController() {
        let authController = MutableAuthController(state: .signedOut)
        let controller = AppController(
            settingsStore: configuredSettingsStore(),
            dataSource: MutableDashboardDataSource(),
            authController: authController,
            sleeper: CancellingSleeper()
        )
        let callbackURL = URL(string: "ghorchestrator://oauth/callback?code=abc&state=123")!

        controller.handleIncomingURL(callbackURL)

        XCTAssertEqual(authController.handledURLs, [callbackURL])
    }

    func testAppControllerAppliesDockIconPreferenceAtLaunchAndWhenSettingsChange() async {
        let store = configuredSettingsStore(hideDockIcon: true)
        let dockIconController = RecordingDockIconVisibilityController()
        let controller = AppController(
            settingsStore: store,
            dataSource: MutableDashboardDataSource(),
            authController: MutableAuthController(state: .authenticated(username: "octocat")),
            sleeper: CancellingSleeper(),
            dockIconVisibilityController: dockIconController
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

    private func configuredSettingsStore(hideDockIcon: Bool = false) -> SettingsStore {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        store.settings = AppSettings(
            observedRepositories: [
                ObservedRepository(owner: "openai", name: "codex")
            ],
            hideDockIcon: hideDockIcon
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

    func loadSections(for _: AppSettings) async throws -> [RepositorySection] {
        loadCount.withLock { count in
            count += 1
        }

        return sections
    }

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
    private(set) var handledURLs: [URL] = []
    private(set) var signInCount = 0
    private(set) var signOutCount = 0

    init(state: GitHubAuthenticationState) {
        self.state = state
    }

    func startSignIn() {
        signInCount += 1
    }

    func handleCallbackURL(_ url: URL) {
        handledURLs.append(url)
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
private final class RecordingDockIconVisibilityController: DockIconVisibilityControlling {
    private(set) var appliedValues: [Bool] = []

    func apply(hideDockIcon: Bool) {
        appliedValues.append(hideDockIcon)
    }
}
