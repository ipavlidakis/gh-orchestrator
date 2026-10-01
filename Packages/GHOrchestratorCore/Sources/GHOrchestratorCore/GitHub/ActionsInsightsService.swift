import Foundation

public protocol ActionsInsightsLoading: Sendable {
    func loadInsights(
        repository: ObservedRepository,
        workflow: ActionsWorkflowItem,
        jobName: String?,
        period: ActionsInsightsPeriod,
        now: Date
    ) async throws -> ActionsInsightsDashboard
}

public struct ActionsInsightsDashboard: Equatable, Sendable {
    public let dateInterval: DateInterval
    public let summary: ActionsInsightsSummary
    public let dataPoints: [ActionsInsightsDataPoint]
    public let isWorkflowRunResultCapped: Bool
    public let isJobResultCapped: Bool

    public init(
        dateInterval: DateInterval,
        summary: ActionsInsightsSummary,
        dataPoints: [ActionsInsightsDataPoint],
        isWorkflowRunResultCapped: Bool = false,
        isJobResultCapped: Bool = false
    ) {
        self.dateInterval = dateInterval
        self.summary = summary
        self.dataPoints = dataPoints
        self.isWorkflowRunResultCapped = isWorkflowRunResultCapped
        self.isJobResultCapped = isJobResultCapped
    }
}

public struct ActionsInsightsSummary: Equatable, Sendable {
    public let totalCount: Int
    public let successCount: Int
    public let failureCount: Int
    public let averageDurationSeconds: TimeInterval?

    public init(
        totalCount: Int,
        successCount: Int,
        failureCount: Int,
        averageDurationSeconds: TimeInterval?
    ) {
        self.totalCount = totalCount
        self.successCount = successCount
        self.failureCount = failureCount
        self.averageDurationSeconds = averageDurationSeconds
    }

    public var successRate: Double? {
        guard totalCount > 0 else {
            return nil
        }

        return Double(successCount) / Double(totalCount)
    }

    public var failureRate: Double? {
        guard totalCount > 0 else {
            return nil
        }

        return Double(failureCount) / Double(totalCount)
    }
}

public struct ActionsInsightsDataPoint: Equatable, Identifiable, Sendable {
    public var id: Date { date }

    public let date: Date
    public let successCount: Int
    public let failureCount: Int
    public let averageDurationSeconds: TimeInterval?

    public init(
        date: Date,
        successCount: Int,
        failureCount: Int,
        averageDurationSeconds: TimeInterval?
    ) {
        self.date = date
        self.successCount = successCount
        self.failureCount = failureCount
        self.averageDurationSeconds = averageDurationSeconds
    }

    public var totalCount: Int {
        successCount + failureCount
    }

    public var successRate: Double? {
        guard totalCount > 0 else {
            return nil
        }

        return Double(successCount) / Double(totalCount)
    }

    public var failureRate: Double? {
        guard totalCount > 0 else {
            return nil
        }

        return Double(failureCount) / Double(totalCount)
    }
}

public enum ActionsInsightsError: Error, Equatable, Sendable {
    case requestFailed(repository: ObservedRepository, workflowName: String, message: String)
    case invalidResponse(repository: ObservedRepository, workflowName: String, message: String)
}

extension ActionsInsightsError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .requestFailed(let repository, let workflowName, let message):
            return "Failed to load Actions insights for \(workflowName) in \(repository.fullName): \(message)"
        case .invalidResponse(let repository, let workflowName, let message):
            return "Received invalid Actions insights data for \(workflowName) in \(repository.fullName): \(message)"
        }
    }
}

public struct ActionsInsightsService: ActionsInsightsLoading {
    public let client: any GitHubAPIClient
    public let maximumWorkflowRunCount: Int
    public let maximumJobPageCount: Int

    private let perPage = 100
    private let jobsBatchSize = 50
    private let jobsCache = InsightJobsCache()

    public init(
        client: any GitHubAPIClient = URLSessionGitHubAPIClient(),
        maximumWorkflowRunCount: Int = 1_000,
        maximumJobPageCount: Int = 10
    ) {
        self.client = client
        self.maximumWorkflowRunCount = max(maximumWorkflowRunCount, 1)
        self.maximumJobPageCount = max(maximumJobPageCount, 1)
    }

