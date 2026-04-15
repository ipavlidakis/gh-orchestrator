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
        var page = 1
        var runs: [ActionsWorkflowRunsResponseDTO.WorkflowRunDTO] = []
        var totalCount: Int?

        while page <= maximumPages, runs.count < maximumWorkflowRunCount {
            let response: ActionsWorkflowRunsResponseDTO = try await client.get(
                pathWithQuery(
                    path: "/repos/\(repository.fullName)/actions/workflows/\(workflow.id)/runs",
                    queryItems: [
                        URLQueryItem(name: "per_page", value: "\(perPage)"),
                        URLQueryItem(name: "page", value: "\(page)"),
                        URLQueryItem(name: "created", value: createdFilter(for: dateInterval))
                    ]
                )
            )

            totalCount = response.totalCount ?? totalCount
            runs.append(contentsOf: response.workflowRuns)

            guard response.workflowRuns.count == perPage else {
                break
            }

            page += 1
        }

        if runs.count > maximumWorkflowRunCount {
            runs = Array(runs.prefix(maximumWorkflowRunCount))
        }

        return (runs, (totalCount ?? runs.count) > runs.count)
    }

    private func fetchJobRecords(
        repository: ObservedRepository,
        runs: [InsightWorkflowRun],
        matchingJobName jobName: String
    ) async throws -> (records: [InsightRecord], isCapped: Bool) {
        var records: [InsightRecord] = []
        var isCapped = false

        for run in runs {
            let fetch = try await fetchJobs(repository: repository, runID: run.id)
            isCapped = isCapped || fetch.isCapped

            records.append(contentsOf: fetch.jobs.compactMap { job in
                guard job.name.caseInsensitiveCompare(jobName) == .orderedSame else {
                    return nil
                }

                return InsightRecord(job: job)
            })
        }

        return (records, isCapped)
    }

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
        guard
            job.status == "completed",
            let conclusion = job.conclusion?.trimmingCharacters(in: .whitespacesAndNewlines),
            !conclusion.isEmpty,
            let completedAt = job.completedAt
        else {
            return nil
        }

        self.conclusion = conclusion
        self.completedAt = completedAt

        if let startedAt = job.startedAt, completedAt >= startedAt {
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
