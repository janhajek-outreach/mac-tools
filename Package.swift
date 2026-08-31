// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacTools",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .target(
            name: "MacToolsGeometry",
            path: "Sources/MacToolsGeometry"
        ),
        .executableTarget(
            name: "MacTools",
            dependencies: ["MacToolsGeometry"],
            path: "Sources/MacTools"
        ),
        // Dependency-free test runner (works without Xcode/XCTest — run `swift run GeometryTests`).
        .executableTarget(
            name: "GeometryTests",
            dependencies: ["MacToolsGeometry"],
            path: "Tests/GeometryTests"
        )
    ]
)