    public func loadInsights(
        repository: ObservedRepository,
        workflow: ActionsWorkflowItem,
        jobName: String?,
        period: ActionsInsightsPeriod,
        now: Date
    ) async throws -> ActionsInsightsDashboard {
        let dateInterval = period.dateInterval(containing: now)

        do {
            let runFetch = try await fetchWorkflowRuns(
                repository: repository,
                workflow: workflow,
                dateInterval: dateInterval
            )
            let completedRuns = runFetch.runs.compactMap(InsightWorkflowRun.init(dto:))
            let trimmedJobName = jobName?.trimmingCharacters(in: .whitespacesAndNewlines)

            if let trimmedJobName, !trimmedJobName.isEmpty {
                let jobFetch = try await fetchJobRecords(
                    repository: repository,
                    runs: completedRuns,
                    matchingJobName: trimmedJobName
                )
                return dashboard(
                    dateInterval: dateInterval,
                    records: jobFetch.records,
                    workflowRunCapped: runFetch.isCapped,
                    jobCapped: jobFetch.isCapped
                )
            }

            return dashboard(
                dateInterval: dateInterval,
                records: completedRuns.map(InsightRecord.init(run:)),
                workflowRunCapped: runFetch.isCapped,
                jobCapped: false
            )
        } catch let error as GitHubAPIClientError {
            switch error {
            case .invalidResponse(let message):
                throw ActionsInsightsError.invalidResponse(
                    repository: repository,
                    workflowName: workflow.name,
                    message: message
                )
            default:
                throw ActionsInsightsError.requestFailed(
                    repository: repository,
                    workflowName: workflow.name,
                    message: error.displayMessage
                )
            }
        } catch let error as ActionsInsightsError {
            throw error
        } catch {
            throw ActionsInsightsError.requestFailed(
                repository: repository,
                workflowName: workflow.name,
                message: error.localizedDescription
            )
        }
    }

    private func fetchWorkflowRuns(
        repository: ObservedRepository,
        workflow: ActionsWorkflowItem,
        dateInterval: DateInterval
    ) async throws -> (runs: [ActionsWorkflowRunsResponseDTO.WorkflowRunDTO], isCapped: Bool) {
        let maximumPages = max(Int(ceil(Double(maximumWorkflowRunCount) / Double(perPage))), 1)
        let first = try await fetchWorkflowRunPage(
            repository: repository,
            workflow: workflow,
            dateInterval: dateInterval,
            page: 1
        )
        var runs = first.workflowRuns
        var totalCount = first.totalCount

        if first.workflowRuns.count == perPage, maximumPages > 1 {
            if let total = first.totalCount {
                // total_count is known after page 1, so the remaining pages can load concurrently.
                let lastPage = min(maximumPages, Int(ceil(Double(total) / Double(perPage))))
                if lastPage >= 2 {
                    let pages = try await BoundedConcurrency.map(Array(2...lastPage)) { page in
                        try await self.fetchWorkflowRunPage(
                            repository: repository,
                            workflow: workflow,
                            dateInterval: dateInterval,
                            page: page
                        )
                    }
                    runs.append(contentsOf: pages.flatMap(\.workflowRuns))
                }
            } else {
                var page = 2
                while page <= maximumPages {
                    let response = try await fetchWorkflowRunPage(
                        repository: repository,
                        workflow: workflow,
                        dateInterval: dateInterval,
                        page: page
                    )
                    totalCount = response.totalCount ?? totalCount
                    runs.append(contentsOf: response.workflowRuns)

                    guard response.workflowRuns.count == perPage else {
                        break
                    }

                    page += 1
                }
            }
        }

        if runs.count > maximumWorkflowRunCount {
            runs = Array(runs.prefix(maximumWorkflowRunCount))
        }

        return (runs, (totalCount ?? runs.count) > runs.count)
    }

