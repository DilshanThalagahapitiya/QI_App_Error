// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ErrorRegistryKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "ErrorRegistryKit",
            targets: ["ErrorRegistryKit"]
        )
    ],
    targets: [
        .target(
            name: "ErrorRegistryKit",
            dependencies: [],
            path: "Sources/ErrorRegistryKit",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ErrorRegistryKitTests",
            dependencies: ["ErrorRegistryKit"],
            path: "Tests/ErrorRegistryKitTests"
        )
    ]
)