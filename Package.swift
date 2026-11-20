// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LocalGit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "localgit", targets: ["LocalGitCLI"]),
        .library(name: "LocalGitCore", targets: ["LocalGitCore"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "LocalGitCore",
            path: "Sources/LocalGitCore"
        ),
        .executableTarget(
            name: "LocalGitCLI",
            dependencies: ["LocalGitCore"],
            path: "Sources/LocalGitCLI"
        ),
        .testTarget(
            name: "LocalGitTests",
            dependencies: ["LocalGitCore"],
            path: "Tests/LocalGitTests"
        )
    ]
)
