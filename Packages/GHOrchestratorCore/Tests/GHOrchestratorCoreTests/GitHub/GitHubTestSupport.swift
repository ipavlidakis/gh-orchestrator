import Foundation
@testable import GHOrchestratorCore

actor StubGitHubHTTPTransport: GitHubHTTPTransport {
    enum Result {
        case success(data: Data, response: URLResponse)
        case failure(Error)
    }

    private var results: [Result]
    private var requests: [URLRequest] = []

    init(results: [Result]) {
        self.results = results
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)

        guard !results.isEmpty else {
            throw StubGitHubTransportError.noQueuedResponse
        }

        let result = results.removeFirst()

        switch result {
        case .success(let data, let response):
            return (data, response)
        case .failure(let error):
            throw error
        }
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}

enum StubGitHubTransportError: Error {
    case noQueuedResponse
}

final class StubGitHubCredentialStore: GitHubCredentialStore, @unchecked Sendable {
    private var session: GitHubSession?

    init(session: GitHubSession? = GitHubSession(accessToken: "access-token", tokenType: "bearer")) {
        self.session = session
    }

    func loadSession() throws -> GitHubSession? {
        session
    }

    func saveSession(_ session: GitHubSession) throws {
        self.session = session
    }

    func deleteSession() throws {
        session = nil
    }
}

func makeHTTPResponse(
    url: String,
    statusCode: Int,
    headerFields: [String: String]? = nil
) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: url)!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: headerFields
    )!
}

func fixtureData(named name: String, subdirectory: String) -> Data {
    let directURL = Bundle.module.url(forResource: name, withExtension: "json")
    let nestedURL = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: subdirectory)
    let fixturesURL = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/\(subdirectory)")

    guard let url = directURL ?? nestedURL ?? fixturesURL else {
        fatalError("Missing fixture \(name).json in \(subdirectory)")
    }

    guard let data = try? Data(contentsOf: url) else {
        fatalError("Unable to load fixture \(name).json from \(subdirectory)")
    }

    return data
}
