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

    func testChangingDashboardFiltersRefreshesWithScopeAndFocusedRepository() async throws {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        store.settings = AppSettings(
            observedRepositories: [
                ObservedRepository(owner: "openai", name: "codex"),
                ObservedRepository(owner: "swiftlang", name: "swift")
            ]
        )

        let dataSource = RecordingFilterDashboardDataSource(sections: [])
        let model = MenuBarDashboardModel(
            settingsStore: store,
            dataSource: dataSource,
            sleeper: RecordingSleeper(),
            authenticationState: .authenticated(username: "octocat")
        )

        await dataSource.waitForLoadCount(1)

        model.setPullRequestScope(.all)
        await dataSource.waitForLoadCount(2)

        model.toggleRepositoryCollapsed(repositoryID: "swiftlang/swift")
        XCTAssertEqual(model.collapsedRepositoryIDs, ["swiftlang/swift"])

        model.setFocusedRepositoryID(" swiftlang/swift ")
        await dataSource.waitForLoadCount(3)

        let filters = await dataSource.recordedFilters()
        XCTAssertEqual(filters.map(\.pullRequestScope), [.mine, .all, .all])
        XCTAssertEqual(filters.map(\.focusedRepositoryID), [nil, nil, "swiftlang/swift"])
        XCTAssertEqual(model.focusedRepositoryID, "swiftlang/swift")
        XCTAssertTrue(model.collapsedRepositoryIDs.isEmpty)
    }

    func testChangingDashboardFiltersIgnoresUnknownFocusedRepository() async throws {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        store.settings = AppSettings(
            observedRepositories: [
                ObservedRepository(owner: "openai", name: "codex")
            ]
        )

        let dataSource = RecordingFilterDashboardDataSource(sections: [])
        let model = MenuBarDashboardModel(
            settingsStore: store,
            dataSource: dataSource,
            sleeper: RecordingSleeper(),
            authenticationState: .authenticated(username: "octocat")
        )

        await dataSource.waitForLoadCount(1)

        model.setFocusedRepositoryID("swiftlang/swift")
        await Task.yield()

        let filters = await dataSource.recordedFilters()
        XCTAssertEqual(filters.count, 1)
        XCTAssertNil(model.focusedRepositoryID)
    }

    func testOnlyOnePullRequestDetailBubbleCanBeExpandedAtATime() {
        let model = MenuBarDashboardModel(
            settingsStore: SettingsStore(storageURL: makeIsolatedStorageURL()),
            dataSource: MockDashboardDataSource(sections: []),
            sleeper: RecordingSleeper(),
            authenticationState: .signedOut
        )

        model.toggleChecksExpansion(for: "openai/codex#1")
        XCTAssertEqual(model.expandedChecksPullRequestIDs, ["openai/codex#1"])
        XCTAssertTrue(model.expandedCommentPullRequestIDs.isEmpty)

        model.toggleCommentsExpansion(for: "openai/codex#2")
        XCTAssertTrue(model.expandedChecksPullRequestIDs.isEmpty)
        XCTAssertEqual(model.expandedCommentPullRequestIDs, ["openai/codex#2"])

        model.toggleChecksExpansion(for: "swiftlang/swift#3")
        XCTAssertEqual(model.expandedChecksPullRequestIDs, ["swiftlang/swift#3"])
        XCTAssertTrue(model.expandedCommentPullRequestIDs.isEmpty)

        model.toggleChecksExpansion(for: "swiftlang/swift#3")
        XCTAssertTrue(model.expandedChecksPullRequestIDs.isEmpty)
    }

    func testRepositoryCollapseStateTogglesByRepositoryID() {
        let model = MenuBarDashboardModel(
            settingsStore: SettingsStore(storageURL: makeIsolatedStorageURL()),
            dataSource: MockDashboardDataSource(sections: []),
            sleeper: RecordingSleeper(),
            authenticationState: .signedOut
        )

        model.toggleRepositoryCollapsed(repositoryID: " OpenAI/Codex ")
        XCTAssertEqual(model.collapsedRepositoryIDs, ["openai/codex"])

        model.toggleRepositoryCollapsed(repositoryID: "openai/codex")
        XCTAssertTrue(model.collapsedRepositoryIDs.isEmpty)
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

    func testRefreshFailurePreservesLoadedContentAndDisablesFilters() async throws {
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
        let dataSource = FailingAfterFirstLoadDashboardDataSource(
            firstSections: initialSections,
            errorMessage: "API rate limit exceeded for user ID 472467."
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
        await waitForRefreshWarning(on: model)

        XCTAssertEqual(model.state, .loaded(initialSections))
        XCTAssertEqual(model.contentState, .loaded(initialSections))
        XCTAssertEqual(model.refreshWarningMessage, "API rate limit exceeded for user ID 472467.")
        XCTAssertTrue(model.areDashboardFiltersDisabled)
    }

    func testHiddenPollingSkipsRefreshWhenPreviousRefreshIsStillRunning() async throws {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        store.settings = AppSettings(
            observedRepositories: [ObservedRepository(owner: "openai", name: "codex")]
        )

        let dataSource = DelayedDashboardDataSource(sections: [])
        let sleeper = ResumableSleeper()
        let model = MenuBarDashboardModel(
            settingsStore: store,
            dataSource: dataSource,
            sleeper: sleeper,
            authenticationState: .authenticated(username: "octocat")
        )

        await dataSource.waitUntilLoadStarts()
        await sleeper.finishNextSleep()
        await Task.yield()

        let loadCount = await dataSource.currentLoadCount()
        XCTAssertEqual(loadCount, 1)
        XCTAssertTrue(model.isRefreshing)

        await dataSource.finishLoading()
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
            XCTAssertEqual(failingModel.refreshWarningMessage, "synthetic failure")
            XCTAssertTrue(failingModel.areDashboardFiltersDisabled)
        } else {
            XCTFail("Expected command failure state")
        }
    }

    func testRetryWorkflowJobRefreshesLoadedContentOnSuccess() async throws {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        store.settings = AppSettings(
            observedRepositories: [ObservedRepository(owner: "openai", name: "codex")]
        )

        let sections = [
            RepositorySection(
                repository: ObservedRepository(owner: "openai", name: "codex"),
                pullRequests: [pullRequestWithFailedJob(number: 7)]
            )
        ]
        let dataSource = RetryableDashboardDataSource(sections: sections)
        let model = MenuBarDashboardModel(
            settingsStore: store,
            dataSource: dataSource,
            sleeper: RecordingSleeper(),
            authenticationState: .authenticated(username: "octocat")
        )

        await waitForLoadedState(on: model)
        model.retryWorkflowJob(
            repository: ObservedRepository(owner: "openai", name: "codex"),
            jobID: 700
        )

        XCTAssertTrue(model.isRetryingJob(700))
        await dataSource.waitForRerunCount(1)
        await waitForLoadCount(2, dataSource: dataSource)

        XCTAssertFalse(model.isRetryingJob(700))
        XCTAssertNil(model.retryErrorMessage(for: 700))

        let rerunRequests = await dataSource.recordedRerunRequests()
        XCTAssertEqual(rerunRequests.count, 1)
        XCTAssertEqual(rerunRequests[0].repository, ObservedRepository(owner: "openai", name: "codex"))
        XCTAssertEqual(rerunRequests[0].jobID, 700)
    }

    func testRetryWorkflowJobStoresInlineErrorWithoutReplacingLoadedState() async throws {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        store.settings = AppSettings(
            observedRepositories: [ObservedRepository(owner: "openai", name: "codex")]
        )

        let sections = [
            RepositorySection(
                repository: ObservedRepository(owner: "openai", name: "codex"),
                pullRequests: [pullRequestWithFailedJob(number: 9)]
            )
        ]
        let dataSource = RetryableDashboardDataSource(
            sections: sections,
            rerunError: ActionsJobRetryError.rerunFailed(
                repository: ObservedRepository(owner: "openai", name: "codex"),
                jobID: 900,
                message: "GitHub denied the retry request."
            )
        )
        let model = MenuBarDashboardModel(
            settingsStore: store,
            dataSource: dataSource,
            sleeper: RecordingSleeper(),
            authenticationState: .authenticated(username: "octocat")
        )

        await waitForLoadedState(on: model)
        model.retryWorkflowJob(
            repository: ObservedRepository(owner: "openai", name: "codex"),
            jobID: 900
        )

        await waitForRetryError(jobID: 900, on: model)

        XCTAssertFalse(model.isRetryingJob(900))
        XCTAssertEqual(model.retryErrorMessage(for: 900), "Failed to retry Actions job for openai/codex: GitHub denied the retry request.")
        XCTAssertEqual(model.state, .loaded(sections))
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

    private func waitForLoadCount(
        _ count: Int,
        dataSource: RetryableDashboardDataSource
    ) async {
        for _ in 0..<50 {
            if await dataSource.currentLoadCount() >= count {
                return
            }
            await Task.yield()
        }

        XCTFail("Timed out waiting for expected load count")
    }

    private func waitForRetryError(
        jobID: Int,
        on model: MenuBarDashboardModel
    ) async {
        for _ in 0..<50 {
            if model.retryErrorMessage(for: jobID) != nil {
                return
            }
            await Task.yield()
        }

        XCTFail("Timed out waiting for retry error")
    }

    private func waitForRefreshWarning(on model: MenuBarDashboardModel) async {
        for _ in 0..<50 {
            if model.refreshWarningMessage != nil {
                return
            }
            await Task.yield()
        }

        XCTFail("Timed out waiting for refresh warning")
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

private func pullRequestWithFailedJob(number: Int) -> PullRequestItem {
    PullRequestItem(
        repository: ObservedRepository(owner: "openai", name: "codex"),
        number: number,
        title: "PR #\(number)",
        url: URL(string: "https://github.com/openai/codex/pull/\(number)")!,
        isDraft: false,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(number)),
        reviewStatus: .approved,
        unresolvedReviewThreadCount: 0,
        checkRollupState: .failing,
        workflowRuns: [
            WorkflowRunItem(
                id: number * 10,
                name: "CI",
                status: "completed",
                conclusion: "failure",
                detailsURL: URL(string: "https://github.com/openai/codex/actions/runs/\(number * 10)")!,
                jobs: [
                    ActionJobItem(
                        id: number * 100,
                        name: "Build",
                        status: "completed",
                        conclusion: "failure",
                        detailsURL: URL(string: "https://github.com/openai/codex/actions/runs/\(number * 10)/job/\(number * 100)")!,
                        steps: [
                            ActionStepItem(
                                number: 1,
                                name: "Checkout",
                                status: "completed",
                                conclusion: "success",
                                detailsURL: URL(string: "https://github.com/openai/codex/actions/runs/\(number * 10)/job/\(number * 100)#step:1:1")!
                            ),
                            ActionStepItem(
                                number: 2,
                                name: "Test",
                                status: "completed",
                                conclusion: "failure",
                                detailsURL: URL(string: "https://github.com/openai/codex/actions/runs/\(number * 10)/job/\(number * 100)#step:2:1")!
                            )
                        ]
                    )
                ]
            )
        ]
    )
}

private struct MockDashboardDataSource: DashboardDataSource {
    let sections: [RepositorySection]

    func loadSections(
        for _: AppSettings,
        filter _: DashboardFilter
    ) async throws -> [RepositorySection] {
        sections
    }

    func rerunWorkflowJob(
        repository _: ObservedRepository,
        jobID _: Int
    ) async throws {}
}

private actor CountingDashboardDataSource: DashboardDataSource {
    let sections: [RepositorySection]
    private(set) var loadCount = 0

    init(sections: [RepositorySection]) {
        self.sections = sections
    }

    func loadSections(
        for _: AppSettings,
        filter _: DashboardFilter
    ) async throws -> [RepositorySection] {
        loadCount += 1
        return sections
    }

    func rerunWorkflowJob(
        repository _: ObservedRepository,
        jobID _: Int
    ) async throws {}

    func waitForLoadCount(_ expectedCount: Int) async {
        while loadCount < expectedCount {
            await Task.yield()
        }
    }

    func currentLoadCount() -> Int {
        loadCount
    }
}

private actor RecordingFilterDashboardDataSource: DashboardDataSource {
    let sections: [RepositorySection]
    private(set) var filters: [DashboardFilter] = []

    init(sections: [RepositorySection]) {
        self.sections = sections
    }

    func loadSections(
        for _: AppSettings,
        filter: DashboardFilter
    ) async throws -> [RepositorySection] {
        filters.append(filter)
        return sections
    }

    func rerunWorkflowJob(
        repository _: ObservedRepository,
        jobID _: Int
    ) async throws {}

    func waitForLoadCount(_ expectedCount: Int) async {
        while filters.count < expectedCount {
            await Task.yield()
        }
    }

    func recordedFilters() -> [DashboardFilter] {
        filters
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

    func loadSections(
        for _: AppSettings,
        filter _: DashboardFilter
    ) async throws -> [RepositorySection] {
        loadCount += 1

        if loadCount == 1 {
            return firstSections
        }

        try await Task.sleep(for: .seconds(10))
        return subsequentSections
    }

    func rerunWorkflowJob(
        repository _: ObservedRepository,
        jobID _: Int
    ) async throws {}

    func waitForLoadCount(_ expectedCount: Int) async {
        while loadCount < expectedCount {
            await Task.yield()
        }
    }
}

private actor FailingAfterFirstLoadDashboardDataSource: DashboardDataSource {
    struct SyntheticError: LocalizedError {
        let message: String

        var errorDescription: String? { message }
    }

    let firstSections: [RepositorySection]
    let errorMessage: String
    private(set) var loadCount = 0

    init(firstSections: [RepositorySection], errorMessage: String) {
        self.firstSections = firstSections
        self.errorMessage = errorMessage
    }

    func loadSections(
        for _: AppSettings,
        filter _: DashboardFilter
    ) async throws -> [RepositorySection] {
        loadCount += 1

        if loadCount == 1 {
            return firstSections
        }

        throw SyntheticError(message: errorMessage)
    }

    func rerunWorkflowJob(
        repository _: ObservedRepository,
        jobID _: Int
    ) async throws {}

    func waitForLoadCount(_ expectedCount: Int) async {
        while loadCount < expectedCount {
            await Task.yield()
        }
    }
}

private struct FailingDashboardDataSource: DashboardDataSource {
    func loadSections(
        for _: AppSettings,
        filter _: DashboardFilter
    ) async throws -> [RepositorySection] {
        struct SyntheticError: LocalizedError {
            var errorDescription: String? { "synthetic failure" }
        }

        throw SyntheticError()
    }

    func rerunWorkflowJob(
        repository _: ObservedRepository,
        jobID _: Int
    ) async throws {}
}

private actor RecordingSleeper: DashboardSleepProviding {
    private(set) var recordedDurations: [Duration] = []

    func sleep(for duration: Duration) async throws {
        recordedDurations.append(duration)
        throw CancellationError()
    }
}

private actor ResumableSleeper: DashboardSleepProviding {
    private var continuations: [CheckedContinuation<Void, any Error>] = []

    func sleep(for _: Duration) async throws {
        try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func finishNextSleep() async {
        while continuations.isEmpty {
            await Task.yield()
        }

        continuations.removeFirst().resume()
    }
}

private actor DelayedDashboardDataSource: DashboardDataSource {
    let sections: [RepositorySection]
    private(set) var didStartLoading = false
    private(set) var loadCount = 0
    private var continuation: CheckedContinuation<Void, Never>?

    init(sections: [RepositorySection]) {
        self.sections = sections
    }

    func loadSections(
        for _: AppSettings,
        filter _: DashboardFilter
    ) async throws -> [RepositorySection] {
        loadCount += 1
        didStartLoading = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return sections
    }

    func rerunWorkflowJob(
        repository _: ObservedRepository,
        jobID _: Int
    ) async throws {}

    func waitUntilLoadStarts() async {
        while !didStartLoading {
            await Task.yield()
        }
    }

    func finishLoading() {
        continuation?.resume()
        continuation = nil
    }

    func currentLoadCount() -> Int {
        loadCount
    }
}

private actor RetryableDashboardDataSource: DashboardDataSource {
    struct RerunRequest: Equatable {
        let repository: ObservedRepository
        let jobID: Int
    }

    let sections: [RepositorySection]
    let rerunError: (any Error & Sendable)?

    private(set) var loadCount = 0
    private(set) var rerunRequests: [RerunRequest] = []

    init(
        sections: [RepositorySection],
        rerunError: (any Error & Sendable)? = nil
    ) {
        self.sections = sections
        self.rerunError = rerunError
    }

    func loadSections(
        for _: AppSettings,
        filter _: DashboardFilter
    ) async throws -> [RepositorySection] {
        loadCount += 1
        return sections
    }

    func rerunWorkflowJob(
        repository: ObservedRepository,
        jobID: Int
    ) async throws {
        rerunRequests.append(RerunRequest(repository: repository, jobID: jobID))

        if let rerunError {
            throw rerunError
        }
    }

    func waitForRerunCount(_ expectedCount: Int) async {
        while rerunRequests.count < expectedCount {
            await Task.yield()
        }
    }

    func recordedRerunRequests() -> [RerunRequest] {
        rerunRequests
    }

    func currentLoadCount() -> Int {
        loadCount
    }
}
