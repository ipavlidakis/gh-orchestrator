import Foundation

public enum ActionsInsightsPeriod: String, CaseIterable, Codable, Identifiable, Sendable {
    case previousMonth
    case last7Days
    case last30Days
    case last90Days

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .previousMonth:
            return "Last month"
        case .last7Days:
            return "Last 7 days"
        case .last30Days:
            return "Last 30 days"
        case .last90Days:
            return "Last 90 days"
        }
    }

    public func dateInterval(
        containing now: Date,
        calendar: Calendar = .current
    ) -> DateInterval {
        switch self {
        case .previousMonth:
            let components = calendar.dateComponents([.year, .month], from: now)
            guard
                let startOfCurrentMonth = calendar.date(from: components),
                let startOfPreviousMonth = calendar.date(byAdding: .month, value: -1, to: startOfCurrentMonth)
            else {
                return rollingDateInterval(dayCount: 30, endingAt: now, calendar: calendar)
            }

            return DateInterval(start: startOfPreviousMonth, end: startOfCurrentMonth)
        case .last7Days:
            return rollingDateInterval(dayCount: 7, endingAt: now, calendar: calendar)
        case .last30Days:
            return rollingDateInterval(dayCount: 30, endingAt: now, calendar: calendar)
        case .last90Days:
            return rollingDateInterval(dayCount: 90, endingAt: now, calendar: calendar)
        }
    }

    private func rollingDateInterval(
        dayCount: Int,
        endingAt now: Date,
        calendar: Calendar
    ) -> DateInterval {
        let start = calendar.date(byAdding: .day, value: -dayCount, to: now) ?? now
        return DateInterval(start: start, end: now)
    }
}

public struct ActionsInsightsSelection: Codable, Equatable, Sendable {
    public var repositoryID: String?
    public var workflowID: Int?
    public var workflowName: String?
    public var jobName: String?
    /// True when the user explicitly chose "All jobs" (workflow-level duration), as opposed to
    /// not having chosen a job yet, which both leave `jobName` empty.
    public var includesAllJobs: Bool
    public var period: ActionsInsightsPeriod

    public init(
        repositoryID: String? = nil,
        workflowID: Int? = nil,
        workflowName: String? = nil,
        jobName: String? = nil,
        includesAllJobs: Bool = false,
        period: ActionsInsightsPeriod = .previousMonth
    ) {
        self.repositoryID = repositoryID
        self.workflowID = workflowID
        self.workflowName = workflowName
        self.jobName = jobName
        self.includesAllJobs = includesAllJobs
        self.period = period
    }

    private enum CodingKeys: String, CodingKey {
        case repositoryID
        case workflowID
        case workflowName
        case jobName
        case includesAllJobs
        case period
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            repositoryID: try container.decodeIfPresent(String.self, forKey: .repositoryID),
            workflowID: try container.decodeIfPresent(Int.self, forKey: .workflowID),
            workflowName: try container.decodeIfPresent(String.self, forKey: .workflowName),
            jobName: try container.decodeIfPresent(String.self, forKey: .jobName),
            includesAllJobs: try container.decodeIfPresent(Bool.self, forKey: .includesAllJobs) ?? false,
            period: try container.decodeIfPresent(ActionsInsightsPeriod.self, forKey: .period) ?? .previousMonth
        )
    }
}
