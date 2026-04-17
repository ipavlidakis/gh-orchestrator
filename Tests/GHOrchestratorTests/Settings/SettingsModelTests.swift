import XCTest
@testable import GHOrchestrator
import GHOrchestratorCore

@MainActor
final class SettingsModelTests: XCTestCase {
    func testManualRefreshHookInvokesAssignedAction() {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        var refreshCount = 0
        let model = SettingsModel(store: store, manualRefreshAction: {
            refreshCount += 1
        })

        XCTAssertTrue(model.hasManualRefreshAction)

        model.requestManualRefresh()

        XCTAssertEqual(refreshCount, 1)
    }

    func testAuthenticationDescriptionAndActionsReflectState() {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        var signInCount = 0
        var signOutCount = 0
        let model = SettingsModel(
            store: store,
            authenticationState: .signedOut,
            signInAction: { signInCount += 1 },
            signOutAction: { signOutCount += 1 }
        )

        XCTAssertEqual(model.authenticationDescription, "Not signed in")
        XCTAssertTrue(model.canStartSignIn)
        XCTAssertFalse(model.canSignOut)

        model.requestSignIn()
        XCTAssertEqual(signInCount, 1)

        model.authenticationState = .authenticated(username: "octocat")
        XCTAssertEqual(model.authenticationDescription, "Signed in as octocat")
        XCTAssertTrue(model.canSignOut)

        model.requestSignOut()
        XCTAssertEqual(signOutCount, 1)
    }

#if DEBUG
    func testNotificationDebugPreviewUsesRepoLocalDefaultRepositoryAndAuthor() {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        let model = SettingsModel(store: store)

        XCTAssertEqual(model.notificationDebugPreview.repositoryOwner, "ipavlidakis")
        XCTAssertEqual(model.notificationDebugPreview.repositoryName, "gh-orchestrator")
        XCTAssertEqual(model.notificationDebugPreview.authorLogin, "ipavlidakis")
    }

    func testNotificationDebugPreviewBuildsEventAndInvokesAssignedAction() async {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        var receivedEvent: RepositoryNotificationEvent?
        let model = SettingsModel(
            store: store,
            sendNotificationPreviewAction: { event in
                receivedEvent = event
            }
        )

        model.notificationDebugPreview.selectedTrigger = .workflowJobCompleted
        model.notificationDebugPreview.repositoryOwner = "swiftlang"
        model.notificationDebugPreview.repositoryName = "swift"
        model.notificationDebugPreview.pullRequestNumberText = "42"
        model.notificationDebugPreview.pullRequestTitle = "Stabilize CI"
        model.notificationDebugPreview.workflowName = "PR"
        model.notificationDebugPreview.workflowJobName = "Linux"
        model.notificationDebugPreview.workflowJobConclusion = "failure"
        model.notificationDebugPreview.targetURLText = "https://github.com/swiftlang/swift/actions/runs/42/job/7"

        model.requestNotificationDebugPreview()

        await waitUntil("notification debug preview send") {
            receivedEvent != nil
        }

        XCTAssertEqual(model.notificationDebugPreview.deliveryState, .delivered("Preview delivered."))
        XCTAssertEqual(receivedEvent?.trigger, .workflowJobCompleted)
        XCTAssertEqual(receivedEvent?.repository.fullName, "swiftlang/swift")
        XCTAssertEqual(receivedEvent?.pullRequestNumber, 42)
        XCTAssertEqual(receivedEvent?.pullRequestTitle, "Stabilize CI")
        XCTAssertEqual(receivedEvent?.workflowName, "PR")
        XCTAssertEqual(receivedEvent?.workflowJobName, "Linux")
        XCTAssertEqual(receivedEvent?.workflowJobConclusion, "failure")
        XCTAssertEqual(receivedEvent?.targetURL.absoluteString, "https://github.com/swiftlang/swift/actions/runs/42/job/7")
    }

