import Foundation
import Synchronization
import XCTest
@testable import GHOrchestrator
import GHOrchestratorCore

@MainActor
final class AppControllerTests: XCTestCase {
    func testAppControllerSeedsAndPropagatesCliHealthIntoSettingsModel() async {
        let dataSource = MutableDashboardDataSource(
            health: .authenticated(username: "octocat")
        )
        let controller = AppController(
            settingsStore: configuredSettingsStore(),
            dataSource: dataSource,
            sleeper: CancellingSleeper()
        )

        XCTAssertEqual(
            controller.settingsModel.cliHealth,
            .authenticated(username: "octocat")
        )

        await waitUntil("initial dashboard refresh") {
            dataSource.currentLoadCount() == 1
        }

        dataSource.setHealth(.loggedOut)
        controller.dashboardModel.refresh()

        await waitUntil("settings model cliHealth update") {
            controller.settingsModel.cliHealth == .loggedOut
        }

        XCTAssertEqual(controller.dashboardModel.cliHealth, .loggedOut)
    }

    func testManualRefreshActionTriggersDashboardRefreshThroughSettingsModel() async {
        let dataSource = MutableDashboardDataSource(
            health: .authenticated(username: "octocat")
        )
        let controller = AppController(
            settingsStore: configuredSettingsStore(),
            dataSource: dataSource,
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

    private func configuredSettingsStore() -> SettingsStore {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        store.settings = AppSettings(
            observedRepositories: [
                ObservedRepository(owner: "openai", name: "codex")
            ]
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
    private struct State {
        var health: GitHubCLIHealth
        var loadCount = 0
    }

    private let state: Mutex<State>
    private let sections: [RepositorySection]

    init(
        health: GitHubCLIHealth,
        sections: [RepositorySection] = []
    ) {
        self.state = Mutex(State(health: health))
        self.sections = sections
    }

    func setHealth(_ health: GitHubCLIHealth) {
        state.withLock { currentState in
            currentState.health = health
        }
    }

    func cliHealth() -> GitHubCLIHealth {
        state.withLock { currentState in
            currentState.health
        }
    }

    func loadSections(for _: AppSettings) async throws -> [RepositorySection] {
        state.withLock { currentState in
            currentState.loadCount += 1
        }
        return sections
    }

    func currentLoadCount() -> Int {
        state.withLock { currentState in
            currentState.loadCount
        }
    }
}

private struct CancellingSleeper: DashboardSleepProviding {
    func sleep(for _: Duration) async throws {
        throw CancellationError()
    }
}
