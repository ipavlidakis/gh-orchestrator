import Foundation
import XCTest
@testable import GHOrchestratorCore

final class ActionsJobsEnrichmentServiceTests: XCTestCase {
    func testBuildPullRequestItemsMapsCompletedJobsWithStepLinks() async throws {
        let repository = ObservedRepository(owner: "cli", name: "cli")
        let snapshot = PullRequestSnapshotItem(
            repository: repository,
            number: 100,
            title: "Add workflow details",
            url: URL(string: "https://github.com/cli/cli/pull/100")!,
            isDraft: false,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            reviewStatus: .approved,
            unresolvedReviewThreadCount: 0,
            unresolvedReviewComments: [],
            checkRollupState: .passing,
            checkRuns: [
                CheckRunSnapshot(
                    name: "lint",
                    status: "COMPLETED",
                    conclusion: "SUCCESS",
                    detailsURL: URL(string: "https://github.com/cli/cli/actions/runs/321/job/654"),
                    appName: "GitHub Actions",
                    appSlug: "github-actions",
                    workflowRun: WorkflowRunReferenceSnapshot(
                        id: 321,
                        url: URL(string: "https://github.com/cli/cli/actions/runs/321"),
                        workflowName: "Lint"
                    )
                )
            ],
            statusContexts: []
        )

        let service = makeActionsService(
            results: [
                .success(
                    data: fixtureData(named: "completed_jobs", subdirectory: "ActionsJobs"),
                    response: makeHTTPResponse(url: "https://api.github.com/repos/cli/cli/actions/runs/321/jobs", statusCode: 200)
                )
            ]
        )
        let items = try await service.buildPullRequestItems(
            from: [RepositoryPullRequestSnapshot(repository: repository, pullRequests: [snapshot])]
        )

        let workflowRun = try XCTUnwrap(items.first?.workflowRuns.first)
        let job = try XCTUnwrap(workflowRun.jobs.first)
        let step = try XCTUnwrap(job.steps.first)

        XCTAssertEqual(workflowRun.name, "Lint")
        XCTAssertEqual(job.name, "lint")
        XCTAssertEqual(step.detailsURL?.absoluteString, "https://github.com/cli/cli/actions/runs/321/job/654#step:1:1")
        XCTAssertEqual(items.first?.externalChecks, [])
    }

    func testBuildPullRequestItemsMapsQueuedJobsWithoutSteps() async throws {
        let repository = ObservedRepository(owner: "cli", name: "cli")
        let snapshot = PullRequestSnapshotItem(
            repository: repository,
            number: 101,
            title: "Queue workflow",
            url: URL(string: "https://github.com/cli/cli/pull/101")!,
            isDraft: false,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            reviewStatus: .reviewRequired,
            unresolvedReviewThreadCount: 1,
            unresolvedReviewComments: [],
            checkRollupState: .pending,
            checkRuns: [
                CheckRunSnapshot(
                    name: "unit-tests",
                    status: "QUEUED",
                    conclusion: nil,
                    detailsURL: URL(string: "https://github.com/cli/cli/actions/runs/555/job/777"),
                    appName: "GitHub Actions",
                    appSlug: "github-actions",
                    workflowRun: WorkflowRunReferenceSnapshot(
                        id: 555,
                        url: URL(string: "https://github.com/cli/cli/actions/runs/555"),
                        workflowName: "Unit Tests"
                    )
                )
            ],
            statusContexts: []
        )

        let service = makeActionsService(
            results: [
                .success(
                    data: fixtureData(named: "queued_jobs", subdirectory: "ActionsJobs"),
                    response: makeHTTPResponse(url: "https://api.github.com/repos/cli/cli/actions/runs/555/jobs", statusCode: 200)
                )
            ]
        )
        let items = try await service.buildPullRequestItems(
            from: [RepositoryPullRequestSnapshot(repository: repository, pullRequests: [snapshot])]
        )

        let job = try XCTUnwrap(items.first?.workflowRuns.first?.jobs.first)
        XCTAssertEqual(job.status, "queued")
        XCTAssertTrue(job.steps.isEmpty)
    }

    func testBuildPullRequestItemsKeepsMixedExternalChecksAlongsideActionsRuns() async throws {
        let repository = ObservedRepository(owner: "cli", name: "cli")
        let snapshot = PullRequestSnapshotItem(
            repository: repository,
            number: 102,
            title: "Mixed checks",
            url: URL(string: "https://github.com/cli/cli/pull/102")!,
            isDraft: false,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_200),
            reviewStatus: .approved,
            unresolvedReviewThreadCount: 0,
            unresolvedReviewComments: [],
            checkRollupState: .passing,
            checkRuns: [
                CheckRunSnapshot(
                    name: "lint",
                    status: "COMPLETED",
                    conclusion: "SUCCESS",
                    detailsURL: URL(string: "https://github.com/cli/cli/actions/runs/321/job/654"),
                    appName: "GitHub Actions",
                    appSlug: "github-actions",
                    workflowRun: WorkflowRunReferenceSnapshot(
                        id: 321,
                        url: URL(string: "https://github.com/cli/cli/actions/runs/321"),
                        workflowName: "Lint"
                    )
                ),
                CheckRunSnapshot(
                    name: "third-party-scan",
                    status: "COMPLETED",
                    conclusion: "SUCCESS",
                    detailsURL: URL(string: "https://checks.example.com/scan/42"),
                    appName: "Example CI",
                    appSlug: "example-ci",
                    workflowRun: nil
                )
            ],
            statusContexts: [
                StatusContextSnapshot(
                    context: "mergeable",
                    state: "SUCCESS",
                    targetURL: URL(string: "https://github.com/cli/cli/pull/102"),
                    description: "Merge checks passed"
                )
            ]
        )

