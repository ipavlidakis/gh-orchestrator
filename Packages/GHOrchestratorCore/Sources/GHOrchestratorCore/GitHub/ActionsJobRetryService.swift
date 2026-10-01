import Foundation

public protocol ActionsJobRetrying: Sendable {
    func rerunJob(
        repository: ObservedRepository,
        jobID: Int
    ) async throws
}

public enum ActionsJobRetryError: Error, Equatable, Sendable {
    case rerunFailed(repository: ObservedRepository, jobID: Int, message: String)
}

extension ActionsJobRetryError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .rerunFailed(let repository, _, let message):
            return "Failed to retry Actions job for \(repository.fullName): \(message)"
        }
    }
}

public struct ActionsJobRetryService: ActionsJobRetrying {
    public let client: any GitHubAPIClient

    public init(client: any GitHubAPIClient = URLSessionGitHubAPIClient()) {
        self.client = client
    }

    public func rerunJob(
        repository: ObservedRepository,
        jobID: Int
    ) async throws {
        do {
            try await client.rerunWorkflowJob(
                repository: repository,
                jobID: jobID
            )
        } catch let error as GitHubAPIClientError {
            throw ActionsJobRetryError.rerunFailed(
                repository: repository,
                jobID: jobID,
                message: retryFailureMessage(for: error)
            )
        } catch {
            throw ActionsJobRetryError.rerunFailed(
                repository: repository,
                jobID: jobID,
                message: error.localizedDescription
            )
        }
    }
}

private func retryFailureMessage(for error: GitHubAPIClientError) -> String {
    switch error {
    case .missingSession:
        return "No GitHub session is available. Sign in again and retry."
    case .requestFailed(statusCode: 401, _):
        return "GitHub rejected the retry request. Sign in again and retry."
    case .requestFailed(statusCode: 403, let message):
        let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = detail.isEmpty ? "" : " GitHub said: \(detail)"
        return "GitHub denied the retry request.\(reason) Jobs can only be re-run after the whole workflow run finishes, and the signed-in account needs write access (and organization approval for this app)."
    default:
        return error.displayMessage
    }
}
