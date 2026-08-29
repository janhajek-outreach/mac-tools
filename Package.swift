// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacTools",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "MacTools",
            path: "Sources/MacTools"
        )
    ]
)
