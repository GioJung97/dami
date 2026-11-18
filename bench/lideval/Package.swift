// swift-tools-version: 5.10
import PackageDescription

/// Language-choice bench (v1.1): runs each clip once through the same model and decoding settings as the app, and records
/// everything a language rule needs, so rules can be compared afterwards without running the model again.
let package = Package(
    name: "lideval",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift", exact: "1.1.1"),
    ],
    targets: [
        .executableTarget(name: "lideval", dependencies: [.product(name: "WhisperKit", package: "argmax-oss-swift")]),
    ]
)
