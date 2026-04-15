import Foundation

struct PullRequestSearchResponseDTO: Decodable {
    let data: SearchDataDTO

    struct SearchDataDTO: Decodable {
        let search: SearchResultDTO
    }

    struct SearchResultDTO: Decodable {
        let nodes: [SearchNodeDTO]
    }

    struct SearchNodeDTO: Decodable {
        let typename: String
        let number: Int?
        let title: String?
        let url: URL?
        let author: AuthorDTO?
        let isDraft: Bool?
        let updatedAt: Date?
        let reviewDecision: String?
        let reviewThreads: ReviewThreadConnectionDTO?
        let statusCheckRollup: StatusCheckRollupDTO?

        enum CodingKeys: String, CodingKey {
            case typename = "__typename"
            case number
            case title
            case url
            case author
            case isDraft
            case updatedAt
            case reviewDecision
            case reviewThreads
            case statusCheckRollup
        }
    }

    struct ReviewThreadConnectionDTO: Decodable {
        let nodes: [ReviewThreadDTO]
    }

    struct ReviewThreadDTO: Decodable {
        let isResolved: Bool
        let isOutdated: Bool
        let path: String?
        let comments: ReviewCommentConnectionDTO?
    }

    struct ReviewCommentConnectionDTO: Decodable {
        let nodes: [ReviewCommentDTO]
    }

    struct ReviewCommentDTO: Decodable {
        let url: URL?
        let bodyText: String?
        let author: AuthorDTO?
    }

    struct AuthorDTO: Decodable {
        let login: String?
    }

    struct StatusCheckRollupDTO: Decodable {
        let state: String?
        let contexts: CheckContextConnectionDTO
    }

    struct CheckContextConnectionDTO: Decodable {
        let nodes: [CheckContextNodeDTO]
    }

    struct CheckContextNodeDTO: Decodable {
        let typename: String
        let name: String?
        let status: String?
        let conclusion: String?
        let detailsUrl: URL?
        let checkSuite: CheckSuiteDTO?
        let context: String?
        let state: String?
        let targetUrl: URL?
        let description: String?

        enum CodingKeys: String, CodingKey {
            case typename = "__typename"
            case name
            case status
            case conclusion
            case detailsUrl
            case checkSuite
            case context
            case state
            case targetUrl
            case description
        }
    }

    struct CheckSuiteDTO: Decodable {
        let app: AppDTO?
        let workflowRun: WorkflowRunDTO?
    }

    struct AppDTO: Decodable {
        let name: String?
        let slug: String?
    }

    struct WorkflowRunDTO: Decodable {
        let databaseId: Int
        let url: URL?
        let workflow: WorkflowDTO?
    }

    struct WorkflowDTO: Decodable {
        let name: String?
    }
}
