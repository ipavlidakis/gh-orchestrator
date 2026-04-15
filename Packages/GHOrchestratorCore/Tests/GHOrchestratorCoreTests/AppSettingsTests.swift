import XCTest
@testable import GHOrchestratorCore

final class AppSettingsTests: XCTestCase {
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
