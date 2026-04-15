import Foundation

struct ActionsWorkflowRunsResponseDTO: Decodable {
    let workflowRuns: [WorkflowRunDTO]

    enum CodingKeys: String, CodingKey {
        case workflowRuns = "workflow_runs"
    }

    struct WorkflowRunDTO: Decodable {
        let id: Int
        let name: String?
        let status: String?
        let conclusion: String?
        let htmlURL: URL?

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case status
            case conclusion
            case htmlURL = "html_url"
        }
    }
}
