// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SessionEngram",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "session-engram", targets: ["SessionEngram"]),
    ],
    targets: [
        .executableTarget(name: "SessionEngram"),
        .testTarget(name: "SessionEngramTests", dependencies: ["SessionEngram"]),
    ]
)