    private func fetchWorkflowRunPage(
        repository: ObservedRepository,
        workflow: ActionsWorkflowItem,
        dateInterval: DateInterval,
        page: Int
    ) async throws -> ActionsWorkflowRunsResponseDTO {
        try await client.get(
            pathWithQuery(
                path: "/repos/\(repository.fullName)/actions/workflows/\(workflow.id)/runs",
                queryItems: [
                    URLQueryItem(name: "per_page", value: "\(perPage)"),
                    URLQueryItem(name: "page", value: "\(page)"),
                    URLQueryItem(name: "created", value: createdFilter(for: dateInterval))
                ]
            )
        )
    }

    private func fetchJobRecords(
        repository: ObservedRepository,
        runs: [InsightWorkflowRun],
        matchingJobName jobName: String
    ) async throws -> (records: [InsightRecord], isCapped: Bool) {
        let fetches = try await loadJobs(repository: repository, runs: runs)

        let records = fetches.flatMap { fetch in
            fetch.jobs.compactMap { job in
                job.name.caseInsensitiveCompare(jobName) == .orderedSame ? job.record : nil
            }
        }

        return (records, fetches.contains { $0.isCapped })
    }

    /// Resolves jobs for every run: cache first, then batched GraphQL (many runs per request),
    /// then per-run REST for runs that carry no GraphQL node ID.
    private func loadJobs(
        repository: ObservedRepository,
        runs: [InsightWorkflowRun]
    ) async throws -> [InsightJobsFetch] {
        var results = [InsightJobsFetch?](repeating: nil, count: runs.count)
        var batchableIndexes: [Int] = []
        var restIndexes: [Int] = []

        for (index, run) in runs.enumerated() {
            if let cached = await jobsCache.fetch(for: cacheKey(repository: repository, run: run)) {
                results[index] = cached
            } else if run.nodeID != nil {
                batchableIndexes.append(index)
            } else {
                restIndexes.append(index)
            }
        }

        let batches = stride(from: 0, to: batchableIndexes.count, by: jobsBatchSize).map {
            Array(batchableIndexes[$0..<min($0 + jobsBatchSize, batchableIndexes.count)])
        }
        let batchResults = try await BoundedConcurrency.map(batches, limit: 4) { indexes in
            let fetches = try await self.fetchJobsBatch(runs: indexes.map { runs[$0] })
            for (index, fetch) in zip(indexes, fetches) {
                await self.jobsCache.store(fetch, for: self.cacheKey(repository: repository, run: runs[index]))
            }
            return Array(zip(indexes, fetches))
        }
        for (index, fetch) in batchResults.joined() {
            results[index] = fetch
        }

        let restResults = try await BoundedConcurrency.map(restIndexes) { index in
            let fetch = try await self.fetchJobsREST(repository: repository, run: runs[index])
            return (index, fetch)
        }
        for (index, fetch) in restResults {
            results[index] = fetch
        }

        return results.compactMap { $0 }
    }

    /// Completed runs only change when re-run, which bumps `updated_at`, so
    /// `(run id, completedAt)` identifies an immutable job list.
    private func cacheKey(repository: ObservedRepository, run: InsightWorkflowRun) -> InsightJobsCache.Key {
        InsightJobsCache.Key(
            repository: repository.fullName.lowercased(),
            runID: run.id,
            completedAt: run.completedAt
        )
    }

    private func fetchJobsREST(
        repository: ObservedRepository,
        run: InsightWorkflowRun
    ) async throws -> InsightJobsFetch {
        let fetch = try await fetchJobs(repository: repository, runID: run.id)
        let result = InsightJobsFetch(
            jobs: fetch.jobs.map { InsightJob(name: $0.name, record: InsightRecord(job: $0)) },
            isCapped: fetch.isCapped
        )
        await jobsCache.store(result, for: cacheKey(repository: repository, run: run))
        return result
    }

