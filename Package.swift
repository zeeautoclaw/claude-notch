// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "ClaudeNotch",
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "ClaudeNotchApp", targets: ["ClaudeNotchApp"]),
        .executable(name: "ClaudeNotchRelay", targets: ["ClaudeNotchRelay"]),
        .library(name: "ClaudeNotchShared", targets: ["ClaudeNotchShared"]),
    ],
    targets: [
        .target(
            name: "ClaudeNotchShared",
            path: "Sources/ClaudeNotchShared"
        ),
        .executableTarget(
            name: "ClaudeNotchRelay",
            dependencies: ["ClaudeNotchShared"],
            path: "Sources/ClaudeNotchRelay"
        ),
        .executableTarget(
            name: "ClaudeNotchApp",
            dependencies: ["ClaudeNotchShared"],
            path: "Sources/ClaudeNotchApp"
        ),
    ]
)
