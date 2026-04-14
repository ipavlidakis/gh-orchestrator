import Foundation
import ProjectDescription

let gitHubOAuthClientID = LocalGitHubOAuthConfiguration.clientID
let gitHubOAuthClientSecret = LocalGitHubOAuthConfiguration.clientSecret

private enum LocalGitHubOAuthConfiguration {
    private static let localConfigURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Config", isDirectory: true)
        .appendingPathComponent("GitHubOAuth.local.json", isDirectory: false)

    static let clientID: String = {
        if let localClientID = readPayload(from: localConfigURL)?.clientID {
            return localClientID
        }

        return ProcessInfo.processInfo.environment["GH_ORCHESTRATOR_GITHUB_CLIENT_ID"] ?? ""
    }()

    static let clientSecret: String = {
        if let localClientSecret = readPayload(from: localConfigURL)?.clientSecret {
            return localClientSecret
        }

        return ProcessInfo.processInfo.environment["GH_ORCHESTRATOR_GITHUB_CLIENT_SECRET"] ?? ""
    }()

    private static func readPayload(from url: URL) -> Payload? {
        guard
            let data = try? Data(contentsOf: url),
            let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else {
            return nil
        }

        return Payload(
            clientID: payload.clientID.trimmingCharacters(in: .whitespacesAndNewlines),
            clientSecret: payload.clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private struct Payload: Decodable {
        let clientID: String
        let clientSecret: String
    }
}

let project = Project(
    name: "GHOrchestrator",
    organizationName: "ipavlidakis",
    packages: [
        .local(path: "Packages/GHOrchestratorCore")
    ],
    targets: [
        .target(
            name: "GHOrchestrator",
            destinations: [.mac],
            product: .app,
            bundleId: "com.ipavlidakis.GHOrchestrator",
            deploymentTargets: .macOS("15.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleURLTypes": .array([
                    .dictionary([
                        "CFBundleURLName": .string("GHOrchestrator OAuth Callback"),
                        "CFBundleURLSchemes": .array([
                            .string("ghorchestrator")
                        ])
                    ])
                ]),
                "GitHubOAuthClientID": .string(gitHubOAuthClientID),
                "GitHubOAuthClientSecret": .string(gitHubOAuthClientSecret)
            ]),
            sources: ["App/Sources/**"],
            resources: [],
            dependencies: [
                .package(product: "GHOrchestratorCore")
            ]
        ),
        .target(
            name: "GHOrchestratorTests",
            destinations: [.mac],
            product: .unitTests,
            bundleId: "com.ipavlidakis.GHOrchestratorTests",
            deploymentTargets: .macOS("15.0"),
            infoPlist: .default,
            sources: ["Tests/GHOrchestratorTests/**"],
            resources: [],
            dependencies: [
                .target(name: "GHOrchestrator"),
                .package(product: "GHOrchestratorCore")
            ]
        )
    ]
)
