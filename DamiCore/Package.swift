// swift-tools-version: 5.10
import PackageDescription

/// Dami's pure logic, testable without the app: no AppKit, WhisperKit or GRDB.
let package = Package(
    name: "DamiCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DamiCore", targets: ["DamiCore"]),
        .executable(name: "dami-eval", targets: ["dami-eval"]),
        .executable(name: "dami-guard", targets: ["dami-guard"]),
    ],
    targets: [
        .target(name: "DamiCore"),
        .executableTarget(name: "dami-eval", dependencies: ["DamiCore"]),
        .executableTarget(name: "dami-guard", dependencies: ["DamiCore"]),
        .testTarget(name: "DamiCoreTests", dependencies: ["DamiCore"]),
    ]
)
