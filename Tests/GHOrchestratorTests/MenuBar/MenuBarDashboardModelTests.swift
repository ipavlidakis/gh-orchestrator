import Foundation
import XCTest
@testable import GHOrchestrator
import GHOrchestratorCore

@MainActor
final class MenuBarDashboardModelTests: XCTestCase {
    func testHiddenDashboardLoadsSectionsWhenRepositoriesAreConfigured() async throws {
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

        await waitForLoadedState(on: model)

        XCTAssertEqual(model.state, .loaded(dataSource.sections))
        XCTAssertEqual(model.cliHealth, .authenticated(username: "octocat"))
    }

    func testEmptyRepositoryListShowsNoRepositoriesConfiguredWhileHidden() {
        let model = MenuBarDashboardModel(
            settingsStore: SettingsStore(storageURL: makeIsolatedStorageURL()),
            dataSource: MockDashboardDataSource(
                health: .authenticated(username: "octocat"),
                sections: []
            ),
            sleeper: RecordingSleeper()
        )

        XCTAssertEqual(model.state, .noRepositoriesConfigured)
    }

    func testHiddenPollingUsesConfiguredIntervalAndRestartsWhenSettingsChange() async throws {
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

        await waitForDurations(count: 1, sleeper: sleeper)

        store.settings.pollingIntervalSeconds = 120
        await waitForDurations(count: 2, sleeper: sleeper)

        let durations = await sleeper.recordedDurations
        XCTAssertEqual(durations.map { $0.components.seconds }, [60, 120])
        XCTAssertFalse(model.isMenuVisible)
    }

    func testShowingMenuKeepsInFlightRefreshRunning() async throws {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        store.settings = AppSettings(
            observedRepositories: [ObservedRepository(owner: "openai", name: "codex")]
        )

        let expectedSections = [
            RepositorySection(
                repository: ObservedRepository(owner: "openai", name: "codex"),
                pullRequests: [pullRequest(number: 1)]
            )
        ]
        let dataSource = DelayedDashboardDataSource(sections: expectedSections)
        let model = MenuBarDashboardModel(
            settingsStore: store,
            dataSource: dataSource,
            sleeper: RecordingSleeper()
        )

        await dataSource.waitUntilLoadStarts()

        model.setMenuVisible(true)
        await dataSource.finishLoading()
        await waitForLoadedState(on: model)

        XCTAssertTrue(model.isMenuVisible)
        XCTAssertEqual(model.state, .loaded(expectedSections))
    }

    func testShowingMenuDoesNotTriggerAdditionalRefresh() async throws {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        store.settings = AppSettings(
            observedRepositories: [ObservedRepository(owner: "openai", name: "codex")]
        )

        let dataSource = CountingDashboardDataSource(
            health: .authenticated(username: "octocat"),
            sections: []
        )
        let model = MenuBarDashboardModel(
            settingsStore: store,
            dataSource: dataSource,
            sleeper: RecordingSleeper()
        )

        await dataSource.waitForLoadCount(1)
        model.setMenuVisible(true)
        await Task.yield()

        let loadCount = await dataSource.currentLoadCount()
        XCTAssertEqual(loadCount, 1)
    }

    func testRefreshKeepsLoadedContentVisibleWhileLoading() async throws {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        store.settings = AppSettings(
            observedRepositories: [ObservedRepository(owner: "openai", name: "codex")]
        )

        let initialSections = [
            RepositorySection(
                repository: ObservedRepository(owner: "openai", name: "codex"),
                pullRequests: [pullRequest(number: 1)]
            )
        ]
        let dataSource = SequencedDashboardDataSource(
            firstSections: initialSections,
            subsequentSections: []
        )
        let model = MenuBarDashboardModel(
            settingsStore: store,
            dataSource: dataSource,
            sleeper: RecordingSleeper()
        )

        await waitForLoadedState(on: model)
        model.refresh()
        await dataSource.waitForLoadCount(2)

        XCTAssertTrue(model.isRefreshing)
        XCTAssertEqual(model.contentState, .loaded(initialSections))
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
        XCTAssertEqual(missingModel.state, .ghMissing)

        let failingModel = MenuBarDashboardModel(
            settingsStore: store,
            dataSource: FailingDashboardDataSource(),
            sleeper: RecordingSleeper()
        )
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

private actor CountingDashboardDataSource: DashboardDataSource {
    let health: GitHubCLIHealth
    let sections: [RepositorySection]
    private(set) var loadCount = 0

    init(health: GitHubCLIHealth, sections: [RepositorySection]) {
        self.health = health
        self.sections = sections
    }

    nonisolated func cliHealth() -> GitHubCLIHealth {
        health
    }

    func loadSections(for settings: AppSettings) async throws -> [RepositorySection] {
        loadCount += 1
        return sections
    }

    func waitForLoadCount(_ expectedCount: Int) async {
        while loadCount < expectedCount {
            await Task.yield()
        }
    }

    func currentLoadCount() -> Int {
        loadCount
    }
}

private actor SequencedDashboardDataSource: DashboardDataSource {
    let firstSections: [RepositorySection]
    let subsequentSections: [RepositorySection]
    private(set) var loadCount = 0

    init(firstSections: [RepositorySection], subsequentSections: [RepositorySection]) {
        self.firstSections = firstSections
        self.subsequentSections = subsequentSections
    }

    nonisolated func cliHealth() -> GitHubCLIHealth {
        .authenticated(username: "octocat")
    }

    func loadSections(for settings: AppSettings) async throws -> [RepositorySection] {
        loadCount += 1

        if loadCount == 1 {
            return firstSections
        }

        try await Task.sleep(for: .seconds(10))
        return subsequentSections
    }

    func waitForLoadCount(_ expectedCount: Int) async {
        while loadCount < expectedCount {
            await Task.yield()
        }
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

private actor DelayedDashboardDataSource: DashboardDataSource {
    let sections: [RepositorySection]
    private(set) var didStartLoading = false
    private var continuation: CheckedContinuation<Void, Never>?

    init(sections: [RepositorySection]) {
        self.sections = sections
    }

    nonisolated func cliHealth() -> GitHubCLIHealth {
        .authenticated(username: "octocat")
    }

    func loadSections(for settings: AppSettings) async throws -> [RepositorySection] {
        didStartLoading = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return sections
    }

    func waitUntilLoadStarts() async {
        while !didStartLoading {
            await Task.yield()
        }
    }

    func finishLoading() {
        continuation?.resume()
        continuation = nil
    }
}
