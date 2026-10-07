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

    private let jobsCache = ActionJobsCache()

    public init(client: any GitHubAPIClient = URLSessionGitHubAPIClient()) {
        self.client = client
    }

    public func buildPullRequestItems(
        from snapshots: [RepositoryPullRequestSnapshot]
    ) async throws -> [PullRequestItem] {
        let pullRequests = snapshots.flatMap(\.pullRequests)
        let referencesByPullRequest = pullRequests.map { deduplicatedWorkflowRunReferences(from: $0.checkRuns) }

        // Fetch every run's jobs once, with bounded fan-out across all pull requests.
        var fetchTargets: [JobsFetchTarget] = []
        var seenKeys = Set<ActionJobsCache.Key>()
        for (snapshot, references) in zip(pullRequests, referencesByPullRequest) {
            for reference in references {
                let target = JobsFetchTarget(repository: snapshot.repository, reference: reference)
                if seenKeys.insert(target.runKey).inserted {
                    fetchTargets.append(target)
                }
            }
        }

        let fetchedJobs = try await BoundedConcurrency.map(fetchTargets) { target in
            try await self.jobs(for: target)
        }
        var jobsByRunKey: [ActionJobsCache.Key: [ActionJobItem]] = [:]
        for (target, jobs) in zip(fetchTargets, fetchedJobs) {
            jobsByRunKey[target.runKey] = jobs
        }

        return zip(pullRequests, referencesByPullRequest).map { snapshot, references in
            let workflowRuns = references.map { reference in
                let jobs = jobsByRunKey[ActionJobsCache.Key(repository: snapshot.repository, runID: reference.id)] ?? []
                let state = workflowState(jobs: jobs, reference: reference)
                return WorkflowRunItem(
                    id: reference.id,
                    name: reference.workflowName ?? reference.checkName,
                    status: state.status,
                    conclusion: state.conclusion,
                    detailsURL: reference.url ?? reference.fallbackDetailsURL,
                    jobs: jobs
                )
            }

            return PullRequestItem(
                repository: snapshot.repository,
                number: snapshot.number,
                title: snapshot.title,
                url: snapshot.url,
                authorLogin: snapshot.authorLogin,
                isDraft: snapshot.isDraft,
                createdAt: snapshot.createdAt,
                updatedAt: snapshot.updatedAt,
                reviewStatus: snapshot.reviewStatus,
                unresolvedReviewThreadCount: snapshot.unresolvedReviewThreadCount,
                unresolvedReviewComments: snapshot.unresolvedReviewComments.map { comment in
                    UnresolvedReviewCommentItem(
                        url: comment.url,
                        authorLogin: comment.authorLogin,
                        bodyText: comment.bodyText,
                        filePath: comment.filePath,
                        authorAvatarURL: comment.authorAvatarURL,
                        createdAt: comment.createdAt
                    )
                },
                checkRollupState: snapshot.checkRollupState,
                externalChecks: externalChecks(for: snapshot),
                workflowRuns: workflowRuns
            )
        }
    }
}

extension ActionsJobsEnrichmentService {
    /// A check run represents one job, not the whole workflow. Cache only terminal
    /// job lists, and invalidate when any sibling check changes (including reruns).
    private func jobs(for target: JobsFetchTarget) async throws -> [ActionJobItem] {
        let cacheChecks = target.isCacheable ? target.reference.checkRuns : nil

        if let cacheChecks, let cached = await jobsCache.jobs(for: target.runKey, checkRuns: cacheChecks) {
            return cached
        }

        let jobs = try await fetchJobs(repository: target.repository, runID: target.reference.id)

        if let cacheChecks, !jobs.isEmpty,
           jobs.allSatisfy({ $0.status.caseInsensitiveCompare("completed") == .orderedSame }) {
            await jobsCache.store(jobs, for: target.runKey, checkRuns: cacheChecks)
        }

        return jobs
    }

    private func workflowState(
        jobs: [ActionJobItem],
        reference: WorkflowRunReference
    ) -> (status: String, conclusion: String?) {
        guard !jobs.isEmpty else {
            return (reference.status, reference.conclusion)
        }
        if jobs.contains(where: { $0.status.caseInsensitiveCompare("in_progress") == .orderedSame }) {
            return ("in_progress", nil)
        }
        if let pending = jobs.first(where: { $0.status.caseInsensitiveCompare("completed") != .orderedSame }) {
            return (pending.status, nil)
        }
        let conclusions = jobs.compactMap { $0.conclusion?.lowercased() }
        let failure = conclusions.first { !["success", "skipped", "neutral"].contains($0) }
        return ("completed", failure ?? (conclusions.contains("success") ? "success" : conclusions.first))
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
        let checksByRunID = Dictionary(grouping: checkRuns.filter(isActionsBacked)) { $0.workflowRun?.id }

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
                    checkRuns: checksByRunID[workflowRun.id] ?? [],
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
                    createdAt: job.createdAt,
                    startedAt: job.startedAt,
                    completedAt: job.completedAt,
                    detailsURL: job.htmlURL,
                    steps: (job.steps ?? []).map { step in
                        ActionStepItem(
                            number: step.number,
                            name: step.name,
                            status: step.status,
                            conclusion: step.conclusion,
                            startedAt: step.startedAt,
                            completedAt: step.completedAt,
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
    let checkRuns: [CheckRunSnapshot]
    let fallbackDetailsURL: URL?
}

private struct JobsFetchTarget: Sendable {
    let repository: ObservedRepository
    let reference: WorkflowRunReference

    var runKey: ActionJobsCache.Key {
        ActionJobsCache.Key(repository: repository, runID: reference.id)
    }

    var isCacheable: Bool {
        !reference.checkRuns.isEmpty && reference.checkRuns.allSatisfy {
            $0.status.caseInsensitiveCompare("completed") == .orderedSame && $0.completedAt != nil
        }
    }
}

private actor ActionJobsCache {
    struct Key: Hashable, Sendable {
        let repository: String
        let runID: Int

        init(repository: ObservedRepository, runID: Int) {
            self.repository = repository.fullName.lowercased()
            self.runID = runID
        }
    }

    private struct Entry {
        let checkRuns: [CheckRunSnapshot]
        let jobs: [ActionJobItem]
    }

    private let maximumEntryCount = 500
    private var entries: [Key: Entry] = [:]

    func jobs(for key: Key, checkRuns: [CheckRunSnapshot]) -> [ActionJobItem]? {
        guard let entry = entries[key], entry.checkRuns == checkRuns else {
            return nil
        }

        return entry.jobs
    }

    func store(_ jobs: [ActionJobItem], for key: Key, checkRuns: [CheckRunSnapshot]) {
        if entries.count >= maximumEntryCount, entries[key] == nil {
            entries.removeAll(keepingCapacity: true)
        }

        entries[key] = Entry(checkRuns: checkRuns, jobs: jobs)
    }
}
