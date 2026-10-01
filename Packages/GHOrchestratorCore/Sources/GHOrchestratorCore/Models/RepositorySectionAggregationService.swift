import Foundation

public protocol RepositorySectionAggregating: Sendable {
    func makeSections(
        observedRepositories: [ObservedRepository],
        pullRequests: [PullRequestItem],
        sortOrder: PullRequestSortOrder,
        repositorySortOrder: RepositorySortOrder
    ) -> [RepositorySection]
}

public extension RepositorySectionAggregating {
    func makeSections(
        observedRepositories: [ObservedRepository],
        pullRequests: [PullRequestItem],
        sortOrder: PullRequestSortOrder
    ) -> [RepositorySection] {
        makeSections(
            observedRepositories: observedRepositories,
            pullRequests: pullRequests,
            sortOrder: sortOrder,
            repositorySortOrder: .lastModifiedNewestFirst
        )
    }
}

public struct RepositorySectionAggregationService: RepositorySectionAggregating {
    public init() {}

    public func makeSections(
        observedRepositories: [ObservedRepository],
        pullRequests: [PullRequestItem],
        sortOrder: PullRequestSortOrder = .title,
        repositorySortOrder: RepositorySortOrder = .lastModifiedNewestFirst
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
                pullRequests: grouped.sorted { Self.isPullRequestOrderedBefore($0, $1, sortOrder: sortOrder) }
            )
        }

        return unsortedSections.sorted { Self.isSectionOrderedBefore($0, $1, order: repositorySortOrder) }
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

    static func isPullRequestOrderedBefore(_ lhs: PullRequestItem, _ rhs: PullRequestItem, sortOrder: PullRequestSortOrder) -> Bool {
        if sortOrder != .title {
            switch (lhs.createdAt, rhs.createdAt) {
            case let (left?, right?) where left != right:
                return sortOrder == .createdOldestFirst ? left < right : left > right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return sortOrder == .createdOldestFirst ? lhs.number < rhs.number : lhs.number > rhs.number
            }
        }

        let titleComparison = lhs.title.localizedStandardCompare(rhs.title)
        if titleComparison != .orderedSame {
            return titleComparison == .orderedAscending
        }

        return lhs.number > rhs.number
    }

    static func isSectionOrderedBefore(
        _ lhs: RepositorySection,
        _ rhs: RepositorySection,
        order: RepositorySortOrder = .lastModifiedNewestFirst
    ) -> Bool {
        func compare(_ left: String, _ right: String) -> ComparisonResult {
            left.localizedStandardCompare(right)
        }

        switch order {
        case .nameAscending, .nameDescending:
            let result = compare(lhs.repository.name, rhs.repository.name)
            if result != .orderedSame {
                return (result == .orderedAscending) == (order == .nameAscending)
            }
        case .teamAscending, .teamDescending:
            let result = compare(lhs.repository.owner, rhs.repository.owner)
            if result != .orderedSame {
                return (result == .orderedAscending) == (order == .teamAscending)
            }
        case .lastModifiedNewestFirst, .lastModifiedOldestFirst:
            let left = lhs.pullRequests.map(\.updatedAt).max() ?? .distantPast
            let right = rhs.pullRequests.map(\.updatedAt).max() ?? .distantPast
            if left != right {
                return order == .lastModifiedNewestFirst ? left > right : left < right
            }
        }

        // Stable tie-breakers keep equal keys in a predictable order.
        let nameComparison = lhs.repository.fullName.localizedCaseInsensitiveCompare(rhs.repository.fullName)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }

        let lhsNumber = lhs.pullRequests.max { $0.updatedAt < $1.updatedAt }?.number ?? 0
        let rhsNumber = rhs.pullRequests.max { $0.updatedAt < $1.updatedAt }?.number ?? 0
        return lhsNumber > rhsNumber
    }
}
