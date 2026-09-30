// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tempo",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Tempo",
            path: "Sources/Tempo"
        ),
        .testTarget(
            name: "TempoTests",
            dependencies: ["Tempo"],
            path: "Tests/TempoTests"
        ),
    ]
)