    /// One GraphQL request returns the check runs (Actions jobs) of up to `jobsBatchSize` runs.
    private func fetchJobsBatch(runs: [InsightWorkflowRun]) async throws -> [InsightJobsFetch] {
        let response: InsightJobsBatchResponse = try await client.graphQL(
            query: Self.jobsBatchQuery,
            variables: InsightJobsBatchVariables(ids: runs.compactMap(\.nodeID))
        )

        guard response.nodes.count == runs.count else {
            throw GitHubAPIClientError.invalidResponse(
                message: "GitHub returned \(response.nodes.count) workflow runs for \(runs.count) requested."
            )
        }

        return response.nodes.map { node in
            let checkRuns = node?.checkSuite?.checkRuns
            let nodes = checkRuns?.nodes?.compactMap { $0 } ?? []
            let jobs = nodes.map { checkRun in
                InsightJob(
                    name: checkRun.name,
                    record: InsightRecord(
                        status: checkRun.status,
                        conclusion: checkRun.conclusion,
                        startedAt: checkRun.startedAt,
                        completedAt: checkRun.completedAt
                    )
                )
            }

            return InsightJobsFetch(jobs: jobs, isCapped: (checkRuns?.totalCount ?? nodes.count) > nodes.count)
        }
    }

    private static let jobsBatchQuery = """
    query($ids: [ID!]!) {
      nodes(ids: $ids) {
        ... on WorkflowRun {
          checkSuite {
            checkRuns(first: 100) {
              totalCount
              nodes {
                name
                status
                conclusion
                startedAt
                completedAt
              }
            }
          }
        }
      }
    }
    """

    private func fetchJobs(
        repository: ObservedRepository,
        runID: Int
    ) async throws -> (jobs: [ActionsJobsResponseDTO.JobDTO], isCapped: Bool) {
        var page = 1
        var jobs: [ActionsJobsResponseDTO.JobDTO] = []
        var totalCount: Int?

        while page <= maximumJobPageCount {
            let response: ActionsJobsResponseDTO = try await client.get(
                pathWithQuery(
                    path: "/repos/\(repository.fullName)/actions/runs/\(runID)/jobs",
                    queryItems: [
                        URLQueryItem(name: "per_page", value: "\(perPage)"),
                        URLQueryItem(name: "page", value: "\(page)")
                    ]
                )
            )

            totalCount = response.totalCount ?? totalCount
            jobs.append(contentsOf: response.jobs)

            guard response.jobs.count == perPage else {
                break
            }

            page += 1
        }

        return (jobs, (totalCount ?? jobs.count) > jobs.count)
    }

    private func dashboard(
        dateInterval: DateInterval,
        records: [InsightRecord],
        workflowRunCapped: Bool,
        jobCapped: Bool
    ) -> ActionsInsightsDashboard {
        let sortedRecords = records.sorted { $0.completedAt < $1.completedAt }
        let summary = summary(records: sortedRecords)
        let points = dataPoints(records: sortedRecords)

        return ActionsInsightsDashboard(
            dateInterval: dateInterval,
            summary: summary,
            dataPoints: points,
            isWorkflowRunResultCapped: workflowRunCapped,
            isJobResultCapped: jobCapped
        )
    }

    private func summary(records: [InsightRecord]) -> ActionsInsightsSummary {
        let successCount = records.filter(\.isSuccess).count
        let failureCount = records.count - successCount
        let durations = records.compactMap(\.durationSeconds)
        let averageDuration = durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count)

        return ActionsInsightsSummary(
            totalCount: records.count,
            successCount: successCount,
            failureCount: failureCount,
            averageDurationSeconds: averageDuration
        )
    }

    private func dataPoints(records: [InsightRecord]) -> [ActionsInsightsDataPoint] {
        var buckets: [Date: InsightBucket] = [:]
        let calendar = Calendar.current

        for record in records {
            let day = calendar.startOfDay(for: record.completedAt)
            var bucket = buckets[day] ?? InsightBucket()
            bucket.record(record)
            buckets[day] = bucket
        }

        return buckets.keys.sorted().map { day in
            let bucket = buckets[day] ?? InsightBucket()
            return ActionsInsightsDataPoint(
                date: day,
                successCount: bucket.successCount,
                failureCount: bucket.failureCount,
                averageDurationSeconds: bucket.averageDurationSeconds
            )
        }
    }

    private func pathWithQuery(
        path: String,
        queryItems: [URLQueryItem]
    ) -> String {
        var components = URLComponents()
        components.queryItems = queryItems
        guard let query = components.percentEncodedQuery, !query.isEmpty else {
            return path
        }

        return "\(path)?\(query)"
    }

    private func createdFilter(for dateInterval: DateInterval) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return "\(formatter.string(from: dateInterval.start))..\(formatter.string(from: dateInterval.end))"
    }
}

