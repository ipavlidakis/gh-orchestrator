import Foundation
import XCTest
@testable import GHOrchestratorCore

final class RepositorySectionAggregationServiceTests: XCTestCase {
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
                pullRequest(repository: alphaRepository, number: 99, updatedAt: timestamp),
                pullRequest(repository: alphaRepository, number: 3, updatedAt: timestamp)
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
}

private func pullRequest(
    repository: ObservedRepository,
    number: Int,
    updatedAt: Date
) -> PullRequestItem {
    PullRequestItem(
        repository: repository,
        number: number,
        title: "PR #\(number)",
        url: URL(string: "https://github.com/\(repository.fullName)/pull/\(number)")!,
        isDraft: false,
        updatedAt: updatedAt,
        reviewStatus: .none,
        unresolvedReviewThreadCount: 0,
        checkRollupState: .none
    )
}

private func date(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: seconds)
}
