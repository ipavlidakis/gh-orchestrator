// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GHOrchestratorCore",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "GHOrchestratorCore",
            targets: ["GHOrchestratorCore"]
        )
    ],
    targets: [
        .target(
            name: "GHOrchestratorCore"
        ),
        .testTarget(
            name: "GHOrchestratorCoreTests",
            dependencies: ["GHOrchestratorCore"],
            resources: [
                .process("Fixtures")
            ]
        )
    ]
)
