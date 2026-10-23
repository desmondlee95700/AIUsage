// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AIUsage",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AIUsage", targets: ["AIUsage"])
    ],
    targets: [
        .executableTarget(
            name: "AIUsage",
            path: "Sources",
            // Full data-race checking; CI builds with warnings as errors, so new races fail the build
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "AIUsageTests",
            dependencies: ["AIUsage"],
            path: "Tests/AIUsageTests"
        )
    ]
)