        let service = makeActionsService(
            results: [
                .success(
                    data: fixtureData(named: "completed_jobs", subdirectory: "ActionsJobs"),
                    response: makeHTTPResponse(url: "https://api.github.com/repos/cli/cli/actions/runs/321/jobs", statusCode: 200)
                )
            ]
        )
        let items = try await service.buildPullRequestItems(
            from: [RepositoryPullRequestSnapshot(repository: repository, pullRequests: [snapshot])]
        )

        let externalChecks = try XCTUnwrap(items.first?.externalChecks)
        XCTAssertEqual(externalChecks.map(\.name), ["third-party-scan", "mergeable"])
        XCTAssertEqual(items.first?.workflowRuns.count, 1)
    }

    func testBuildPullRequestItemsFetchesWorkflowRunJobsOncePerRun() async throws {
        let repository = ObservedRepository(owner: "cli", name: "cli")
        let sharedRun = WorkflowRunReferenceSnapshot(
            id: 321,
            url: URL(string: "https://github.com/cli/cli/actions/runs/321"),
            workflowName: "Lint"
        )
        let snapshot = PullRequestSnapshotItem(
            repository: repository,
            number: 103,
            title: "Duplicate checks",
            url: URL(string: "https://github.com/cli/cli/pull/103")!,
            isDraft: false,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_300),
            reviewStatus: .approved,
            unresolvedReviewThreadCount: 0,
            unresolvedReviewComments: [],
            checkRollupState: .passing,
            checkRuns: [
                CheckRunSnapshot(
                    name: "lint-linux",
                    status: "COMPLETED",
                    conclusion: "SUCCESS",
                    detailsURL: URL(string: "https://github.com/cli/cli/actions/runs/321/job/111"),
                    appName: "GitHub Actions",
                    appSlug: "github-actions",
                    workflowRun: sharedRun
                ),
                CheckRunSnapshot(
                    name: "lint-macos",
                    status: "COMPLETED",
                    conclusion: "SUCCESS",
                    detailsURL: URL(string: "https://github.com/cli/cli/actions/runs/321/job/222"),
                    appName: "GitHub Actions",
                    appSlug: "github-actions",
                    workflowRun: sharedRun
                )
            ],
            statusContexts: []
        )

        let transport = StubGitHubHTTPTransport(
            results: [
                .success(
                    data: fixtureData(named: "completed_jobs", subdirectory: "ActionsJobs"),
                    response: makeHTTPResponse(url: "https://api.github.com/repos/cli/cli/actions/runs/321/jobs", statusCode: 200)
                )
            ]
        )
        let client = URLSessionGitHubAPIClient(
            transport: transport,
            credentialStore: StubGitHubCredentialStore()
        )
        let service = ActionsJobsEnrichmentService(client: client)

        let items = try await service.buildPullRequestItems(
            from: [RepositoryPullRequestSnapshot(repository: repository, pullRequests: [snapshot])]
        )
        let requests = await transport.recordedRequests()

        XCTAssertEqual(items.first?.workflowRuns.count, 1)
        XCTAssertEqual(requests.map { $0.url?.absoluteString }, ["https://api.github.com/repos/cli/cli/actions/runs/321/jobs"])
    }

    func testActionsStepLinkBuilderFallsBackToJobURLWhenStepNumberIsInvalid() {
        let jobURL = URL(string: "https://github.com/cli/cli/actions/runs/321/job/654")

        XCTAssertEqual(
            ActionsStepLinkBuilder.stepURL(jobURL: jobURL, stepNumber: 0),
            jobURL
        )
    }

    func testBuildPullRequestItemsFormatsGitHubAPIErrorsForDisplay() async {
        let repository = ObservedRepository(owner: "cli", name: "cli")
        let snapshot = PullRequestSnapshotItem(
            repository: repository,
            number: 104,
            title: "Rate limited workflow",
            url: URL(string: "https://github.com/cli/cli/pull/104")!,
            isDraft: false,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_400),
            reviewStatus: .approved,
            unresolvedReviewThreadCount: 0,
            unresolvedReviewComments: [],
            checkRollupState: .pending,
            checkRuns: [
                CheckRunSnapshot(
                    name: "lint",
                    status: "COMPLETED",
                    conclusion: "SUCCESS",
                    detailsURL: URL(string: "https://github.com/cli/cli/actions/runs/321/job/654"),
                    appName: "GitHub Actions",
                    appSlug: "github-actions",
                    workflowRun: WorkflowRunReferenceSnapshot(
                        id: 321,
                        url: URL(string: "https://github.com/cli/cli/actions/runs/321"),
                        workflowName: "Lint"
                    )
                )
            ],
            statusContexts: []
        )

        let service = makeActionsService(
            results: [
                .success(
                    data: Data(#"{"message":"API rate limit exceeded for user ID 472467."}"#.utf8),
                    response: makeHTTPResponse(url: "https://api.github.com/repos/cli/cli/actions/runs/321/jobs", statusCode: 403)
                )
            ]
        )

        do {
            _ = try await service.buildPullRequestItems(
                from: [RepositoryPullRequestSnapshot(repository: repository, pullRequests: [snapshot])]
            )
            XCTFail("Expected buildPullRequestItems to throw")
        } catch let error as ActionsJobsEnrichmentError {
            XCTAssertEqual(
                error.localizedDescription,
                "Failed to load Actions jobs for cli/cli: API rate limit exceeded for user ID 472467."
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private func makeActionsService(
    results: [StubGitHubHTTPTransport.Result]
) -> ActionsJobsEnrichmentService {
    let client = URLSessionGitHubAPIClient(
        transport: StubGitHubHTTPTransport(results: results),
        credentialStore: StubGitHubCredentialStore()
    )

    return ActionsJobsEnrichmentService(client: client)
}
