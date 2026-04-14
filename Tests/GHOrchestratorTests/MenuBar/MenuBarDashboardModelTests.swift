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

        let sections = [
            RepositorySection(
                repository: ObservedRepository(owner: "openai", name: "codex"),
                pullRequests: [
                    pullRequest(number: 1)
                ]
            )
        ]
        let model = MenuBarDashboardModel(
            settingsStore: store,
            dataSource: MockDashboardDataSource(sections: sections),
            sleeper: RecordingSleeper(),
            authenticationState: .authenticated(username: "octocat")
        )

        await waitForLoadedState(on: model)

        XCTAssertEqual(model.state, .loaded(sections))
        XCTAssertEqual(model.authenticationState, .authenticated(username: "octocat"))
    }

    func testEmptyRepositoryListShowsNoRepositoriesConfiguredWhenAuthenticated() {
        let model = MenuBarDashboardModel(
            settingsStore: SettingsStore(storageURL: makeIsolatedStorageURL()),
            dataSource: MockDashboardDataSource(sections: []),
            sleeper: RecordingSleeper(),
            authenticationState: .authenticated(username: "octocat")
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
            dataSource: MockDashboardDataSource(sections: []),
            sleeper: sleeper,
            authenticationState: .authenticated(username: "octocat")
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
            sleeper: RecordingSleeper(),
            authenticationState: .authenticated(username: "octocat")
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

        let dataSource = CountingDashboardDataSource(sections: [])
        let model = MenuBarDashboardModel(
            settingsStore: store,
            dataSource: dataSource,
            sleeper: RecordingSleeper(),
            authenticationState: .authenticated(username: "octocat")
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
            sleeper: RecordingSleeper(),
            authenticationState: .authenticated(username: "octocat")
        )

        await waitForLoadedState(on: model)
        model.refresh()
        await dataSource.waitForLoadCount(2)

        XCTAssertTrue(model.isRefreshing)
        XCTAssertEqual(model.contentState, .loaded(initialSections))
    }

    func testAuthenticationStateAndCommandFailureTransitions() async throws {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        store.settings = AppSettings(
            observedRepositories: [ObservedRepository(owner: "openai", name: "codex")]
        )

        let notConfiguredModel = MenuBarDashboardModel(
            settingsStore: store,
            dataSource: MockDashboardDataSource(sections: []),
            sleeper: RecordingSleeper(),
            authenticationState: .notConfigured
        )
        XCTAssertEqual(notConfiguredModel.state, .notConfigured)

        let signedOutModel = MenuBarDashboardModel(
            settingsStore: store,
            dataSource: MockDashboardDataSource(sections: []),
            sleeper: RecordingSleeper(),
            authenticationState: .signedOut
        )
        XCTAssertEqual(signedOutModel.state, .signedOut)

        let authorizingModel = MenuBarDashboardModel(
            settingsStore: store,
            dataSource: MockDashboardDataSource(sections: []),
            sleeper: RecordingSleeper(),
            authenticationState: .authorizing(userCode: "WDJB-MJHT", verificationURI: URL(string: "https://github.com/login/device")!)
        )
        XCTAssertEqual(authorizingModel.state, .authorizing)

        let authFailureModel = MenuBarDashboardModel(
            settingsStore: store,
            dataSource: MockDashboardDataSource(sections: []),
            sleeper: RecordingSleeper(),
            authenticationState: .authFailure(message: "bad callback")
        )
        XCTAssertEqual(authFailureModel.state, .authFailure("bad callback"))

        let failingModel = MenuBarDashboardModel(
            settingsStore: store,
            dataSource: FailingDashboardDataSource(),
            sleeper: RecordingSleeper(),
            authenticationState: .authenticated(username: "octocat")
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
    let sections: [RepositorySection]

    func loadSections(for _: AppSettings) async throws -> [RepositorySection] {
        sections
    }
}

private actor CountingDashboardDataSource: DashboardDataSource {
    let sections: [RepositorySection]
    private(set) var loadCount = 0

    init(sections: [RepositorySection]) {
        self.sections = sections
    }

    func loadSections(for _: AppSettings) async throws -> [RepositorySection] {
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

    func loadSections(for _: AppSettings) async throws -> [RepositorySection] {
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
    func loadSections(for _: AppSettings) async throws -> [RepositorySection] {
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

    func loadSections(for _: AppSettings) async throws -> [RepositorySection] {
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
