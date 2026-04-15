import Foundation

public protocol SoftwareUpdateChecking: Sendable {
    func checkForUpdates(currentVersion: String) async throws -> SoftwareUpdateCheckResult
}

public enum SoftwareUpdateCheckResult: Equatable, Sendable {
    case upToDate(currentVersion: String)
    case updateAvailable(SoftwareUpdate)
}

public struct SoftwareUpdate: Equatable, Identifiable, Sendable {
    public var id: String { version }

    public let version: String
    public let releaseName: String
    public let releaseNotes: String?
    public let releaseURL: URL
    public let publishedAt: Date?
    public let downloadAsset: SoftwareUpdateAsset
    public let checksumAsset: SoftwareUpdateAsset

    public init(
        version: String,
        releaseName: String,
        releaseNotes: String? = nil,
        releaseURL: URL,
        publishedAt: Date? = nil,
        downloadAsset: SoftwareUpdateAsset,
        checksumAsset: SoftwareUpdateAsset
    ) {
        self.version = version
        self.releaseName = releaseName
        self.releaseNotes = releaseNotes
        self.releaseURL = releaseURL
        self.publishedAt = publishedAt
        self.downloadAsset = downloadAsset
        self.checksumAsset = checksumAsset
    }
}

public struct SoftwareUpdateAsset: Equatable, Sendable {
    public let name: String
    public let url: URL
    public let size: Int
    public let contentType: String?

    public init(
        name: String,
        url: URL,
        size: Int,
        contentType: String? = nil
    ) {
        self.name = name
        self.url = url
        self.size = size
        self.contentType = contentType
    }
}

public struct GitHubReleaseUpdateChecker: SoftwareUpdateChecking {
    public let owner: String
    public let repository: String
    public let transport: any GitHubHTTPTransport
    public let apiBaseURL: URL

    public init(
        owner: String = "ipavlidakis",
        repository: String = "gh-orchestrator",
        transport: any GitHubHTTPTransport = URLSessionGitHubHTTPTransport(),
        apiBaseURL: URL = URLSessionGitHubAPIClient.defaultAPIBaseURL
    ) {
        self.owner = owner
        self.repository = repository
        self.transport = transport
        self.apiBaseURL = apiBaseURL
    }

    public func checkForUpdates(currentVersion: String) async throws -> SoftwareUpdateCheckResult {
        guard let current = SoftwareVersion(currentVersion) else {
            throw SoftwareUpdateCheckError.invalidCurrentVersion(currentVersion)
        }

        let release = try await latestRelease()

        guard let releaseVersion = SoftwareVersion(release.tagName) else {
            throw SoftwareUpdateCheckError.invalidReleaseVersion(release.tagName)
        }

        guard releaseVersion > current else {
            return .upToDate(currentVersion: currentVersion)
        }

        return .updateAvailable(
            try update(from: release)
        )
    }

    private func latestRelease() async throws -> GitHubReleaseDTO {
        var request = URLRequest(url: latestReleaseURL())
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let responseData: Data
        let response: URLResponse

        do {
            (responseData, response) = try await transport.data(for: request)
        } catch {
            throw SoftwareUpdateCheckError.transportFailed(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SoftwareUpdateCheckError.invalidResponse("Expected an HTTPURLResponse from GitHub.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = GitHubAPIErrorMessageFormatter.normalize(data: responseData)
            throw SoftwareUpdateCheckError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: message.isEmpty ? "GitHub release lookup failed with status code \(httpResponse.statusCode)." : message
            )
        }

        do {
            return try GitHubJSONCoders.restDecoder.decode(GitHubReleaseDTO.self, from: responseData)
        } catch {
            throw SoftwareUpdateCheckError.invalidResponse(error.localizedDescription)
        }
    }

    private func latestReleaseURL() -> URL {
        apiBaseURL
            .appendingPathComponent("repos", isDirectory: true)
            .appendingPathComponent(owner, isDirectory: true)
            .appendingPathComponent(repository, isDirectory: true)
            .appendingPathComponent("releases", isDirectory: true)
            .appendingPathComponent("latest", isDirectory: false)
    }

    private func update(from release: GitHubReleaseDTO) throws -> SoftwareUpdate {
        guard let dmgAsset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) else {
            throw SoftwareUpdateCheckError.missingDMGAsset(release.tagName)
        }

        let expectedChecksumName = "\(dmgAsset.name).sha256.txt".lowercased()
        let checksumAsset = release.assets.first {
            $0.name.lowercased() == expectedChecksumName
        } ?? release.assets.first {
            $0.name.lowercased().hasSuffix(".sha256.txt")
        }

        guard let checksumAsset else {
            throw SoftwareUpdateCheckError.missingChecksumAsset(dmgAsset.name)
        }

        let displayVersion = Self.displayVersion(from: release.tagName)
        let releaseName = release.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let releaseNotes = release.body?.trimmingCharacters(in: .whitespacesAndNewlines)

        return SoftwareUpdate(
            version: displayVersion,
            releaseName: releaseName.flatMap { $0.isEmpty ? nil : $0 } ?? displayVersion,
            releaseNotes: releaseNotes?.isEmpty == false ? releaseNotes : nil,
            releaseURL: release.htmlURL,
            publishedAt: release.publishedAt,
            downloadAsset: dmgAsset.updateAsset,
            checksumAsset: checksumAsset.updateAsset
        )
    }

