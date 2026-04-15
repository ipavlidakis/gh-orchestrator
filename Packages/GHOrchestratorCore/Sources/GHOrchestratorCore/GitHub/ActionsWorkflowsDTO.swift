import Foundation

struct ActionsWorkflowsResponseDTO: Decodable {
    let workflows: [WorkflowDTO]

    struct WorkflowDTO: Decodable {
        let id: Int
        let name: String
        let path: String
        let state: String
        let htmlURL: URL?
        let badgeURL: URL?

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case path
            case state
            case htmlURL = "html_url"
            case badgeURL = "badge_url"
        }
    }
}