    func testNotificationDebugPreviewValidationFailurePreventsSend() {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        var sendCount = 0
        let model = SettingsModel(
            store: store,
            sendNotificationPreviewAction: { _ in
                sendCount += 1
            }
        )

        model.notificationDebugPreview.repositoryOwner = ""
        model.requestNotificationDebugPreview()

        XCTAssertEqual(sendCount, 0)
        XCTAssertEqual(
            model.notificationDebugPreview.deliveryState,
            .failed("Enter a valid repository owner and name.")
        )
    }
#endif

    func testInvalidRepositoryInputSurfacesValidationMessagesAndPersistsValidEntries() {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        let model = SettingsModel(store: store)

        model.repositoryText = """
        openai/codex
        invalid entry
        swiftlang/swift
        """

        XCTAssertEqual(
            store.settings.observedRepositories.map(\.fullName),
            ["openai/codex", "swiftlang/swift"]
        )
        XCTAssertEqual(
            model.repositoryValidationMessages,
            ["Invalid repository entry: invalid entry"]
        )
    }

    func testPollingIntervalPersistenceClampsAndWritesImmediately() {
        let storageURL = makeIsolatedStorageURL()
        let store = SettingsStore(storageURL: storageURL)
        let model = SettingsModel(store: store)

        model.pollingIntervalText = "1"

        XCTAssertEqual(model.pollingIntervalText, "15")
        XCTAssertEqual(store.settings.pollingIntervalSeconds, 15)

        let reloadedStore = SettingsStore(storageURL: storageURL)

        XCTAssertEqual(reloadedStore.settings.pollingIntervalSeconds, 15)
    }

    func testPollingIntervalAdvisoryAppearsForShortIntervals() {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        let model = SettingsModel(store: store)

        model.pollingIntervalText = "15"

        XCTAssertNotNil(model.pollingIntervalAdvisoryMessage)
        XCTAssertTrue(model.pollingIntervalAdvisoryMessage?.contains("rate limits") == true)

        model.pollingIntervalText = "60"

        XCTAssertNil(model.pollingIntervalAdvisoryMessage)
    }

    func testHideDockIconPersistenceWritesImmediately() {
        let storageURL = makeIsolatedStorageURL()
        let store = SettingsStore(storageURL: storageURL)
        let model = SettingsModel(store: store)

        XCTAssertFalse(model.hideDockIcon)

        model.hideDockIcon = true

        XCTAssertTrue(store.settings.hideDockIcon)

        let reloadedStore = SettingsStore(storageURL: storageURL)

        XCTAssertTrue(reloadedStore.settings.hideDockIcon)
    }

    func testStartAtLoginPersistenceAndSystemSettingsAction() {
        let storageURL = makeIsolatedStorageURL()
        let store = SettingsStore(storageURL: storageURL)
        var openLoginItemsCount = 0
        let model = SettingsModel(
            store: store,
            startAtLoginRegistrationStatus: .requiresApproval,
            openLoginItemsSettingsAction: {
                openLoginItemsCount += 1
            }
        )

        XCTAssertFalse(model.startAtLogin)
        XCTAssertFalse(store.settings.startAtLogin)

        model.startAtLogin = true

        XCTAssertTrue(store.settings.startAtLogin)
        XCTAssertTrue(model.canOpenLoginItemsSettings)
        XCTAssertTrue(model.startAtLoginSubtitle.contains("needs approval"))

        model.requestOpenLoginItemsSettings()

        XCTAssertEqual(openLoginItemsCount, 1)

        let reloadedStore = SettingsStore(storageURL: storageURL)

        XCTAssertTrue(reloadedStore.settings.startAtLogin)
    }

    func testAutomaticUpdateCheckPreferencePersists() {
        let storageURL = makeIsolatedStorageURL()
        let store = SettingsStore(storageURL: storageURL)
        let model = SoftwareUpdateModel(
            store: store,
            checker: StubSoftwareUpdateChecker(result: .upToDate(currentVersion: "1.0.0")),
            installer: RecordingSoftwareUpdateInstaller(),
            currentVersionProvider: { "1.0.0" }
        )

        XCTAssertTrue(model.automaticallyCheckForUpdates)

        model.automaticallyCheckForUpdates = false

        XCTAssertFalse(store.settings.automaticallyCheckForUpdates)

        let reloadedStore = SettingsStore(storageURL: storageURL)

        XCTAssertFalse(reloadedStore.settings.automaticallyCheckForUpdates)
    }

