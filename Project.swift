import Foundation
import ProjectDescription

let gitHubOAuthClientID = LocalGitHubOAuthConfiguration.clientID

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

    private static func readPayload(from url: URL) -> Payload? {
        guard
            let data = try? Data(contentsOf: url),
            let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else {
            return nil
        }

        return Payload(
            clientID: payload.clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private struct Payload: Decodable {
        let clientID: String
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
                "GitHubOAuthClientID": .string(gitHubOAuthClientID)
            ]),
            sources: ["App/Sources/**"],
            resources: ["App/Resources/**"],
            dependencies: [
                .package(product: "GHOrchestratorCore")
            ],
            settings: .settings(
                base: [
                    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                    "CURRENT_PROJECT_VERSION": "1",
                    "MARKETING_VERSION": "1.0.0"
                ],
                configurations: [
                    .debug(name: "Debug"),
                    .release(
                        name: "Release",
                        settings: [
                            "ENABLE_HARDENED_RUNTIME": "YES"
                        ]
                    )
                ]
            )
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
