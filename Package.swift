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
            path: "Sources"
        ),
        .testTarget(
            name: "AIUsageTests",
            dependencies: ["AIUsage"],
            path: "Tests/AIUsageTests"
        )
    ]
)
