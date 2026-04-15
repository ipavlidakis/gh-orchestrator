import Foundation
import XCTest
@testable import GHOrchestrator
import GHOrchestratorCore

@MainActor
final class GitHubRequestLogModelTests: XCTestCase {
    func testRecordsNewestRequestsFirstAndTracksLatestQuota() async {
        let model = GitHubRequestLogModel(maximumRecordCount: 2)
        let firstRateLimit = GitHubRateLimitStatus(
            limit: 5_000,
            remaining: 4_999,
            used: 1,
            resetDate: Date(timeIntervalSince1970: 1_735_689_600),
            resource: "core"
        )
        let secondRateLimit = GitHubRateLimitStatus(
            limit: 5_000,
            remaining: 4_998,
            used: 2,
            resetDate: Date(timeIntervalSince1970: 1_735_689_700),
            resource: "graphql"
        )

        await model.record(
            GitHubRequestRecord(
                method: "GET",
                endpoint: "api.github.com/user",
                statusCode: 200,
                rateLimit: firstRateLimit,
                errorMessage: nil
            )
        )
        await model.record(
            GitHubRequestRecord(
                method: "POST",
                endpoint: "api.github.com/graphql",
                statusCode: 200,
                rateLimit: secondRateLimit,
                errorMessage: nil
            )
        )
        await model.record(
            GitHubRequestRecord(
                method: "POST",
                endpoint: "github.com/login/oauth/access_token",
                statusCode: 200,
                rateLimit: nil,
                errorMessage: nil
            )
        )

        XCTAssertEqual(
            model.records.map(\.endpoint),
            [
                "github.com/login/oauth/access_token",
                "api.github.com/graphql",
            ]
        )
        XCTAssertEqual(model.latestRateLimit, secondRateLimit)
        XCTAssertEqual(model.latestRateLimitsByResource, [secondRateLimit])
        XCTAssertEqual(model.requestsWithRateLimitHeaderCount, 1)

        model.clear()

        XCTAssertTrue(model.records.isEmpty)
        XCTAssertNil(model.latestRateLimit)
        XCTAssertTrue(model.latestRateLimitsByResource.isEmpty)
    }

    func testTracksLatestQuotaPerResource() async {
        let model = GitHubRequestLogModel()
        let olderCoreRateLimit = GitHubRateLimitStatus(
            limit: 5_000,
            remaining: 100,
            used: 4_900,
            resetDate: Date(timeIntervalSince1970: 1_735_689_600),
            resource: "core"
        )
        let graphQLRateLimit = GitHubRateLimitStatus(
            limit: 5_000,
            remaining: 850,
            used: 4_150,
            resetDate: Date(timeIntervalSince1970: 1_735_689_700),
            resource: "graphql"
        )
        let latestCoreRateLimit = GitHubRateLimitStatus(
            limit: 5_000,
            remaining: 6,
            used: 4_994,
            resetDate: Date(timeIntervalSince1970: 1_735_689_800),
            resource: "core"
        )

        await model.record(
            GitHubRequestRecord(
                method: "GET",
                endpoint: "api.github.com/user",
                statusCode: 200,
                rateLimit: olderCoreRateLimit,
                errorMessage: nil
            )
        )
        await model.record(
            GitHubRequestRecord(
                method: "POST",
                endpoint: "api.github.com/graphql",
                statusCode: 200,
                rateLimit: graphQLRateLimit,
                errorMessage: nil
            )
        )
        await model.record(
            GitHubRequestRecord(
                method: "GET",
                endpoint: "api.github.com/repos/openai/codex/actions/runs/1/jobs",
                statusCode: 200,
                rateLimit: latestCoreRateLimit,
                errorMessage: nil
            )
        )

        XCTAssertEqual(
            model.latestRateLimitsByResource,
            [
                latestCoreRateLimit,
                graphQLRateLimit,
            ]
        )
    }
}