    func testGraphQLDashboardLimitPersistenceClampsAndWritesImmediately() {
        let storageURL = makeIsolatedStorageURL()
        let store = SettingsStore(storageURL: storageURL)
        let model = SettingsModel(store: store)

        XCTAssertEqual(model.graphQLSearchResultLimit, 10)
        XCTAssertEqual(model.graphQLReviewThreadLimit, 10)
        XCTAssertEqual(model.graphQLReviewThreadCommentLimit, 5)
        XCTAssertEqual(model.graphQLCheckContextLimit, 15)

        model.graphQLSearchResultLimit = 30
        model.graphQLReviewThreadLimit = 40
        model.graphQLReviewThreadCommentLimit = 99
        model.graphQLCheckContextLimit = 0

        XCTAssertEqual(store.settings.graphQLSearchResultLimit, 30)
        XCTAssertEqual(store.settings.graphQLReviewThreadLimit, 40)
        XCTAssertEqual(store.settings.graphQLReviewThreadCommentLimit, 20)
        XCTAssertEqual(store.settings.graphQLCheckContextLimit, 1)

        let reloadedStore = SettingsStore(storageURL: storageURL)

        XCTAssertEqual(reloadedStore.settings.graphQLSearchResultLimit, 30)
        XCTAssertEqual(reloadedStore.settings.graphQLReviewThreadLimit, 40)
        XCTAssertEqual(reloadedStore.settings.graphQLReviewThreadCommentLimit, 20)
        XCTAssertEqual(reloadedStore.settings.graphQLCheckContextLimit, 1)
    }

    func testAddObservedRepositoryPersistsValidEntry() {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        let model = SettingsModel(store: store)

        let didAdd = model.addObservedRepository(from: "openai/codex")

        XCTAssertTrue(didAdd)
        XCTAssertEqual(store.settings.observedRepositories.map(\.fullName), ["openai/codex"])
        XCTAssertTrue(model.repositoryValidationMessages.isEmpty)
    }

    func testAddObservedRepositoryRejectsInvalidAndDuplicateEntries() {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        store.settings.observedRepositories = [ObservedRepository(owner: "openai", name: "codex")]
        let model = SettingsModel(store: store)

        XCTAssertFalse(model.addObservedRepository(from: "not valid"))
        XCTAssertEqual(model.repositoryValidationMessages, ["Invalid repository entry: not valid"])

        XCTAssertFalse(model.addObservedRepository(from: "OPENAI/CODEX"))
        XCTAssertEqual(model.repositoryValidationMessages, ["Repository already added: OPENAI/CODEX"])
    }

    func testRemoveObservedRepositoriesRemovesSelectedIDs() {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        store.settings.observedRepositories = [
            ObservedRepository(owner: "openai", name: "codex"),
            ObservedRepository(owner: "swiftlang", name: "swift"),
        ]
        let model = SettingsModel(store: store)

        model.removeObservedRepositories(withIDs: ["openai/codex"])

        XCTAssertEqual(store.settings.observedRepositories.map(\.fullName), ["swiftlang/swift"])
    }

    func testRemoveObservedRepositoriesNormalizesSelectedIDs() {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        store.settings.observedRepositories = [
            ObservedRepository(owner: "OpenAI", name: "Codex"),
            ObservedRepository(owner: "swiftlang", name: "swift"),
        ]
        let model = SettingsModel(store: store)

        model.removeObservedRepositories(withIDs: [" OPENAI/CODEX "])

        XCTAssertEqual(store.settings.observedRepositories.map(\.fullName), ["swiftlang/swift"])
    }

