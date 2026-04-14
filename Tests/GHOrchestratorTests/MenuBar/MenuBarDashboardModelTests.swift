import Foundation
import XCTest
@testable import GHOrchestrator
import GHOrchestratorCore

@MainActor
final class MenuBarDashboardModelTests: XCTestCase {
    func testVisibleMenuLoadsSectionsWhenRepositoriesAreConfigured() async throws {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        store.settings = AppSettings(
            observedRepositories: [ObservedRepository(owner: "openai", name: "codex")]
        )

        let dataSource = MockDashboardDataSource(
            health: .authenticated(username: "octocat"),
            sections: [
                RepositorySection(
                    repository: ObservedRepository(owner: "openai", name: "codex"),
                    pullRequests: [
                        pullRequest(number: 1)
                    ]
                )
            ]
        )
        let model = MenuBarDashboardModel(
            settingsStore: store,
            dataSource: dataSource,
            sleeper: RecordingSleeper()
        )

        model.setMenuVisible(true)
        await waitForLoadedState(on: model)

        XCTAssertEqual(model.state, .loaded(dataSource.sections))
        XCTAssertEqual(model.cliHealth, .authenticated(username: "octocat"))
    }

    func testEmptyRepositoryListShowsNoRepositoriesConfigured() {
        let model = MenuBarDashboardModel(
            settingsStore: SettingsStore(storageURL: makeIsolatedStorageURL()),
            dataSource: MockDashboardDataSource(
                health: .authenticated(username: "octocat"),
                sections: []
            ),
            sleeper: RecordingSleeper()
        )

        model.setMenuVisible(true)

        XCTAssertEqual(model.state, .noRepositoriesConfigured)
    }

    func testPollingUsesConfiguredIntervalAndRestartsWhenSettingsChange() async throws {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        store.settings = AppSettings(
            observedRepositories: [ObservedRepository(owner: "openai", name: "codex")],
            pollingIntervalSeconds: 60
        )

        let sleeper = RecordingSleeper()
        let model = MenuBarDashboardModel(
            settingsStore: store,
            dataSource: MockDashboardDataSource(
                health: .authenticated(username: "octocat"),
                sections: []
            ),
            sleeper: sleeper
        )

        model.setMenuVisible(true)
        await waitForDurations(count: 1, sleeper: sleeper)

        store.settings.pollingIntervalSeconds = 120
        await waitForDurations(count: 2, sleeper: sleeper)

        let durations = await sleeper.recordedDurations
        XCTAssertEqual(durations.map { $0.components.seconds }, [60, 120])
    }

    func testHidingMenuCancelsInFlightRefresh() async throws {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        store.settings = AppSettings(
            observedRepositories: [ObservedRepository(owner: "openai", name: "codex")]
        )

        let dataSource = CancellableDashboardDataSource()
        let model = MenuBarDashboardModel(
            settingsStore: store,
            dataSource: dataSource,
            sleeper: RecordingSleeper()
        )

        model.setMenuVisible(true)
        await dataSource.waitUntilLoadStarts()

        model.setMenuVisible(false)
        await dataSource.waitUntilCancelled()

        XCTAssertFalse(model.isMenuVisible)
    }

    func testHealthAndCommandFailureStatesTransition() async throws {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        store.settings = AppSettings(
            observedRepositories: [ObservedRepository(owner: "openai", name: "codex")]
        )

        let missingModel = MenuBarDashboardModel(
            settingsStore: store,
            dataSource: MockDashboardDataSource(health: .missing, sections: []),
            sleeper: RecordingSleeper()
        )
        missingModel.setMenuVisible(true)
        XCTAssertEqual(missingModel.state, .ghMissing)

        let failingModel = MenuBarDashboardModel(
            settingsStore: store,
            dataSource: FailingDashboardDataSource(),
            sleeper: RecordingSleeper()
        )
        failingModel.setMenuVisible(true)
        await waitForCommandFailure(on: failingModel)

        if case .commandFailure(let message) = failingModel.state {
            XCTAssertTrue(message.contains("synthetic failure"))
        } else {
            XCTFail("Expected command failure state")
        }
    }

    private func waitForLoadedState(on model: MenuBarDashboardModel) async {
        for _ in 0..<50 {
            if case .loaded = model.state {
                return
            }
            await Task.yield()
        }

        XCTFail("Timed out waiting for loaded state")
    }

    private func waitForCommandFailure(on model: MenuBarDashboardModel) async {
        for _ in 0..<50 {
            if case .commandFailure = model.state {
                return
            }
            await Task.yield()
        }

        XCTFail("Timed out waiting for command failure state")
    }

    private func waitForDurations(count: Int, sleeper: RecordingSleeper) async {
        for _ in 0..<50 {
            if await sleeper.recordedDurations.count >= count {
                return
            }
            await Task.yield()
        }

        XCTFail("Timed out waiting for recorded sleep durations")
    }

    private func makeIsolatedStorageURL() -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GHOrchestrator.MenuBarDashboardModelTests.\(UUID().uuidString)", isDirectory: true)
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

private func pullRequest(number: Int) -> PullRequestItem {
    PullRequestItem(
        repository: ObservedRepository(owner: "openai", name: "codex"),
        number: number,
        title: "PR #\(number)",
        url: URL(string: "https://github.com/openai/codex/pull/\(number)")!,
        isDraft: false,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(number)),
        reviewStatus: .approved,
        unresolvedReviewThreadCount: 0,
        checkRollupState: .passing
    )
}

private struct MockDashboardDataSource: DashboardDataSource {
    let health: GitHubCLIHealth
    let sections: [RepositorySection]

    func cliHealth() -> GitHubCLIHealth {
        health
    }

    func loadSections(for settings: AppSettings) async throws -> [RepositorySection] {
        sections
    }
}

private struct FailingDashboardDataSource: DashboardDataSource {
    func cliHealth() -> GitHubCLIHealth {
        .authenticated(username: "octocat")
    }

    func loadSections(for settings: AppSettings) async throws -> [RepositorySection] {
        struct SyntheticError: LocalizedError {
            var errorDescription: String? { "synthetic failure" }
        }

        throw SyntheticError()
    }
}

private actor RecordingSleeper: DashboardSleepProviding {
    private(set) var recordedDurations: [Duration] = []

    func sleep(for duration: Duration) async throws {
        recordedDurations.append(duration)
        throw CancellationError()
    }
}

private actor CancellableDashboardDataSource: DashboardDataSource {
    private(set) var didStartLoading = false
    private(set) var didCancel = false

    nonisolated func cliHealth() -> GitHubCLIHealth {
        .authenticated(username: "octocat")
    }

    func loadSections(for settings: AppSettings) async throws -> [RepositorySection] {
        didStartLoading = true

        do {
            try await Task.sleep(for: .seconds(10))
            return []
        } catch {
            didCancel = true
            throw error
        }
    }

    func waitUntilLoadStarts() async {
        while !didStartLoading {
            await Task.yield()
        }
    }

    func waitUntilCancelled() async {
        while !didCancel {
            await Task.yield()
        }
    }
}
