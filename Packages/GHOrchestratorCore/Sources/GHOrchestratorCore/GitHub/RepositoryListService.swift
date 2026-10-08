import Foundation

public protocol RepositoryListing: Sendable {
    func listRepositories() async throws -> [ObservedRepository]
}

public struct RepositoryListService: RepositoryListing {
    public let client: any GitHubAPIClient

    public init(client: any GitHubAPIClient = URLSessionGitHubAPIClient()) {
        self.client = client
    }

    public func listRepositories() async throws -> [ObservedRepository] {
        var repositories: [ObservedRepository] = []
        var seenIDs = Set<String>()
        var page = 1
        while true {
            try Task.checkCancellation()
            let response: [RepositoryDTO] = try await client.get(
                "/user/repos?affiliation=owner,collaborator,organization_member&sort=full_name&per_page=100&page=\(page)"
            )
            let previousCount = repositories.count
            for item in response {
                guard let repository = ObservedRepository(rawValue: item.fullName) else {
                    throw GitHubAPIClientError.invalidResponse(message: "GitHub returned an invalid repository name.")
                }
                if seenIDs.insert(repository.normalizedLookupKey).inserted {
                    repositories.append(repository)
                }
            }
            guard response.count == 100 else { break }
            guard repositories.count > previousCount else {
                throw GitHubAPIClientError.invalidResponse(message: "GitHub repeated a repository page. Please refresh the list.")
            }
            page += 1
        }
        return repositories.sorted { $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending }
    }
}

private struct RepositoryDTO: Decodable {
    let fullName: String

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
    }
}
