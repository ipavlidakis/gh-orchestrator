import Foundation

struct ActionsWorkflowRunsResponseDTO: Decodable {
    let totalCount: Int?
    let workflowRuns: [WorkflowRunDTO]

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case workflowRuns = "workflow_runs"
    }

    struct WorkflowRunDTO: Decodable {
        let id: Int
        let name: String?
        let status: String?
        let conclusion: String?
        let htmlURL: URL?
        let createdAt: Date?
        let updatedAt: Date?
        let runStartedAt: Date?

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case status
            case conclusion
            case htmlURL = "html_url"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
            case runStartedAt = "run_started_at"
        }
    }
}
