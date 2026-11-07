// swift-tools-version: 5.10
import PackageDescription

/// LocalFlow's pure logic, testable without the app: no AppKit, WhisperKit or GRDB.
let package = Package(
    name: "LocalFlowCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LocalFlowCore", targets: ["LocalFlowCore"]),
        .executable(name: "localflow-eval", targets: ["localflow-eval"]),
        .executable(name: "localflow-guard", targets: ["localflow-guard"]),
    ],
    targets: [
        .target(name: "LocalFlowCore"),
        .executableTarget(name: "localflow-eval", dependencies: ["LocalFlowCore"]),
        .executableTarget(name: "localflow-guard", dependencies: ["LocalFlowCore"]),
        .testTarget(name: "LocalFlowCoreTests", dependencies: ["LocalFlowCore"]),
    ]
)
