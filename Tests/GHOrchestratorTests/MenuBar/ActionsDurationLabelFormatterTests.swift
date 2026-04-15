import Foundation
import GHOrchestratorCore
import XCTest
@testable import GHOrchestrator

final class ActionsDurationLabelFormatterTests: XCTestCase {
    private let formatter = ActionsDurationLabelFormatter()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testJobDurationTextFormatsQueuedRunningAndCompletedJobs() {
        XCTAssertEqual(
            formatter.jobDurationText(
                for: ActionJobItem(
                    id: 1,
                    name: "Queued",
                    status: "queued",
                    createdAt: now.addingTimeInterval(-300)
                ),
                now: now
            ),
            "queued for 5m"
        )

        XCTAssertEqual(
            formatter.jobDurationText(
                for: ActionJobItem(
                    id: 2,
                    name: "Running",
                    status: "in_progress",
                    createdAt: now.addingTimeInterval(-360),
                    startedAt: now.addingTimeInterval(-120)
                ),
                now: now
            ),
            "running for 2m"
        )

        XCTAssertEqual(
            formatter.jobDurationText(
                for: ActionJobItem(
                    id: 3,
                    name: "Completed",
                    status: "completed",
                    startedAt: now.addingTimeInterval(-180),
                    completedAt: now.addingTimeInterval(-60)
                ),
                now: now
            ),
            "completed in 2m"
        )
    }

    func testWorkflowDurationTextAggregatesJobTimestamps() {
        let workflowRun = WorkflowRunItem(
            id: 10,
            name: "CI",
            status: "completed",
            conclusion: "success",
            jobs: [
                ActionJobItem(
                    id: 101,
                    name: "Build",
                    status: "completed",
                    startedAt: now.addingTimeInterval(-360),
                    completedAt: now.addingTimeInterval(-240)
                ),
                ActionJobItem(
                    id: 102,
                    name: "Test",
                    status: "completed",
                    startedAt: now.addingTimeInterval(-300),
                    completedAt: now.addingTimeInterval(-60)
                )
            ]
        )

        XCTAssertEqual(
            formatter.workflowDurationText(for: workflowRun, now: now),
            "completed in 5m"
        )
    }

    func testWorkflowDurationTextUsesCreatedAtForQueuedWorkflows() {
        let workflowRun = WorkflowRunItem(
            id: 11,
            name: "CI",
            status: "queued",
            jobs: [
                ActionJobItem(
                    id: 201,
                    name: "Build",
                    status: "queued",
                    createdAt: now.addingTimeInterval(-90)
                )
            ]
        )

        XCTAssertEqual(
            formatter.workflowDurationText(for: workflowRun, now: now),
            "queued for 1m"
        )
    }

    func testRunningWorkflowDurationPrefersStartedJobsOverQueuedJobs() {
        let workflowRun = WorkflowRunItem(
            id: 12,
            name: "CI",
            status: "in_progress",
            jobs: [
                ActionJobItem(
                    id: 301,
                    name: "Queued",
                    status: "queued",
                    createdAt: now.addingTimeInterval(-600)
                ),
                ActionJobItem(
                    id: 302,
                    name: "Running",
                    status: "in_progress",
                    createdAt: now.addingTimeInterval(-540),
                    startedAt: now.addingTimeInterval(-180)
                )
            ]
        )

        XCTAssertEqual(
            formatter.workflowDurationText(for: workflowRun, now: now),
            "running for 3m"
        )
    }

    func testDurationTextIsNilWhenRelevantTimestampsAreUnavailable() {
        XCTAssertNil(
            formatter.jobDurationText(
                for: ActionJobItem(id: 1, name: "Queued", status: "queued"),
                now: now
            )
        )

        XCTAssertNil(
            formatter.workflowDurationText(
                for: WorkflowRunItem(id: 2, name: "CI", status: "completed"),
                now: now
            )
        )
    }
}
