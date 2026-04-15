import Foundation
import GHOrchestratorCore
import Observation

@MainActor
@Observable
final class GitHubRequestLogModel: GitHubRequestMetricsRecording, @unchecked Sendable {
    private let maximumRecordCount: Int

    private(set) var records: [GitHubRequestRecord] = []

    init(maximumRecordCount: Int = 100) {
        self.maximumRecordCount = maximumRecordCount
    }

    var latestRateLimit: GitHubRateLimitStatus? {
        records.compactMap(\.rateLimit).first
    }

    var latestRateLimitsByResource: [GitHubRateLimitStatus] {
        var seenResources = Set<String>()
        var rateLimits: [GitHubRateLimitStatus] = []

        for rateLimit in records.compactMap(\.rateLimit) {
            let resourceKey = rateLimit.resource.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            guard !resourceKey.isEmpty, seenResources.insert(resourceKey).inserted else {
                continue
            }

            rateLimits.append(rateLimit)
        }

        return rateLimits.sorted {
            $0.resource.localizedCaseInsensitiveCompare($1.resource) == .orderedAscending
        }
    }

    var requestsWithRateLimitHeaderCount: Int {
        records.filter { $0.rateLimit != nil }.count
    }

    nonisolated func record(_ request: GitHubRequestRecord) async {
        await MainActor.run {
            records.insert(request, at: 0)

            if records.count > maximumRecordCount {
                records.removeLast(records.count - maximumRecordCount)
            }
        }
    }

    func clear() {
        records.removeAll()
    }
}
