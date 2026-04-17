import Foundation
import XCTest
@testable import GHOrchestrator
import GHOrchestratorCore

final class LocalNotificationContentFormatterTests: XCTestCase {
    func testPullRequestCreatedNotificationIncludesRepositoryTitleAndAuthorBody() {
        let notificationEvent = RepositoryNotificationEvent(
            trigger: .pullRequestCreated,
            repository: ObservedRepository(owner: "openai", name: "codex"),
            pullRequestNumber: 7,
            pullRequestTitle: "Add debug previews",
            pullRequestURL: URL(string: "https://github.com/openai/codex/pull/7")!,
            targetURL: URL(string: "https://github.com/openai/codex/pull/7")!,
            authorLogin: "octocat"
        )

        XCTAssertEqual(LocalNotificationContentFormatter.title(for: notificationEvent), "openai/codex")
        XCTAssertEqual(
            LocalNotificationContentFormatter.body(for: notificationEvent),
            "New PR #7: Add debug previews\nOpened by octocat"
        )
    }

    func testWorkflowJobSuccessNotificationUsesRepositoryTitleAndSuccessBody() {
        let notificationEvent = workflowJobEvent(
            jobName: "unit-tests",
            conclusion: "success"
        )

        XCTAssertEqual(LocalNotificationContentFormatter.title(for: notificationEvent), "codex")
        XCTAssertEqual(
            LocalNotificationContentFormatter.body(for: notificationEvent),
            "✅ unit-tests succeed - Add notifications"
        )
    }

    func testWorkflowJobFailureNotificationUsesRepositoryTitleAndFailureBody() {
        let notificationEvent = workflowJobEvent(
            jobName: "lint",
            conclusion: "failure"
        )

        XCTAssertEqual(LocalNotificationContentFormatter.title(for: notificationEvent), "codex")
        XCTAssertEqual(
            LocalNotificationContentFormatter.body(for: notificationEvent),
            "❌ lint fail - Add notifications"
        )
    }

    private func workflowJobEvent(
        jobName: String,
        conclusion: String
    ) -> RepositoryNotificationEvent {
        let repository = ObservedRepository(owner: "openai", name: "codex")
        let pullRequestURL = URL(string: "https://github.com/openai/codex/pull/1")!
        let jobURL = URL(string: "https://github.com/openai/codex/actions/runs/1/job/2")!

        return RepositoryNotificationEvent(
            trigger: .workflowJobCompleted,
            repository: repository,
            pullRequestNumber: 1,
            pullRequestTitle: "Add notifications",
            pullRequestURL: pullRequestURL,
            targetURL: jobURL,
            workflowRunID: 1,
            workflowName: "CI",
            workflowConclusion: conclusion,
            workflowJobID: 2,
            workflowJobName: jobName,
            workflowJobConclusion: conclusion
        )
    }
}
