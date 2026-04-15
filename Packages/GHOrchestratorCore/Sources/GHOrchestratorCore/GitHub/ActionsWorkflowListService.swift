import Foundation

public protocol ActionsWorkflowListing: Sendable {
    func listWorkflows(repository: ObservedRepository) async throws -> [ActionsWorkflowItem]
}

public struct ActionsWorkflowItem: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let path: String
    public let state: String
    public let htmlURL: URL?
    public let badgeURL: URL?

    public init(
        id: Int,
        name: String,
        path: String,
        state: String,
        htmlURL: URL? = nil,
        badgeURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.state = state
        self.htmlURL = htmlURL
        self.badgeURL = badgeURL
    }
}

public enum ActionsWorkflowListError: Error, Equatable, Sendable {
    case requestFailed(repository: ObservedRepository, message: String)
    case invalidResponse(repository: ObservedRepository, message: String)
}

extension ActionsWorkflowListError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .requestFailed(let repository, let message):
            return "Failed to load Actions workflows for \(repository.fullName): \(message)"
        case .invalidResponse(let repository, let message):
            return "Received an invalid Actions workflows response for \(repository.fullName): \(message)"
        }
    }
}

public struct ActionsWorkflowListService: ActionsWorkflowListing {
    public let client: any GitHubAPIClient

    public init(client: any GitHubAPIClient = URLSessionGitHubAPIClient()) {
        self.client = client
    }

    public func listWorkflows(repository: ObservedRepository) async throws -> [ActionsWorkflowItem] {
        do {
            let response: ActionsWorkflowsResponseDTO = try await client.get(
                "/repos/\(repository.fullName)/actions/workflows"
            )

            return deduplicatedWorkflowItems(
                response.workflows.compactMap { workflow in
                    let name = workflow.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else {
                        return nil
                    }

                    return ActionsWorkflowItem(
                        id: workflow.id,
                        name: name,
                        path: workflow.path,
                        state: workflow.state,
                        htmlURL: workflow.htmlURL,
                        badgeURL: workflow.badgeURL
                    )
                }
            )
        } catch let error as GitHubAPIClientError {
            switch error {
            case .invalidResponse(let message):
                throw ActionsWorkflowListError.invalidResponse(
                    repository: repository,
                    message: message
                )
            default:
                throw ActionsWorkflowListError.requestFailed(
                    repository: repository,
                    message: error.displayMessage
                )
            }
        } catch {
            throw ActionsWorkflowListError.requestFailed(
                repository: repository,
                message: error.localizedDescription
            )
        }
    }

    private func deduplicatedWorkflowItems(_ workflows: [ActionsWorkflowItem]) -> [ActionsWorkflowItem] {
        var seenNames = Set<String>()
        var deduplicatedWorkflows: [ActionsWorkflowItem] = []

        for workflow in workflows.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            let normalizedName = RepositoryNotificationSettings.normalizedWorkflowName(workflow.name)
            if seenNames.insert(normalizedName).inserted {
                deduplicatedWorkflows.append(workflow)
            }
        }

        return deduplicatedWorkflows
    }
}
