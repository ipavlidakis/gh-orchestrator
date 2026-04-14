import Foundation

struct ActionsJobsResponseDTO: Decodable {
    let jobs: [JobDTO]

    struct JobDTO: Decodable {
        let id: Int
        let name: String
        let htmlURL: URL?
        let status: String
        let conclusion: String?
        let startedAt: Date?
        let completedAt: Date?
        let steps: [StepDTO]?

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case htmlURL = "html_url"
            case status
            case conclusion
            case startedAt = "started_at"
            case completedAt = "completed_at"
            case steps
        }
    }

    struct StepDTO: Decodable {
        let number: Int
        let name: String
        let status: String
        let conclusion: String?
    }
}