private struct InsightWorkflowRun {
    let id: Int
    let nodeID: String?
    let conclusion: String
    let completedAt: Date
    let durationSeconds: TimeInterval?

    init?(dto: ActionsWorkflowRunsResponseDTO.WorkflowRunDTO) {
        guard
            dto.status == "completed",
            let conclusion = dto.conclusion?.trimmingCharacters(in: .whitespacesAndNewlines),
            !conclusion.isEmpty,
            let completedAt = dto.updatedAt
        else {
            return nil
        }

        self.id = dto.id
        self.nodeID = dto.nodeID
        self.conclusion = conclusion
        self.completedAt = completedAt

        if let startedAt = dto.runStartedAt ?? dto.createdAt, completedAt >= startedAt {
            self.durationSeconds = completedAt.timeIntervalSince(startedAt)
        } else {
            self.durationSeconds = nil
        }
    }
}

private struct InsightRecord {
    let conclusion: String
    let completedAt: Date
    let durationSeconds: TimeInterval?

    init(run: InsightWorkflowRun) {
        self.conclusion = run.conclusion
        self.completedAt = run.completedAt
        self.durationSeconds = run.durationSeconds
    }

    init?(job: ActionsJobsResponseDTO.JobDTO) {
        self.init(
            status: job.status,
            conclusion: job.conclusion,
            startedAt: job.startedAt,
            completedAt: job.completedAt
        )
    }

    init?(status: String, conclusion: String?, startedAt: Date?, completedAt: Date?) {
        guard
            status.caseInsensitiveCompare("completed") == .orderedSame,
            let conclusion = conclusion?.trimmingCharacters(in: .whitespacesAndNewlines),
            !conclusion.isEmpty,
            let completedAt
        else {
            return nil
        }

        self.conclusion = conclusion
        self.completedAt = completedAt

        if let startedAt, completedAt >= startedAt {
            self.durationSeconds = completedAt.timeIntervalSince(startedAt)
        } else {
            self.durationSeconds = nil
        }
    }

    var isSuccess: Bool {
        conclusion.caseInsensitiveCompare("success") == .orderedSame
    }
}

private struct InsightBucket {
    var successCount = 0
    var failureCount = 0
    var totalDurationSeconds: TimeInterval = 0
    var durationCount = 0

    mutating func record(_ record: InsightRecord) {
        if record.isSuccess {
            successCount += 1
        } else {
            failureCount += 1
        }

        if let durationSeconds = record.durationSeconds {
            totalDurationSeconds += durationSeconds
            durationCount += 1
        }
    }

    var averageDurationSeconds: TimeInterval? {
        guard durationCount > 0 else {
            return nil
        }

        return totalDurationSeconds / Double(durationCount)
    }
}


private struct InsightJob: Sendable {
    let name: String
    let record: InsightRecord?
}

private struct InsightJobsFetch: Sendable {
    let jobs: [InsightJob]
    let isCapped: Bool
}

private actor InsightJobsCache {
    struct Key: Hashable, Sendable {
        let repository: String
        let runID: Int
        let completedAt: Date
    }

    private let maximumEntryCount = 5_000
    private var entries: [Key: InsightJobsFetch] = [:]

    func fetch(for key: Key) -> InsightJobsFetch? {
        entries[key]
    }

    func store(_ fetch: InsightJobsFetch, for key: Key) {
        if entries.count >= maximumEntryCount {
            entries.removeAll(keepingCapacity: true)
        }

        entries[key] = fetch
    }
}


private struct InsightJobsBatchVariables: Encodable, Sendable {
    let ids: [String]
}

private struct InsightJobsBatchResponse: Decodable, Sendable {
    let nodes: [Node?]

    struct Node: Decodable, Sendable {
        let checkSuite: CheckSuite?
    }

    struct CheckSuite: Decodable, Sendable {
        let checkRuns: CheckRuns?
    }

    struct CheckRuns: Decodable, Sendable {
        let totalCount: Int?
        let nodes: [CheckRun?]?
    }

    struct CheckRun: Decodable, Sendable {
        let name: String
        let status: String
        let conclusion: String?
        let startedAt: Date?
        let completedAt: Date?
    }
}
