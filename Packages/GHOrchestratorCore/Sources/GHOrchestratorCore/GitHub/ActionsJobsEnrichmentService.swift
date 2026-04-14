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
    public let client: any GHCLIClient

    public init(client: any GHCLIClient = ProcessGHCLIClient()) {
        self.client = client
    }

    public func buildPullRequestItems(
        from snapshots: [RepositoryPullRequestSnapshot]
    ) async throws -> [PullRequestItem] {
        var items: [PullRequestItem] = []

        for repositorySnapshot in snapshots {
            for snapshot in repositorySnapshot.pullRequests {
                let workflowRuns = try workflowRuns(for: snapshot)
                let externalChecks = externalChecks(for: snapshot)

                items.append(
                    PullRequestItem(
                        repository: snapshot.repository,
                        number: snapshot.number,
                        title: snapshot.title,
                        url: snapshot.url,
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
    private func workflowRuns(for snapshot: PullRequestSnapshotItem) throws -> [WorkflowRunItem] {
        let references = deduplicatedWorkflowRunReferences(from: snapshot.checkRuns)

        return try references.map { reference in
            let jobs = try fetchJobs(
                repository: snapshot.repository,
                runID: reference.id
            )

            return WorkflowRunItem(
                id: reference.id,
                name: reference.workflowName ?? reference.checkName,
                status: reference.status,
                conclusion: reference.conclusion,
                detailsURL: reference.url ?? reference.fallbackDetailsURL,
                jobs: jobs
            )
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
    ) throws -> [ActionJobItem] {
        let output: ProcessOutput

        do {
            output = try client.run(arguments: [
                "api",
                "--hostname",
                "github.com",
                "repos/\(repository.fullName)/actions/runs/\(runID)/jobs",
            ])
        } catch {
            throw ActionsJobsEnrichmentError.workflowJobsRequestFailed(
                repository: repository,
                runID: runID,
                message: error.localizedDescription
            )
        }

        guard output.exitCode == 0 else {
            throw ActionsJobsEnrichmentError.workflowJobsRequestFailed(
                repository: repository,
                runID: runID,
                message: output.combinedOutput.isEmpty
                    ? "gh api exited with code \(output.exitCode)"
                    : GitHubAPIErrorMessageFormatter.normalize(output.combinedOutput)
            )
        }

        do {
            let response = try JSONDecoder.githubREST.decode(
                ActionsJobsResponseDTO.self,
                from: Data(output.standardOutput.utf8)
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
        } catch {
            throw ActionsJobsEnrichmentError.invalidWorkflowJobsResponse(
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

private extension JSONDecoder {
    static let githubREST: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = parseISO8601Date(value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date: \(value)"
            )
        }
        return decoder
    }()
}
