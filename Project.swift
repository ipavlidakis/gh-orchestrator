import ProjectDescription

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
                "GitHubOAuthClientID": .string("")
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
