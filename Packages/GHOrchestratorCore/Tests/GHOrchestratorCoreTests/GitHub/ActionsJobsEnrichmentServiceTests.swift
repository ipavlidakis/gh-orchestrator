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

        let client = MockActionsGHCLIClient(outputsByEndpoint: [
            "repos/cli/cli/actions/runs/321/jobs": .success(fixtureOutput(named: "completed_jobs"))
        ])

        let service = ActionsJobsEnrichmentService(client: client)
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

        let client = MockActionsGHCLIClient(outputsByEndpoint: [
            "repos/cli/cli/actions/runs/555/jobs": .success(fixtureOutput(named: "queued_jobs"))
        ])

        let service = ActionsJobsEnrichmentService(client: client)
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

        let client = MockActionsGHCLIClient(outputsByEndpoint: [
            "repos/cli/cli/actions/runs/321/jobs": .success(fixtureOutput(named: "completed_jobs"))
        ])

        let service = ActionsJobsEnrichmentService(client: client)
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

        let client = MockActionsGHCLIClient(outputsByEndpoint: [
            "repos/cli/cli/actions/runs/321/jobs": .success(fixtureOutput(named: "completed_jobs"))
        ])

        let service = ActionsJobsEnrichmentService(client: client)
        let items = try await service.buildPullRequestItems(
            from: [RepositoryPullRequestSnapshot(repository: repository, pullRequests: [snapshot])]
        )

        XCTAssertEqual(items.first?.workflowRuns.count, 1)
        XCTAssertEqual(client.recordedEndpoints, ["repos/cli/cli/actions/runs/321/jobs"])
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

        let client = MockActionsGHCLIClient(outputsByEndpoint: [
            "repos/cli/cli/actions/runs/321/jobs": .success(
                ProcessOutput(
                    exitCode: 1,
                    standardOutput: #"{"errors":[{"type":"RATE_LIMITED","message":"API rate limit exceeded for user ID 472467."}]}"#,
                    standardError: "gh: API rate limit exceeded for user ID 472467."
                )
            )
        ])

        let service = ActionsJobsEnrichmentService(client: client)

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

private final class MockActionsGHCLIClient: GHCLIClient, @unchecked Sendable {
    enum StubResult {
        case success(ProcessOutput)
        case failure(Error)
    }

    private let outputsByEndpoint: [String: StubResult]
    private(set) var recordedEndpoints: [String] = []

    init(outputsByEndpoint: [String: StubResult]) {
        self.outputsByEndpoint = outputsByEndpoint
    }

    func run(arguments: [String]) throws -> ProcessOutput {
        guard let endpoint = arguments.last else {
            XCTFail("Missing endpoint in arguments: \(arguments)")
            return ProcessOutput(exitCode: 1, standardOutput: "", standardError: "missing endpoint")
        }

        recordedEndpoints.append(endpoint)

        guard let result = outputsByEndpoint[endpoint] else {
            XCTFail("No stub registered for endpoint: \(endpoint)")
            return ProcessOutput(exitCode: 1, standardOutput: "", standardError: "missing stub")
        }

        switch result {
        case .success(let output):
            return output
        case .failure(let error):
            throw error
        }
    }

    func health() -> GitHubCLIHealth {
        .authenticated(username: "octocat")
    }
}

private func fixtureOutput(named name: String) -> ProcessOutput {
    ProcessOutput(
        exitCode: 0,
        standardOutput: fixtureString(named: name),
        standardError: ""
    )
}

private func fixtureString(named name: String) -> String {
    let directURL = Bundle.module.url(forResource: name, withExtension: "json")
    let nestedURL = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "ActionsJobs")
    let fixturesURL = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/ActionsJobs")

    guard let url = directURL ?? nestedURL ?? fixturesURL else {
        fatalError("Missing fixture \(name).json")
    }

    guard let data = try? Data(contentsOf: url), let string = String(data: data, encoding: .utf8) else {
        fatalError("Unable to load fixture \(name).json")
    }

    return string
}
