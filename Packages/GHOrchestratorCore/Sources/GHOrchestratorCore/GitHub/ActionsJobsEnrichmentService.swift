import Foundation

public protocol ActionsJobsEnriching: Sendable {
    func buildPullRequestItems(
        from snapshots: [RepositoryPullRequestSnapshot]
    ) async throws -> [PullRequestItem]
}

public enum ActionsJobsEnrichmentError: Error, Equatable, Sendable {
    case workflowJobsRequestFailed(repository: ObservedRepository, runID: Int, message: String)
    case invalidWorkflowJobsResponse(repository: ObservedRepository, runID: Int, message: String)
}

extension ActionsJobsEnrichmentError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .workflowJobsRequestFailed(let repository, _, let message):
            return "Failed to load Actions jobs for \(repository.fullName): \(message)"
        case .invalidWorkflowJobsResponse(let repository, _, let message):
            return "Received an invalid Actions jobs response for \(repository.fullName): \(message)"
        }
    }
}

public struct ActionsJobsEnrichmentService: ActionsJobsEnriching {
    public let client: any GitHubAPIClient

    public init(client: any GitHubAPIClient = URLSessionGitHubAPIClient()) {
        self.client = client
    }

    public func buildPullRequestItems(
        from snapshots: [RepositoryPullRequestSnapshot]
    ) async throws -> [PullRequestItem] {
        var items: [PullRequestItem] = []

        for repositorySnapshot in snapshots {
            for snapshot in repositorySnapshot.pullRequests {
                let workflowRuns = try await workflowRuns(for: snapshot)
                let externalChecks = externalChecks(for: snapshot)

                items.append(
                    PullRequestItem(
                        repository: snapshot.repository,
                        number: snapshot.number,
                        title: snapshot.title,
                        url: snapshot.url,
                        authorLogin: snapshot.authorLogin,
                        isDraft: snapshot.isDraft,
                        updatedAt: snapshot.updatedAt,
                        reviewStatus: snapshot.reviewStatus,
                        unresolvedReviewThreadCount: snapshot.unresolvedReviewThreadCount,
                        unresolvedReviewComments: snapshot.unresolvedReviewComments.map { comment in
                            UnresolvedReviewCommentItem(
                                url: comment.url,
                                authorLogin: comment.authorLogin,
                                bodyText: comment.bodyText,
                                filePath: comment.filePath
                            )
                        },
                        checkRollupState: snapshot.checkRollupState,
                        externalChecks: externalChecks,
                        workflowRuns: workflowRuns
                    )
                )
            }
        }

        return items
    }
}

extension ActionsJobsEnrichmentService {
    private func workflowRuns(for snapshot: PullRequestSnapshotItem) async throws -> [WorkflowRunItem] {
        let references = deduplicatedWorkflowRunReferences(from: snapshot.checkRuns)

        return try await withThrowingTaskGroup(of: (Int, WorkflowRunItem).self) { group in
            for (index, reference) in references.enumerated() {
                group.addTask {
                    let jobs = try await fetchJobs(
                        repository: snapshot.repository,
                        runID: reference.id
                    )

                    return (
                        index,
                        WorkflowRunItem(
                            id: reference.id,
                            name: reference.workflowName ?? reference.checkName,
                            status: reference.status,
                            conclusion: reference.conclusion,
                            detailsURL: reference.url ?? reference.fallbackDetailsURL,
                            jobs: jobs
                        )
                    )
                }
            }

            var results: [(Int, WorkflowRunItem)] = []
            for try await result in group {
                results.append(result)
            }

            return results
                .sorted { $0.0 < $1.0 }
                .map(\.1)
        }
    }

    private func externalChecks(for snapshot: PullRequestSnapshotItem) -> [ExternalCheckItem] {
        let externalCheckRuns = snapshot.checkRuns.compactMap { checkRun -> ExternalCheckItem? in
            guard !isActionsBacked(checkRun) else {
                return nil
            }

            return ExternalCheckItem(
                name: checkRun.name,
                status: checkRun.status,
                conclusion: checkRun.conclusion,
                detailsURL: checkRun.detailsURL,
                summary: checkRun.appName
            )
        }

        let statusContextChecks = snapshot.statusContexts.map { statusContext in
            ExternalCheckItem(
                name: statusContext.context,
                status: statusContext.state,
                conclusion: nil,
                detailsURL: statusContext.targetURL,
                summary: statusContext.description
            )
        }

        return externalCheckRuns + statusContextChecks
    }

    private func deduplicatedWorkflowRunReferences(
        from checkRuns: [CheckRunSnapshot]
    ) -> [WorkflowRunReference] {
        var orderedReferences: [WorkflowRunReference] = []
        var seenRunIDs = Set<Int>()

        for checkRun in checkRuns where isActionsBacked(checkRun) {
            guard let workflowRun = checkRun.workflowRun else {
                continue
            }

            guard seenRunIDs.insert(workflowRun.id).inserted else {
                continue
            }

            orderedReferences.append(
                WorkflowRunReference(
                    id: workflowRun.id,
                    url: workflowRun.url,
                    workflowName: workflowRun.workflowName,
                    checkName: checkRun.name,
                    status: checkRun.status,
                    conclusion: checkRun.conclusion,
                    fallbackDetailsURL: checkRun.detailsURL
                )
            )
        }

        return orderedReferences
    }

    private func isActionsBacked(_ checkRun: CheckRunSnapshot) -> Bool {
        checkRun.appSlug == "github-actions" || checkRun.workflowRun != nil
    }

    private func fetchJobs(
        repository: ObservedRepository,
        runID: Int
    ) async throws -> [ActionJobItem] {
        do {
            let response: ActionsJobsResponseDTO = try await client.get(
                "/repos/\(repository.fullName)/actions/runs/\(runID)/jobs"
            )

            return response.jobs.map { job in
                ActionJobItem(
                    id: job.id,
                    name: job.name,
                    status: job.status,
                    conclusion: job.conclusion,
                    startedAt: job.startedAt,
                    completedAt: job.completedAt,
                    detailsURL: job.htmlURL,
                    steps: (job.steps ?? []).map { step in
                        ActionStepItem(
                            number: step.number,
                            name: step.name,
                            status: step.status,
                            conclusion: step.conclusion,
                            detailsURL: ActionsStepLinkBuilder.stepURL(jobURL: job.htmlURL, stepNumber: step.number)
                        )
                    }
                )
            }
        } catch let error as GitHubAPIClientError {
            switch error {
            case .invalidResponse(let message):
                throw ActionsJobsEnrichmentError.invalidWorkflowJobsResponse(
                    repository: repository,
                    runID: runID,
                    message: message
                )
            default:
                throw ActionsJobsEnrichmentError.workflowJobsRequestFailed(
                    repository: repository,
                    runID: runID,
                    message: error.displayMessage
                )
            }
        } catch {
            throw ActionsJobsEnrichmentError.workflowJobsRequestFailed(
                repository: repository,
                runID: runID,
                message: error.localizedDescription
            )
        }
    }
}

private struct WorkflowRunReference: Equatable, Sendable {
    let id: Int
    let url: URL?
    let workflowName: String?
    let checkName: String
    let status: String
    let conclusion: String?
    let fallbackDetailsURL: URL?
}
