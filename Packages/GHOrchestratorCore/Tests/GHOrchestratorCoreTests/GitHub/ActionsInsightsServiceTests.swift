import Foundation
import XCTest
@testable import GHOrchestratorCore

final class ActionsInsightsServiceTests: XCTestCase {
    func testPreviousMonthUsesPreviousCalendarMonth() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try XCTUnwrap(parseISO8601Date("2026-04-15T12:00:00Z"))

        let interval = ActionsInsightsPeriod.previousMonth.dateInterval(
            containing: now,
            calendar: calendar
        )

        XCTAssertEqual(interval.start, try XCTUnwrap(parseISO8601Date("2026-03-01T00:00:00Z")))
        XCTAssertEqual(interval.end, try XCTUnwrap(parseISO8601Date("2026-04-01T00:00:00Z")))
    }

    func testWorkflowInsightsAggregateCompletedRuns() async throws {
        let workflowRunsJSON = Data(
            """
            {
              "total_count": 3,
              "workflow_runs": [
                {
                  "id": 101,
                  "name": "CI",
                  "status": "completed",
                  "conclusion": "success",
                  "html_url": "https://github.com/cli/cli/actions/runs/101",
                  "created_at": "2026-04-01T10:00:00Z",
                  "run_started_at": "2026-04-01T10:00:00Z",
                  "updated_at": "2026-04-01T10:10:00Z"
                },
                {
                  "id": 102,
                  "name": "CI",
                  "status": "completed",
                  "conclusion": "failure",
                  "html_url": "https://github.com/cli/cli/actions/runs/102",
                  "created_at": "2026-04-02T11:00:00Z",
                  "run_started_at": "2026-04-02T11:00:00Z",
                  "updated_at": "2026-04-02T11:20:00Z"
                },
                {
                  "id": 103,
                  "name": "CI",
                  "status": "queued",
                  "conclusion": null,
                  "html_url": "https://github.com/cli/cli/actions/runs/103",
                  "created_at": "2026-04-03T12:00:00Z",
                  "run_started_at": null,
                  "updated_at": "2026-04-03T12:00:00Z"
                }
              ]
            }
            """.utf8
        )
        let transport = StubGitHubHTTPTransport(
            results: [
                .success(
                    data: workflowRunsJSON,
                    response: makeHTTPResponse(url: "https://api.github.com/repos/cli/cli/actions/workflows/10/runs", statusCode: 200)
                )
            ]
        )
        let service = ActionsInsightsService(client: client(transport: transport))

        let dashboard = try await service.loadInsights(
            repository: ObservedRepository(owner: "cli", name: "cli"),
            workflow: ActionsWorkflowItem(id: 10, name: "CI", path: ".github/workflows/ci.yml", state: "active"),
            jobName: nil,
            period: .last30Days,
            now: try XCTUnwrap(parseISO8601Date("2026-04-15T12:00:00Z"))
        )
        let requests = await transport.recordedRequests()

        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url?.path, "/repos/cli/cli/actions/workflows/10/runs")
        XCTAssertEqual(requests[0].url?.query?.contains("per_page=100"), true)
        XCTAssertEqual(requests[0].url?.query?.contains("created="), true)
        XCTAssertEqual(dashboard.summary.totalCount, 2)
        XCTAssertEqual(dashboard.summary.successCount, 1)
        XCTAssertEqual(dashboard.summary.failureCount, 1)
        XCTAssertEqual(dashboard.summary.averageDurationSeconds, 900)
        XCTAssertEqual(dashboard.dataPoints.count, 2)
    }

    func testJobInsightsUseSelectedJobTimestamps() async throws {
        let workflowRunsJSON = Data(
            """
            {
              "total_count": 2,
              "workflow_runs": [
                {
                  "id": 101,
                  "name": "CI",
                  "status": "completed",
                  "conclusion": "success",
                  "html_url": "https://github.com/cli/cli/actions/runs/101",
                  "created_at": "2026-04-01T10:00:00Z",
                  "run_started_at": "2026-04-01T10:00:00Z",
                  "updated_at": "2026-04-01T10:10:00Z"
                },
                {
                  "id": 102,
                  "name": "CI",
                  "status": "completed",
                  "conclusion": "failure",
                  "html_url": "https://github.com/cli/cli/actions/runs/102",
                  "created_at": "2026-04-02T11:00:00Z",
                  "run_started_at": "2026-04-02T11:00:00Z",
                  "updated_at": "2026-04-02T11:20:00Z"
                }
              ]
            }
            """.utf8
        )
        let firstJobsJSON = Data(
            """
            {
              "total_count": 2,
              "jobs": [
                {
                  "id": 201,
                  "name": "Build",
                  "html_url": "https://github.com/cli/cli/actions/runs/101/job/201",
                  "status": "completed",
                  "conclusion": "success",
                  "created_at": "2026-04-01T10:01:00Z",
                  "started_at": "2026-04-01T10:02:00Z",
                  "completed_at": "2026-04-01T10:07:00Z",
                  "steps": []
                },
                {
                  "id": 202,
                  "name": "Test",
                  "html_url": "https://github.com/cli/cli/actions/runs/101/job/202",
                  "status": "completed",
                  "conclusion": "success",
                  "created_at": "2026-04-01T10:01:00Z",
                  "started_at": "2026-04-01T10:02:00Z",
                  "completed_at": "2026-04-01T10:08:00Z",
                  "steps": []
                }
              ]
            }
            """.utf8
        )
        let secondJobsJSON = Data(
            """
            {
              "total_count": 1,
              "jobs": [
                {
                  "id": 203,
                  "name": "Build",
                  "html_url": "https://github.com/cli/cli/actions/runs/102/job/203",
                  "status": "completed",
                  "conclusion": "failure",
                  "created_at": "2026-04-02T11:01:00Z",
                  "started_at": "2026-04-02T11:03:00Z",
                  "completed_at": "2026-04-02T11:23:00Z",
                  "steps": []
                }
              ]
            }
            """.utf8
        )
        let transport = StubGitHubHTTPTransport(
            results: [
                .success(
                    data: workflowRunsJSON,
                    response: makeHTTPResponse(url: "https://api.github.com/repos/cli/cli/actions/workflows/10/runs", statusCode: 200)
                ),
                .success(
                    data: firstJobsJSON,
                    response: makeHTTPResponse(url: "https://api.github.com/repos/cli/cli/actions/runs/101/jobs", statusCode: 200)
                ),
                .success(
                    data: secondJobsJSON,
                    response: makeHTTPResponse(url: "https://api.github.com/repos/cli/cli/actions/runs/102/jobs", statusCode: 200)
                )
            ]
        )
        let service = ActionsInsightsService(client: client(transport: transport))

        let dashboard = try await service.loadInsights(
            repository: ObservedRepository(owner: "cli", name: "cli"),
            workflow: ActionsWorkflowItem(id: 10, name: "CI", path: ".github/workflows/ci.yml", state: "active"),
            jobName: "Build",
            period: .last30Days,
            now: try XCTUnwrap(parseISO8601Date("2026-04-15T12:00:00Z"))
        )
        let requests = await transport.recordedRequests()

        XCTAssertEqual(requests.map(\.url?.path), [
            "/repos/cli/cli/actions/workflows/10/runs",
            "/repos/cli/cli/actions/runs/101/jobs",
            "/repos/cli/cli/actions/runs/102/jobs"
        ])
        XCTAssertEqual(dashboard.summary.totalCount, 2)
        XCTAssertEqual(dashboard.summary.successCount, 1)
        XCTAssertEqual(dashboard.summary.failureCount, 1)
        XCTAssertEqual(dashboard.summary.averageDurationSeconds, 750)
    }

    private func client(transport: StubGitHubHTTPTransport) -> URLSessionGitHubAPIClient {
        URLSessionGitHubAPIClient(
            transport: transport,
            credentialStore: StubGitHubCredentialStore()
        )
    }
}