    func testRepositoryNotificationSettingsPersistTriggerTogglesAndWorkflowFilters() {
        let storageURL = makeIsolatedStorageURL()
        let store = SettingsStore(storageURL: storageURL)
        store.settings.observedRepositories = [
            ObservedRepository(owner: "openai", name: "codex")
        ]
        let model = SettingsModel(store: store)

        model.setRepositoryNotificationsEnabled(true, repositoryID: "openai/codex")
        model.setNotificationTrigger(.approval, isEnabled: false, repositoryID: "openai/codex")
        model.setWorkflowNameFilterText("CI\nRelease, ci", repositoryID: "openai/codex")

        let settings = store.settings.notificationSettings(forRepositoryID: "openai/codex")

        XCTAssertEqual(settings?.repositoryID, "openai/codex")
        XCTAssertEqual(settings?.enabled, true)
        XCTAssertFalse(settings?.enabledTriggers.contains(.approval) ?? true)
        XCTAssertTrue(settings?.enabledTriggers.contains(.changesRequested) ?? false)
        XCTAssertEqual(settings?.workflowNameFilters, ["ci", "release"])

        let reloadedStore = SettingsStore(storageURL: storageURL)
        XCTAssertEqual(reloadedStore.settings.notificationSettings(forRepositoryID: "openai/codex"), settings)
    }

    func testWorkflowNameLoadingAndSelectionUsesFetchedRepositoryWorkflows() async {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        store.settings.observedRepositories = [
            ObservedRepository(owner: "openai", name: "codex")
        ]
        let workflowListService = StubActionsWorkflowListing(
            workflows: [
                ActionsWorkflowItem(id: 1, name: "CI", path: ".github/workflows/ci.yml", state: "active"),
                ActionsWorkflowItem(id: 2, name: "Release", path: ".github/workflows/release.yml", state: "active")
            ]
        )
        let model = SettingsModel(
            store: store,
            workflowListService: workflowListService
        )

        model.loadWorkflowNamesIfNeeded(repositoryID: "openai/codex")

        await waitUntil("workflow names load") {
            if case .loaded(["CI", "Release"]) = model.workflowListState(repositoryID: "openai/codex") {
                return true
            }

            return false
        }

        XCTAssertEqual(model.workflowNameFilterSummary(repositoryID: "openai/codex"), "All workflows")

        model.setWorkflowNameFilter("Release", isSelected: true, repositoryID: "openai/codex")

        XCTAssertTrue(model.isWorkflowNameFilterSelected("release", repositoryID: "openai/codex"))
        XCTAssertEqual(model.workflowNameFilterSummary(repositoryID: "openai/codex"), "1 selected")
        XCTAssertEqual(
            store.settings.notificationSettings(forRepositoryID: "openai/codex")?.workflowNameFilters,
            ["release"]
        )

        model.clearWorkflowNameFilters(repositoryID: "openai/codex")

        XCTAssertEqual(model.workflowNameFilterSummary(repositoryID: "openai/codex"), "All workflows")
    }

    func testWorkflowJobNameLoadingAndSelectionUsesFetchedWorkflowJobs() async {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        store.settings.observedRepositories = [
            ObservedRepository(owner: "openai", name: "codex")
        ]
        let workflow = ActionsWorkflowItem(id: 1, name: "CI", path: ".github/workflows/ci.yml", state: "active")
        let model = SettingsModel(
            store: store,
            workflowListService: StubActionsWorkflowListing(workflows: [workflow]),
            workflowJobListService: StubActionsWorkflowJobListing(jobNames: ["Build", "Test"])
        )

        model.loadWorkflowNamesIfNeeded(repositoryID: "openai/codex")
        await waitUntil("workflow names load") {
            !model.availableWorkflows(repositoryID: "openai/codex").isEmpty
        }

        model.loadWorkflowJobNamesIfNeeded(
            repositoryID: "openai/codex",
            workflow: workflow
        )
        await waitUntil("workflow job names load") {
            if case .loaded(["Build", "Test"]) = model.workflowJobListState(repositoryID: "openai/codex", workflowName: "CI") {
                return true
            }

            return false
        }

        XCTAssertEqual(model.workflowJobNameFilterSummary(repositoryID: "openai/codex", workflowName: "CI"), "All jobs")

        model.setWorkflowJobNameFilter(
            "Test",
            isSelected: true,
            repositoryID: "openai/codex",
            workflowName: "CI"
        )

        XCTAssertTrue(model.isWorkflowJobNameFilterSelected("test", repositoryID: "openai/codex", workflowName: "ci"))
        XCTAssertEqual(model.workflowJobNameFilterSummary(repositoryID: "openai/codex", workflowName: "CI"), "1 selected")
        XCTAssertEqual(
            store.settings.notificationSettings(forRepositoryID: "openai/codex")?.workflowJobNameFiltersByWorkflowName,
            ["ci": ["test"]]
        )

        model.clearWorkflowJobNameFilters(repositoryID: "openai/codex", workflowName: "CI")

        XCTAssertEqual(model.workflowJobNameFilterSummary(repositoryID: "openai/codex", workflowName: "CI"), "All jobs")
    }

