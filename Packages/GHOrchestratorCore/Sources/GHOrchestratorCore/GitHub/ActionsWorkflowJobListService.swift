import Foundation

public protocol ActionsWorkflowJobListing: Sendable {
    func listJobNames(
        repository: ObservedRepository,
        workflow: ActionsWorkflowItem
    ) async throws -> [String]
}

public enum ActionsWorkflowJobListError: Error, Equatable, Sendable {
    case requestFailed(repository: ObservedRepository, workflowName: String, message: String)
    case invalidResponse(repository: ObservedRepository, workflowName: String, message: String)
}

extension ActionsWorkflowJobListError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .requestFailed(let repository, let workflowName, let message):
            return "Failed to load Actions jobs for \(workflowName) in \(repository.fullName): \(message)"
        case .invalidResponse(let repository, let workflowName, let message):
            return "Received an invalid Actions jobs response for \(workflowName) in \(repository.fullName): \(message)"
        }
    }
}

public struct ActionsWorkflowJobListService: ActionsWorkflowJobListing {
    public let client: any GitHubAPIClient
    public let runSampleLimit: Int

    public init(
        client: any GitHubAPIClient = URLSessionGitHubAPIClient(),
        runSampleLimit: Int = 5
    ) {
        self.client = client
        self.runSampleLimit = max(runSampleLimit, 1)
    }

    public func listJobNames(
        repository: ObservedRepository,
        workflow: ActionsWorkflowItem
    ) async throws -> [String] {
        do {
            let runsResponse: ActionsWorkflowRunsResponseDTO = try await client.get(
                "/repos/\(repository.fullName)/actions/workflows/\(workflow.id)/runs"
            )

            let runIDs = Array(runsResponse.workflowRuns.map(\.id).prefix(runSampleLimit))
            guard !runIDs.isEmpty else {
                return []
            }

            let jobNames = try await withThrowingTaskGroup(of: [String].self) { group in
                for runID in runIDs {
                    group.addTask {
                        let jobsResponse: ActionsJobsResponseDTO = try await client.get(
                            "/repos/\(repository.fullName)/actions/runs/\(runID)/jobs"
                        )

                        return jobsResponse.jobs.map(\.name)
                    }
                }

                var names: [String] = []
                for try await runNames in group {
                    names.append(contentsOf: runNames)
                }

                return names
            }

            return normalizedJobNames(jobNames)
        } catch let error as GitHubAPIClientError {
            switch error {
            case .invalidResponse(let message):
                throw ActionsWorkflowJobListError.invalidResponse(
                    repository: repository,
                    workflowName: workflow.name,
                    message: message
                )
            default:
                throw ActionsWorkflowJobListError.requestFailed(
                    repository: repository,
                    workflowName: workflow.name,
                    message: error.displayMessage
                )
            }
        } catch let error as ActionsWorkflowJobListError {
            throw error
        } catch {
            throw ActionsWorkflowJobListError.requestFailed(
                repository: repository,
                workflowName: workflow.name,
                message: error.localizedDescription
            )
        }
    }

    private func normalizedJobNames(_ jobNames: [String]) -> [String] {
        var displayNamesByNormalizedName: [String: String] = [:]

        for jobName in jobNames {
            let trimmedName = jobName.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedName = RepositoryNotificationSettings.normalizedWorkflowJobName(trimmedName)

            guard !normalizedName.isEmpty else {
                continue
            }

            displayNamesByNormalizedName[normalizedName] = displayNamesByNormalizedName[normalizedName] ?? trimmedName
        }

        return displayNamesByNormalizedName.values.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }
}
