// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentSessions",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "agent-sessions", targets: ["AgentSessions"]),
    ],
    targets: [
        .executableTarget(name: "AgentSessions"),
        .testTarget(name: "AgentSessionsTests", dependencies: ["AgentSessions"]),
    ]
)
