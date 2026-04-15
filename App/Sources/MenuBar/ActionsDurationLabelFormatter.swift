import Foundation
import GHOrchestratorCore

struct ActionsDurationLabelFormatter {
    func workflowDurationText(
        for workflowRun: WorkflowRunItem,
        now: Date = .now
    ) -> String? {
        let status = normalizedStatus(workflowRun.status)

        switch status {
        case "completed":
            guard
                let start = earliestStartedAt(in: workflowRun.jobs) ?? earliestCreatedAt(in: workflowRun.jobs),
                let end = latestDate(workflowRun.jobs.compactMap(\.completedAt))
            else {
                return nil
            }

            return "completed in \(compactDuration(from: start, to: end))"

        case "in_progress", "running":
            guard let start = earliestStartedAt(in: workflowRun.jobs) ?? earliestCreatedAt(in: workflowRun.jobs) else {
                return nil
            }

            return "running for \(compactDuration(from: start, to: now))"

        case "queued", "pending", "requested", "waiting":
            guard let start = earliestDate(workflowRun.jobs.compactMap { $0.createdAt ?? $0.startedAt }) else {
                return nil
            }

            return "queued for \(compactDuration(from: start, to: now))"

        default:
            return nil
        }
    }

    func jobDurationText(
        for job: ActionJobItem,
        now: Date = .now
    ) -> String? {
        let status = normalizedStatus(job.status)

        switch status {
        case "completed":
            guard
                let start = job.startedAt ?? job.createdAt,
                let end = job.completedAt
            else {
                return nil
            }

            return "completed in \(compactDuration(from: start, to: end))"

        case "in_progress", "running":
            guard let start = job.startedAt ?? job.createdAt else {
                return nil
            }

            return "running for \(compactDuration(from: start, to: now))"

        case "queued", "pending", "requested", "waiting":
            guard let start = job.createdAt ?? job.startedAt else {
                return nil
            }

            return "queued for \(compactDuration(from: start, to: now))"

        default:
            return nil
        }
    }

    func stepDurationText(
        for step: ActionStepItem,
        now: Date = .now
    ) -> String? {
        let status = normalizedStatus(step.status)

        switch status {
        case "completed":
            guard
                let start = step.startedAt,
                let end = step.completedAt
            else {
                return nil
            }

            return "completed in \(compactDuration(from: start, to: end))"

        case "in_progress", "running":
            guard let start = step.startedAt else {
                return nil
            }

            return "running for \(compactDuration(from: start, to: now))"

        default:
            return nil
        }
    }

    private func normalizedStatus(_ status: String) -> String {
        status
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private func earliestDate(_ dates: [Date]) -> Date? {
        dates.min()
    }

    private func latestDate(_ dates: [Date]) -> Date? {
        dates.max()
    }

    private func earliestStartedAt(in jobs: [ActionJobItem]) -> Date? {
        earliestDate(jobs.compactMap(\.startedAt))
    }

    private func earliestCreatedAt(in jobs: [ActionJobItem]) -> Date? {
        earliestDate(jobs.compactMap(\.createdAt))
    }

    private func compactDuration(from start: Date, to end: Date) -> String {
        let totalSeconds = max(0, Int(end.timeIntervalSince(start).rounded(.down)))

        if totalSeconds < 60 {
            return "\(max(totalSeconds, 1))s"
        }

        let totalMinutes = totalSeconds / 60
        if totalMinutes < 60 {
            return "\(totalMinutes)m"
        }

        let totalHours = totalMinutes / 60
        let remainingMinutes = totalMinutes % 60
        if totalHours < 24 {
            return remainingMinutes == 0 ? "\(totalHours)h" : "\(totalHours)h \(remainingMinutes)m"
        }

        let days = totalHours / 24
        let remainingHours = totalHours % 24
        return remainingHours == 0 ? "\(days)d" : "\(days)d \(remainingHours)h"
    }
}
