import XCTest
@testable import GHOrchestratorCore

final class AppSettingsTests: XCTestCase {
    func testLegacyAllCategoryMigratesWithoutLosingOtherPreferences() throws {
        let data = Data(#"{"dashboardPullRequestScope":"all","dashboardFocusedRepositoryID":"Outside/Repo","pullRequestSortOrder":"createdOldestFirst","repositorySortOrder":"teamDescending"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(settings.dashboardPullRequestScope, .reviewRequested)
        XCTAssertEqual(settings.dashboardFocusedRepositoryID, "outside/repo")
        XCTAssertEqual(settings.pullRequestSortOrder, .createdOldestFirst)
        XCTAssertEqual(settings.repositorySortOrder, .teamDescending)
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored, settings)
    }

    func testPRDestinationDefaultsForLegacySettingsAndRoundTrips() throws {
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).pullRequestOpenDestination, .browser)
        for destination in PullRequestOpenDestination.allCases {
            let data = try JSONEncoder().encode(AppSettings(pullRequestOpenDestination: destination))
            XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data).pullRequestOpenDestination, destination)
        }
    }

    func testSortPreferenceRoundTripsAndLegacySettingsDefaultToTitle() throws {
        let decoder = JSONDecoder()
        let legacySettings = try decoder.decode(AppSettings.self, from: Data(#"{"pullRequestSortOrder":"createdOldestFirst","repositorySortOrder":"teamDescending","pollingIntervalSeconds":120}"#.utf8))
        XCTAssertEqual(legacySettings.dashboardPullRequestScope, .mine)
        XCTAssertNil(legacySettings.dashboardFocusedRepositoryID)
        XCTAssertEqual(legacySettings.pullRequestSortOrder, .createdOldestFirst)
        XCTAssertEqual(legacySettings.repositorySortOrder, .teamDescending)
        XCTAssertEqual(legacySettings.pollingIntervalSeconds, 120)
        XCTAssertEqual(try decoder.decode(AppSettings.self, from: Data("{}".utf8)).pullRequestSortOrder, .title)
        XCTAssertEqual(try decoder.decode(AppSettings.self, from: Data("{}".utf8)).repositorySortOrder, .lastModifiedNewestFirst)
        for order in RepositorySortOrder.allCases {
            let data = try JSONEncoder().encode(AppSettings(repositorySortOrder: order))
            XCTAssertEqual(try decoder.decode(AppSettings.self, from: data).repositorySortOrder, order)
        }
        for order in PullRequestSortOrder.allCases {
            let data = try JSONEncoder().encode(AppSettings(pullRequestSortOrder: order))
            XCTAssertEqual(try decoder.decode(AppSettings.self, from: data).pullRequestSortOrder, order)
        }
    }

    func testPollingIntervalUsesDefaultWhenNotProvided() {
        let settings = AppSettings()

        XCTAssertEqual(settings.pollingIntervalSeconds, AppSettings.defaultPollingIntervalSeconds)
        XCTAssertEqual(settings.hideDockIcon, AppSettings.defaultHideDockIcon)
        XCTAssertEqual(settings.startAtLogin, AppSettings.defaultStartAtLogin)
        XCTAssertEqual(settings.automaticallyCheckForUpdates, AppSettings.defaultAutomaticallyCheckForUpdates)
        XCTAssertEqual(settings.graphQLSearchResultLimit, 10)
        XCTAssertEqual(settings.graphQLReviewThreadLimit, 10)
        XCTAssertEqual(settings.graphQLReviewThreadCommentLimit, 5)
        XCTAssertEqual(settings.graphQLCheckContextLimit, 15)
        XCTAssertEqual(settings.actionsInsightsSelection, AppSettings.defaultActionsInsightsSelection)
        XCTAssertTrue(settings.repositoryNotificationSettings.isEmpty)
    }

    func testPollingIntervalIsClampedToAllowedRange() {
        XCTAssertEqual(AppSettings(pollingIntervalSeconds: 1).pollingIntervalSeconds, 15)
        XCTAssertEqual(AppSettings(pollingIntervalSeconds: 60).pollingIntervalSeconds, 60)
        XCTAssertEqual(AppSettings(pollingIntervalSeconds: 9_999).pollingIntervalSeconds, 900)
    }

    func testObservedRepositoriesAreDeduplicatedByNormalizedNameKeepingFirstOccurrence() {
        let settings = AppSettings(
            observedRepositories: [
                ObservedRepository(owner: "openai", name: "codex"),
                ObservedRepository(owner: "OPENAI", name: "CODEX"),
                ObservedRepository(owner: "swiftlang", name: "swift")
            ]
        )

        XCTAssertEqual(
            settings.observedRepositories.map(\.fullName),
            ["openai/codex", "swiftlang/swift"]
        )
    }

    func testHideDockIconPreferenceRoundTripsThroughInitializer() {
        let settings = AppSettings(hideDockIcon: true)

        XCTAssertTrue(settings.hideDockIcon)
    }

    func testStartAtLoginPreferenceRoundTripsThroughInitializer() {
        let settings = AppSettings(startAtLogin: true)

        XCTAssertTrue(settings.startAtLogin)
    }

    func testAutomaticUpdateCheckPreferenceRoundTripsThroughInitializer() {
        let settings = AppSettings(automaticallyCheckForUpdates: false)

        XCTAssertFalse(settings.automaticallyCheckForUpdates)
    }

    func testGraphQLDashboardLimitsAreClampedToAllowedRanges() {
        let settings = AppSettings(
            graphQLSearchResultLimit: 0,
            graphQLReviewThreadLimit: 101,
            graphQLReviewThreadCommentLimit: 99,
            graphQLCheckContextLimit: 0
        )

        XCTAssertEqual(settings.graphQLSearchResultLimit, 1)
        XCTAssertEqual(settings.graphQLReviewThreadLimit, 100)
        XCTAssertEqual(settings.graphQLReviewThreadCommentLimit, 20)
        XCTAssertEqual(settings.graphQLCheckContextLimit, 1)
    }

    func testActionsInsightsSelectionRoundTripsThroughInitializer() {
        let selection = ActionsInsightsSelection(
            repositoryID: "openai/codex",
            workflowID: 42,
            workflowName: "CI",
            jobName: "Tests",
            period: .last90Days
        )

        let settings = AppSettings(actionsInsightsSelection: selection)

        XCTAssertEqual(settings.actionsInsightsSelection, selection)
    }

    func testGraphQLDashboardLimitsUseDefaultsWhenMissingFromStoredSettings() throws {
        let data = Data(
            """
            {
              "observedRepositories": [],
              "pollingIntervalSeconds": 60,
              "hideDockIcon": false
            }
            """.utf8
        )

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(settings.graphQLSearchResultLimit, AppSettings.defaultGraphQLSearchResultLimit)
        XCTAssertEqual(settings.graphQLReviewThreadLimit, AppSettings.defaultGraphQLReviewThreadLimit)
        XCTAssertEqual(settings.graphQLReviewThreadCommentLimit, AppSettings.defaultGraphQLReviewThreadCommentLimit)
        XCTAssertEqual(settings.graphQLCheckContextLimit, AppSettings.defaultGraphQLCheckContextLimit)
        XCTAssertEqual(settings.actionsInsightsSelection, AppSettings.defaultActionsInsightsSelection)
        XCTAssertEqual(settings.startAtLogin, AppSettings.defaultStartAtLogin)
        XCTAssertEqual(settings.automaticallyCheckForUpdates, AppSettings.defaultAutomaticallyCheckForUpdates)
        XCTAssertTrue(settings.repositoryNotificationSettings.isEmpty)
    }

    func testNotificationSettingsAreNormalizedDeduplicatedAndScopedToObservedRepositories() {
        let settings = AppSettings(
            observedRepositories: [
                ObservedRepository(owner: "OpenAI", name: "Codex"),
                ObservedRepository(owner: "swiftlang", name: "swift")
            ],
            repositoryNotificationSettings: [
                RepositoryNotificationSettings(
                    repositoryID: " OPENAI/CODEX ",
                    enabled: true,
                    enabledTriggers: [.approval],
                    workflowNameFilters: [" CI ", "ci", "Release"],
                    workflowJobNameFiltersByWorkflowName: [
                        " CI ": [" Build ", "build", "Test"],
                        " ": ["ignored"],
                        "Release": []
                    ]
                ),
                RepositoryNotificationSettings(
                    repositoryID: "openai/codex",
                    enabled: false
                ),
                RepositoryNotificationSettings(
                    repositoryID: "missing/repo",
                    enabled: true
                )
            ]
        )

        XCTAssertEqual(settings.repositoryNotificationSettings.count, 1)
        XCTAssertEqual(settings.repositoryNotificationSettings[0].repositoryID, "openai/codex")
        XCTAssertTrue(settings.repositoryNotificationSettings[0].enabled)
        XCTAssertEqual(settings.repositoryNotificationSettings[0].enabledTriggers, [.approval])
        XCTAssertEqual(settings.repositoryNotificationSettings[0].workflowNameFilters, ["ci", "release"])
        XCTAssertEqual(settings.repositoryNotificationSettings[0].workflowJobNameFiltersByWorkflowName, ["ci": ["build", "test"]])
    }

    func testNotificationSettingsReconcileAfterRepositoryRemoval() {
        var settings = AppSettings(
            observedRepositories: [
                ObservedRepository(owner: "openai", name: "codex"),
                ObservedRepository(owner: "swiftlang", name: "swift")
            ],
            repositoryNotificationSettings: [
                RepositoryNotificationSettings(repositoryID: "openai/codex", enabled: true),
                RepositoryNotificationSettings(repositoryID: "swiftlang/swift", enabled: true)
            ]
        )

        settings.observedRepositories = [
            ObservedRepository(owner: "swiftlang", name: "swift")
        ]
        settings.reconcileNotificationSettingsWithObservedRepositories()

        XCTAssertEqual(settings.repositoryNotificationSettings.map(\.repositoryID), ["swiftlang/swift"])
    }
}
