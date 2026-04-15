import Foundation
import XCTest
@testable import GHOrchestrator
import GHOrchestratorCore

@MainActor
final class RepositoryNotificationMonitorTests: XCTestCase {
    func testMonitorEstablishesBaselineWithoutDeliveringFirstLoad() async {
        let store = configuredStore()
        let dataSource = SequencedNotificationDataSource(
            responses: [
                [section(reviewStatus: .approved)]
            ]
        )
        let delivery = RecordingNotificationDelivery(status: .authorized)

        _ = RepositoryNotificationMonitor(
            settingsStore: store,
            dataSource: dataSource,
            sleeper: NotificationCancellingSleeper(),
            delivery: delivery,
            authenticationState: .authenticated(username: "octocat")
        )

        await dataSource.waitForLoadCount(1)

        XCTAssertTrue(delivery.deliveredEvents.isEmpty)
    }

    func testMonitorDeliversAuthorizedMatchingEventsAfterBaseline() async {
        let store = configuredStore()
        let dataSource = SequencedNotificationDataSource(
            responses: [
                [section(reviewStatus: .reviewRequired)],
                [section(reviewStatus: .approved)]
            ]
        )
        let sleeper = ResumableNotificationSleeper()
        let delivery = RecordingNotificationDelivery(status: .authorized)

        _ = RepositoryNotificationMonitor(
            settingsStore: store,
            dataSource: dataSource,
            sleeper: sleeper,
            delivery: delivery,
            authenticationState: .authenticated(username: "octocat")
        )

        await dataSource.waitForLoadCount(1)
        await sleeper.finishNextSleep()
        await dataSource.waitForLoadCount(2)
        await waitUntil("notification delivery") {
            delivery.deliveredEvents.count == 1
        }

        XCTAssertEqual(delivery.deliveredEvents.map(\.trigger), [.approval])
    }

    func testMonitorSuppressesDeliveryWhenNotificationsAreUnauthorized() async {
        let store = configuredStore()
        let dataSource = SequencedNotificationDataSource(
            responses: [
                [section(reviewStatus: .reviewRequired)],
                [section(reviewStatus: .approved)]
            ]
        )
        let sleeper = ResumableNotificationSleeper()
        let delivery = RecordingNotificationDelivery(status: .denied)

        _ = RepositoryNotificationMonitor(
            settingsStore: store,
            dataSource: dataSource,
            sleeper: sleeper,
            delivery: delivery,
            authenticationState: .authenticated(username: "octocat")
        )

        await dataSource.waitForLoadCount(1)
        await sleeper.finishNextSleep()
        await dataSource.waitForLoadCount(2)

        XCTAssertTrue(delivery.deliveredEvents.isEmpty)
    }

    func testMonitorUsesAllPullRequestScopeAndEnabledRepositoriesOnly() async {
        let enabledRepository = ObservedRepository(owner: "openai", name: "codex")
        let disabledRepository = ObservedRepository(owner: "swiftlang", name: "swift")
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        store.settings = AppSettings(
            observedRepositories: [
                enabledRepository,
                disabledRepository
            ],
            repositoryNotificationSettings: [
                RepositoryNotificationSettings(repository: enabledRepository, enabled: true),
                RepositoryNotificationSettings(repository: disabledRepository, enabled: false)
            ]
        )
        let dataSource = SequencedNotificationDataSource(responses: [[]])

        _ = RepositoryNotificationMonitor(
            settingsStore: store,
            dataSource: dataSource,
            sleeper: NotificationCancellingSleeper(),
            delivery: RecordingNotificationDelivery(status: .authorized),
            authenticationState: .authenticated(username: "octocat")
        )

        await dataSource.waitForLoadCount(1)

        let filters = await dataSource.recordedFilters()
        let settings = await dataSource.recordedSettings()

        XCTAssertEqual(filters.map(\.pullRequestScope), [.all])
        XCTAssertEqual(filters.map(\.focusedRepositoryID), [nil])
        XCTAssertEqual(settings[0].observedRepositories.map(\.fullName), ["openai/codex"])
    }

    func testNotificationResponseRouterOpensStoredTargetURL() async {
        var openedURLs: [URL] = []
        let router = NotificationResponseRouter { url in
            openedURLs.append(url)
        }
        let targetURL = URL(string: "https://github.com/openai/codex/pull/1")!

        router.route(userInfo: [
            LocalNotificationUserInfo.targetURLKey: targetURL.absoluteString
        ])

        await waitUntil("notification URL routing") {
            openedURLs == [targetURL]
        }
    }

    private func configuredStore() -> SettingsStore {
        let repository = ObservedRepository(owner: "openai", name: "codex")
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        store.settings = AppSettings(
            observedRepositories: [repository],
            repositoryNotificationSettings: [
                RepositoryNotificationSettings(repository: repository, enabled: true)
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
            .appendingPathComponent("GHOrchestrator.RepositoryNotificationMonitorTests.\(UUID().uuidString)", isDirectory: true)
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

@MainActor
private final class RecordingNotificationDelivery: LocalNotificationDelivering {
    private(set) var deliveredEvents: [RepositoryNotificationEvent] = []
    var status: LocalNotificationAuthorizationStatus

    init(status: LocalNotificationAuthorizationStatus) {
        self.status = status
    }

    func authorizationStatus() async -> LocalNotificationAuthorizationStatus {
        status
    }

    func requestAuthorization() async throws -> LocalNotificationAuthorizationStatus {
        status = .authorized
        return status
    }

    func deliver(_ event: RepositoryNotificationEvent) async throws {
        deliveredEvents.append(event)
    }
}

private actor SequencedNotificationDataSource: DashboardDataSource {
    private let responses: [[RepositorySection]]
    private var loadCount = 0
    private var filters: [DashboardFilter] = []
    private var settings: [AppSettings] = []

    init(responses: [[RepositorySection]]) {
        self.responses = responses
    }

    func loadSections(
        for settings: AppSettings,
        filter: DashboardFilter
    ) async throws -> [RepositorySection] {
        self.settings.append(settings)
        filters.append(filter)

        let responseIndex = min(loadCount, max(responses.count - 1, 0))
        loadCount += 1

        return responses.isEmpty ? [] : responses[responseIndex]
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

    func recordedFilters() -> [DashboardFilter] {
        filters
    }

    func recordedSettings() -> [AppSettings] {
        settings
    }
}

private struct NotificationCancellingSleeper: DashboardSleepProviding {
    func sleep(for _: Duration) async throws {
        throw CancellationError()
    }
}

private actor ResumableNotificationSleeper: DashboardSleepProviding {
    private var continuations: [CheckedContinuation<Void, any Error>] = []

    func sleep(for _: Duration) async throws {
        try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func finishNextSleep() {
        guard !continuations.isEmpty else {
            return
        }

        continuations.removeFirst().resume()
    }
}

private func section(
    reviewStatus: ReviewStatus
) -> RepositorySection {
    let repository = ObservedRepository(owner: "openai", name: "codex")
    return RepositorySection(
        repository: repository,
        pullRequests: [
            PullRequestItem(
                repository: repository,
                number: 1,
                title: "Add notifications",
                url: URL(string: "https://github.com/openai/codex/pull/1")!,
                isDraft: false,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                reviewStatus: reviewStatus,
                unresolvedReviewThreadCount: 0,
                checkRollupState: .passing
            )
        ]
    )
}
