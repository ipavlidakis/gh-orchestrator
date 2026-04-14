import Foundation

public protocol RepositorySectionAggregating: Sendable {
    func makeSections(
        observedRepositories: [ObservedRepository],
        pullRequests: [PullRequestItem]
    ) -> [RepositorySection]
}

public struct RepositorySectionAggregationService: RepositorySectionAggregating {
    public init() {}

    public func makeSections(
        observedRepositories: [ObservedRepository],
        pullRequests: [PullRequestItem]
    ) -> [RepositorySection] {
        let groupedPullRequests = Dictionary(grouping: pullRequests, by: \.repository.normalizedLookupKey)
        let repositoriesByKey = canonicalRepositories(
            observedRepositories: observedRepositories,
            pullRequests: pullRequests
        )

        let unsortedSections = repositoriesByKey.compactMap { key, repository -> RepositorySection? in
            guard let grouped = groupedPullRequests[key], !grouped.isEmpty else {
                return nil
            }

            return RepositorySection(
                repository: repository,
                pullRequests: grouped.sorted(by: Self.isPullRequestOrderedBefore)
            )
        }

        return unsortedSections.sorted(by: Self.isSectionOrderedBefore)
    }
}

extension RepositorySectionAggregationService {
    private func canonicalRepositories(
        observedRepositories: [ObservedRepository],
        pullRequests: [PullRequestItem]
    ) -> [String: ObservedRepository] {
        var repositoriesByKey: [String: ObservedRepository] = [:]

        for repository in observedRepositories {
            repositoriesByKey[repository.normalizedLookupKey] = repository
        }

        for pullRequest in pullRequests where repositoriesByKey[pullRequest.repository.normalizedLookupKey] == nil {
            repositoriesByKey[pullRequest.repository.normalizedLookupKey] = pullRequest.repository
        }

        return repositoriesByKey
    }

    static func isPullRequestOrderedBefore(_ lhs: PullRequestItem, _ rhs: PullRequestItem) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }

        return lhs.number > rhs.number
    }

    static func isSectionOrderedBefore(_ lhs: RepositorySection, _ rhs: RepositorySection) -> Bool {
        let lhsMostRecent = lhs.pullRequests.first
        let rhsMostRecent = rhs.pullRequests.first

        if lhsMostRecent?.updatedAt != rhsMostRecent?.updatedAt {
            return (lhsMostRecent?.updatedAt ?? .distantPast) > (rhsMostRecent?.updatedAt ?? .distantPast)
        }

        let nameComparison = lhs.repository.fullName.localizedCaseInsensitiveCompare(rhs.repository.fullName)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }

        return (lhsMostRecent?.number ?? 0) > (rhsMostRecent?.number ?? 0)
    }
}
