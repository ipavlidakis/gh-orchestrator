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
        let transport = RoutingGitHubHTTPTransport { request in
            switch request.url?.path {
            case "/repos/cli/cli/actions/runs/101/jobs": return firstJobsJSON
            case "/repos/cli/cli/actions/runs/102/jobs": return secondJobsJSON
            default: return workflowRunsJSON
            }
        }
        let service = ActionsInsightsService(client: client(transport: transport))

        let dashboard = try await service.loadInsights(
            repository: ObservedRepository(owner: "cli", name: "cli"),
            workflow: ActionsWorkflowItem(id: 10, name: "CI", path: ".github/workflows/ci.yml", state: "active"),
            jobName: "Build",
            period: .last30Days,
            now: try XCTUnwrap(parseISO8601Date("2026-04-15T12:00:00Z"))
        )
        let requests = await transport.recordedRequests()

        XCTAssertEqual(requests.first?.url?.path, "/repos/cli/cli/actions/workflows/10/runs")
        XCTAssertEqual(
            Set(requests.compactMap(\.url?.path)),
            [
                "/repos/cli/cli/actions/workflows/10/runs",
                "/repos/cli/cli/actions/runs/101/jobs",
                "/repos/cli/cli/actions/runs/102/jobs"
            ]
        )
        XCTAssertEqual(dashboard.summary.totalCount, 2)
        XCTAssertEqual(dashboard.summary.successCount, 1)
        XCTAssertEqual(dashboard.summary.failureCount, 1)
        XCTAssertEqual(dashboard.summary.averageDurationSeconds, 750)
    }

    func testWorkflowRunPagesAfterTheFirstLoadAndAreAllAggregated() async throws {
        let transport = RoutingGitHubHTTPTransport { request in
            let page = request.url?.query?.contains("page=2") == true ? 2 : 1
            let ids = page == 1 ? Array(1...100) : Array(101...150)
            return Self.workflowRunsPayload(total: 150, ids: ids)
        }
        let service = ActionsInsightsService(client: client(transport: transport))

        let dashboard = try await service.loadInsights(
            repository: ObservedRepository(owner: "cli", name: "cli"),
            workflow: ActionsWorkflowItem(id: 10, name: "CI", path: ".github/workflows/ci.yml", state: "active"),
            jobName: nil,
            period: .last30Days,
            now: try XCTUnwrap(parseISO8601Date("2026-04-15T12:00:00Z"))
        )
        let requests = await transport.recordedRequests()

        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(dashboard.summary.totalCount, 150)
        XCTAssertFalse(dashboard.isWorkflowRunResultCapped)
    }

    func testJobsForCompletedRunsAreCachedAcrossLoads() async throws {
        let transport = RoutingGitHubHTTPTransport { request in
            if request.url?.path.hasSuffix("/jobs") == true {
                return Self.jobsPayload(runID: 1)
            }
            return Self.workflowRunsPayload(total: 1, ids: [1])
        }
        let service = ActionsInsightsService(client: client(transport: transport))
        let repository = ObservedRepository(owner: "cli", name: "cli")
        let workflow = ActionsWorkflowItem(id: 10, name: "CI", path: ".github/workflows/ci.yml", state: "active")
        let now = try XCTUnwrap(parseISO8601Date("2026-04-15T12:00:00Z"))

        let first = try await service.loadInsights(repository: repository, workflow: workflow, jobName: "Build", period: .last30Days, now: now)
        let second = try await service.loadInsights(repository: repository, workflow: workflow, jobName: "Build", period: .last30Days, now: now)
        let jobRequests = await transport.recordedRequests().filter { $0.url?.path.hasSuffix("/jobs") == true }

        XCTAssertEqual(jobRequests.count, 1)
        XCTAssertEqual(first, second)
        XCTAssertEqual(second.summary.totalCount, 1)
    }

    func testJobInsightsBatchRunsIntoFewGraphQLRequests() async throws {
        let runCount = 120
        let transport = RoutingGitHubHTTPTransport { request in
            if request.url?.path == "/graphql" {
                let body = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                let ids = (body["variables"] as! [String: Any])["ids"] as! [String]
                let nodes = ids.map { _ in
                    """
                    {"checkSuite": {"checkRuns": {"totalCount": 2, "nodes": [
                      {"name": "Build", "status": "COMPLETED", "conclusion": "SUCCESS",
                       "startedAt": "2026-04-01T10:00:00Z", "completedAt": "2026-04-01T10:10:00Z"},
                      {"name": "Lint", "status": "COMPLETED", "conclusion": "FAILURE",
                       "startedAt": "2026-04-01T10:00:00Z", "completedAt": "2026-04-01T10:01:00Z"}]}}}
                    """
                }.joined(separator: ",")
                return Data("{\"data\": {\"nodes\": [\(nodes)]}}".utf8)
            }
            let page = request.url?.query?.contains("page=2") == true ? 2 : 1
            let ids = page == 1 ? Array(1...100) : Array(101...runCount)
            return Self.workflowRunsPayload(total: runCount, ids: ids, includeNodeIDs: true)
        }
        let service = ActionsInsightsService(client: client(transport: transport))
        let repository = ObservedRepository(owner: "cli", name: "cli")
        let workflow = ActionsWorkflowItem(id: 10, name: "CI", path: ".github/workflows/ci.yml", state: "active")
        let now = try XCTUnwrap(parseISO8601Date("2026-04-15T12:00:00Z"))

        let dashboard = try await service.loadInsights(repository: repository, workflow: workflow, jobName: "build", period: .last30Days, now: now)
        let again = try await service.loadInsights(repository: repository, workflow: workflow, jobName: "Build", period: .last30Days, now: now)
        let requests = await transport.recordedRequests()
        let graphQLRequests = requests.filter { $0.url?.path == "/graphql" }
        let jobRESTRequests = requests.filter { $0.url?.path.hasSuffix("/jobs") == true }

        XCTAssertEqual(graphQLRequests.count, 3) // 120 runs / 50 per batch, then fully cached
        XCTAssertEqual(jobRESTRequests.count, 0)
        XCTAssertEqual(dashboard.summary.totalCount, runCount)
        XCTAssertEqual(dashboard.summary.successCount, runCount)
        XCTAssertEqual(dashboard.summary.averageDurationSeconds, 600)
        XCTAssertEqual(dashboard, again)
    }

    private static func workflowRunsPayload(total: Int, ids: [Int], includeNodeIDs: Bool = false) -> Data {
        let runs = ids.map { id in
            """
            {"id": \(id), \(includeNodeIDs ? "\"node_id\": \"WFR_\(id)\"," : "") "name": "CI", "status": "completed", "conclusion": "success",
             "html_url": "https://github.com/cli/cli/actions/runs/\(id)",
             "created_at": "2026-04-01T10:00:00Z", "run_started_at": "2026-04-01T10:00:00Z",
             "updated_at": "2026-04-01T10:10:00Z"}
            """
        }.joined(separator: ",")
        return Data("{\"total_count\": \(total), \"workflow_runs\": [\(runs)]}".utf8)
    }

    private static func jobsPayload(runID: Int) -> Data {
        Data(
            """
            {"total_count": 1, "jobs": [{"id": 9, "name": "Build",
             "html_url": "https://github.com/cli/cli/actions/runs/\(runID)/job/9",
             "status": "completed", "conclusion": "success",
             "created_at": "2026-04-01T10:01:00Z", "started_at": "2026-04-01T10:02:00Z",
             "completed_at": "2026-04-01T10:07:00Z", "steps": []}]}
            """.utf8
        )
    }

    private func client(transport: any GitHubHTTPTransport) -> URLSessionGitHubAPIClient {
        URLSessionGitHubAPIClient(
            transport: transport,
            credentialStore: StubGitHubCredentialStore()
        )
    }
}