    private static func displayVersion(from tagName: String) -> String {
        let trimmed = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("v") {
            return String(trimmed.dropFirst())
        }

        return trimmed
    }
}

public enum SoftwareUpdateCheckError: Error, Equatable, LocalizedError, Sendable {
    case invalidCurrentVersion(String)
    case invalidReleaseVersion(String)
    case missingDMGAsset(String)
    case missingChecksumAsset(String)
    case transportFailed(String)
    case requestFailed(statusCode: Int, message: String)
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCurrentVersion(let version):
            return "The current app version is not a valid release version: \(version)."
        case .invalidReleaseVersion(let version):
            return "The latest GitHub Release tag is not a valid release version: \(version)."
        case .missingDMGAsset(let tagName):
            return "GitHub Release \(tagName) does not include a DMG asset."
        case .missingChecksumAsset(let assetName):
            return "GitHub Release asset \(assetName) does not include a SHA-256 checksum asset."
        case .transportFailed(let message):
            return "GitHub release lookup failed: \(message)"
        case .requestFailed(let statusCode, let message):
            return "GitHub release lookup failed with status code \(statusCode): \(message)"
        case .invalidResponse(let message):
            return "GitHub returned an invalid release response: \(message)"
        }
    }
}

private struct GitHubReleaseDTO: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let publishedAt: Date?
    let assets: [GitHubReleaseAssetDTO]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case assets
    }
}

private struct GitHubReleaseAssetDTO: Decodable {
    let name: String
    let browserDownloadURL: URL
    let size: Int
    let contentType: String?

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
        case contentType = "content_type"
    }

    var updateAsset: SoftwareUpdateAsset {
        SoftwareUpdateAsset(
            name: name,
            url: browserDownloadURL,
            size: size,
            contentType: contentType
        )
    }
}

private struct SoftwareVersion: Comparable {
    let components: [Int]

    init?(_ rawValue: String) {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("v") {
            value = String(value.dropFirst())
        }

        let baseVersion = value
            .split(whereSeparator: { $0 == "-" || $0 == "+" })
            .first

        guard let baseVersion else {
            return nil
        }

        let parsedComponents = baseVersion
            .split(separator: ".")
            .map(String.init)

        guard !parsedComponents.isEmpty else {
            return nil
        }

        var components: [Int] = []
        for component in parsedComponents {
            guard let value = Int(component) else {
                return nil
            }

            components.append(value)
        }

        self.components = components
    }

    static func < (lhs: SoftwareVersion, rhs: SoftwareVersion) -> Bool {
        let maxCount = max(lhs.components.count, rhs.components.count)

        for index in 0..<maxCount {
            let lhsComponent = index < lhs.components.count ? lhs.components[index] : 0
            let rhsComponent = index < rhs.components.count ? rhs.components[index] : 0

            if lhsComponent != rhsComponent {
                return lhsComponent < rhsComponent
            }
        }

        return false
    }
}
