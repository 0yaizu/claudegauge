// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "ClaudeGauge",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "ClaudeGaugeCore"),
        .executableTarget(name: "ClaudeGauge", dependencies: ["ClaudeGaugeCore"]),
        .testTarget(
            name: "ClaudeGaugeCoreTests",
            dependencies: ["ClaudeGaugeCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
