import Foundation
import XCTest
@testable import GHOrchestratorCore

final class RepositorySectionAggregationServiceTests: XCTestCase {
    func testCreationOrderingUsesCreationDatesWithUnknownDatesLast() {
        let repository = ObservedRepository(owner: "example", name: "repo")
        let items = [
            pullRequest(repository: repository, number: 90, updatedAt: date(900), title: "Alpha", createdAt: date(100)),
            pullRequest(repository: repository, number: 2, updatedAt: date(10), title: "Zebra", createdAt: date(200)),
            pullRequest(repository: repository, number: 100, updatedAt: date(1000), title: "Unknown")
        ]
        let service = RepositorySectionAggregationService()
        for (order, expected) in [(PullRequestSortOrder.createdNewestFirst, [2, 90, 100]), (.createdOldestFirst, [90, 2, 100]), (.title, [90, 100, 2])] {
            let sections = service.makeSections(observedRepositories: [repository], pullRequests: items, sortOrder: order)
            XCTAssertEqual(sections.first?.pullRequests.map(\.number), expected)
        }
    }

    func testMakeSectionsOrdersRepositoriesByMostRecentlyUpdatedPullRequest() {
        let firstRepository = ObservedRepository(owner: "openai", name: "codex")
        let secondRepository = ObservedRepository(owner: "swiftlang", name: "swift")

        let service = RepositorySectionAggregationService()
        let sections = service.makeSections(
            observedRepositories: [firstRepository, secondRepository],
            pullRequests: [
                pullRequest(repository: firstRepository, number: 10, updatedAt: date(100)),
                pullRequest(repository: secondRepository, number: 20, updatedAt: date(200))
            ]
        )

        XCTAssertEqual(sections.map(\.repository.fullName), ["swiftlang/swift", "openai/codex"])
        XCTAssertEqual(sections.first?.pullRequests.map(\.number), [20])
    }

    func testMakeSectionsUsesDeterministicTieBreakersForMatchingTimestamps() {
        let alphaRepository = ObservedRepository(owner: "alpha", name: "repo")
        let betaRepository = ObservedRepository(owner: "beta", name: "repo")
        let timestamp = date(500)

        let service = RepositorySectionAggregationService()
        let sections = service.makeSections(
            observedRepositories: [betaRepository, alphaRepository],
            pullRequests: [
                pullRequest(repository: betaRepository, number: 1, updatedAt: timestamp),
                pullRequest(repository: alphaRepository, number: 99, updatedAt: timestamp, title: "Same title"),
                pullRequest(repository: alphaRepository, number: 3, updatedAt: timestamp, title: "Same title")
            ]
        )

        XCTAssertEqual(sections.map(\.repository.fullName), ["alpha/repo", "beta/repo"])
        XCTAssertEqual(sections[0].pullRequests.map(\.number), [99, 3])
    }

    func testMakeSectionsDoesNotEmitObservedRepositoriesWithoutPullRequests() {
        let activeRepository = ObservedRepository(owner: "openai", name: "codex")
        let emptyRepository = ObservedRepository(owner: "openai", name: "missing")

        let service = RepositorySectionAggregationService()
        let sections = service.makeSections(
            observedRepositories: [activeRepository, emptyRepository],
            pullRequests: [
                pullRequest(repository: activeRepository, number: 10, updatedAt: date(100))
            ]
        )

        XCTAssertEqual(sections.map(\.repository.fullName), ["openai/codex"])
    }

    func testMakeSectionsUsesStableNaturalTitleOrderWithoutChangingRepositoryActivityOrder() {
        let alpha = ObservedRepository(owner: "alpha", name: "repo")
        let beta = ObservedRepository(owner: "beta", name: "repo")
        let service = RepositorySectionAggregationService()

        for timestamps in [[1000.0, 100, 200, 300], [900, 400, 800, 700]] {
            let sections = service.makeSections(
                observedRepositories: [beta, alpha],
                pullRequests: [
                    pullRequest(repository: alpha, number: 1, updatedAt: date(timestamps[0]), title: "Zebra"),
                    pullRequest(repository: beta, number: 5, updatedAt: date(500), title: "Other"),
                    pullRequest(repository: alpha, number: 2, updatedAt: date(timestamps[1]), title: "alpha"),
                    pullRequest(repository: alpha, number: 3, updatedAt: date(timestamps[2]), title: "Build 10"),
                    pullRequest(repository: alpha, number: 4, updatedAt: date(timestamps[3]), title: "build 2")
                ]
            )

            XCTAssertEqual(sections.map(\.repository.fullName), ["alpha/repo", "beta/repo"])
            XCTAssertEqual(sections[0].pullRequests.map(\.number), [2, 4, 3, 1])
        }
    }
}

private func pullRequest(
    repository: ObservedRepository,
    number: Int,
    updatedAt: Date,
    title: String? = nil,
    createdAt: Date? = nil
) -> PullRequestItem {
    PullRequestItem(
        repository: repository,
        number: number,
        title: title ?? "PR #\(number)",
        url: URL(string: "https://github.com/\(repository.fullName)/pull/\(number)")!,
        isDraft: false,
        createdAt: createdAt,
        updatedAt: updatedAt,
        reviewStatus: .none,
        unresolvedReviewThreadCount: 0,
        checkRollupState: .none
    )
}

private func date(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: seconds)
}