    func testActionsInsightsSelectionPersistsAndRefreshesDashboard() async throws {
        let storageURL = makeIsolatedStorageURL()
        let store = SettingsStore(storageURL: storageURL)
        store.settings.observedRepositories = [
            ObservedRepository(owner: "openai", name: "codex")
        ]
        let workflow = ActionsWorkflowItem(id: 42, name: "CI", path: ".github/workflows/ci.yml", state: "active")
        let insightsService = StubActionsInsightsLoading(
            dashboard: ActionsInsightsDashboard(
                dateInterval: DateInterval(
                    start: Date(timeIntervalSince1970: 0),
                    end: Date(timeIntervalSince1970: 60)
                ),
                summary: ActionsInsightsSummary(
                    totalCount: 2,
                    successCount: 1,
                    failureCount: 1,
                    averageDurationSeconds: 120
                ),
                dataPoints: []
            )
        )
        let model = SettingsModel(
            store: store,
            authenticationState: .authenticated(username: "octocat"),
            workflowListService: StubActionsWorkflowListing(workflows: [workflow]),
            workflowJobListService: StubActionsWorkflowJobListing(jobNames: ["Build", "Test"]),
            actionsInsightsService: insightsService
        )

        model.loadActionsInsightsDependenciesIfNeeded()

        await waitUntil("workflow names load") {
            !model.availableWorkflows(repositoryID: "openai/codex").isEmpty
        }

        model.setActionsInsightsRepositoryID("openai/codex")
        model.setActionsInsightsWorkflowID(42)
        model.setActionsInsightsJobName("Test")
        model.actionsInsightsPeriod = .last90Days
        model.refreshActionsInsights(now: try XCTUnwrap(parseISO8601Date("2026-04-15T12:00:00Z")))

        await waitUntil("Actions insights load") {
            if case .loaded = model.actionsInsightsState {
                return true
            }

            return false
        }

        XCTAssertEqual(store.settings.actionsInsightsSelection.repositoryID, "openai/codex")
        XCTAssertEqual(store.settings.actionsInsightsSelection.workflowID, 42)
        XCTAssertEqual(store.settings.actionsInsightsSelection.workflowName, "CI")
        XCTAssertEqual(store.settings.actionsInsightsSelection.jobName, "Test")
        XCTAssertEqual(store.settings.actionsInsightsSelection.period, .last90Days)

        let request = await insightsService.lastRequest
        XCTAssertEqual(request?.repository.fullName, "openai/codex")
        XCTAssertEqual(request?.workflow.id, 42)
        XCTAssertEqual(request?.jobName, "Test")
        XCTAssertEqual(request?.period, .last90Days)

        let reloadedStore = SettingsStore(storageURL: storageURL)
        XCTAssertEqual(reloadedStore.settings.actionsInsightsSelection, store.settings.actionsInsightsSelection)
    }

    func testWorkflowNameLoadingSurfacesFailures() async {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        store.settings.observedRepositories = [
            ObservedRepository(owner: "openai", name: "codex")
        ]
        let model = SettingsModel(
            store: store,
            workflowListService: StubActionsWorkflowListing(
                error: ActionsWorkflowListError.requestFailed(
                    repository: ObservedRepository(owner: "openai", name: "codex"),
                    message: "Actions disabled"
                )
            )
        )

        model.loadWorkflowNamesIfNeeded(repositoryID: "openai/codex")

        await waitUntil("workflow load failure") {
            if case .failed(let message) = model.workflowListState(repositoryID: "openai/codex") {
                return message.contains("Actions disabled")
            }

            return false
        }
    }

    func testRemovingObservedRepositoryReconcilesNotificationSettings() {
        let store = SettingsStore(storageURL: makeIsolatedStorageURL())
        store.settings = AppSettings(
            observedRepositories: [
                ObservedRepository(owner: "openai", name: "codex"),
                ObservedRepository(owner: "swiftlang", name: "swift")
            ],
            actionsInsightsSelection: ActionsInsightsSelection(
                repositoryID: "openai/codex",
                workflowID: 42,
                workflowName: "CI",
                jobName: "Test",
                period: .last90Days
            ),
            repositoryNotificationSettings: [
                RepositoryNotificationSettings(repositoryID: "openai/codex", enabled: true),
                RepositoryNotificationSettings(repositoryID: "swiftlang/swift", enabled: true)
            ]
        )
        let model = SettingsModel(store: store)

        model.removeObservedRepositories(withIDs: ["openai/codex"])

        XCTAssertEqual(store.settings.observedRepositories.map(\.fullName), ["swiftlang/swift"])
        XCTAssertEqual(store.settings.repositoryNotificationSettings.map(\.repositoryID), ["swiftlang/swift"])
        XCTAssertNil(store.settings.actionsInsightsSelection.repositoryID)
        XCTAssertNil(store.settings.actionsInsightsSelection.workflowID)
        XCTAssertNil(store.settings.actionsInsightsSelection.workflowName)
        XCTAssertNil(store.settings.actionsInsightsSelection.jobName)
        XCTAssertEqual(store.settings.actionsInsightsSelection.period, .last90Days)
    }

    private func makeIsolatedStorageURL() -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GHOrchestrator.SettingsModelTests.\(UUID().uuidString)", isDirectory: true)
        let storageURL = rootURL
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("GHOrchestrator", isDirectory: true)
            .appendingPathComponent("settings.json", isDirectory: false)

        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        return storageURL
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

    private func parseISO8601Date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

private final class StubActionsWorkflowListing: ActionsWorkflowListing, @unchecked Sendable {
    let workflows: [ActionsWorkflowItem]
    let error: (any Error)?

    init(
        workflows: [ActionsWorkflowItem] = [],
        error: (any Error)? = nil
    ) {
        self.workflows = workflows
        self.error = error
    }

    func listWorkflows(repository _: ObservedRepository) async throws -> [ActionsWorkflowItem] {
        if let error {
            throw error
        }

        return workflows
    }
}

private final class StubActionsWorkflowJobListing: ActionsWorkflowJobListing, @unchecked Sendable {
    let jobNames: [String]
    let error: (any Error)?

    init(
        jobNames: [String] = [],
        error: (any Error)? = nil
    ) {
        self.jobNames = jobNames
        self.error = error
    }

    func listJobNames(
        repository _: ObservedRepository,
        workflow _: ActionsWorkflowItem
    ) async throws -> [String] {
        if let error {
            throw error
        }

        return jobNames
    }
}

private actor StubActionsInsightsLoading: ActionsInsightsLoading {
    struct Request: Sendable {
        let repository: ObservedRepository
        let workflow: ActionsWorkflowItem
        let jobName: String?
        let period: ActionsInsightsPeriod
        let now: Date
    }

    let dashboard: ActionsInsightsDashboard
    private(set) var lastRequest: Request?

    init(dashboard: ActionsInsightsDashboard) {
        self.dashboard = dashboard
    }

    func loadInsights(
        repository: ObservedRepository,
        workflow: ActionsWorkflowItem,
        jobName: String?,
        period: ActionsInsightsPeriod,
        now: Date
    ) async throws -> ActionsInsightsDashboard {
        lastRequest = Request(
            repository: repository,
            workflow: workflow,
            jobName: jobName,
            period: period,
            now: now
        )
        return dashboard
    }
}
