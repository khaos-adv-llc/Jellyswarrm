// swift-tools-version: 5.9
// Jellyswarrm — A native SwiftUI Jellyfin client
// GPL v3 with App Store exception. Inspired by Fladder (https://github.com/DonutWare/Fladder)

import PackageDescription

let package = Package(
    name: "Jellyswarrm",
    platforms: [
        .iOS(.v17),
        .tvOS(.v17),
        .macOS(.v14),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "JellyswarrmCore", targets: ["JellyswarrmCore"]),
        .library(name: "JellyswarrmUI", targets: ["JellyswarrmUI"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "JellyswarrmCore",
            dependencies: [],
            path: "Sources/JellyswarrmCore",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "JellyswarrmUI",
            dependencies: ["JellyswarrmCore"],
            path: "Sources/JellyswarrmUI"
        ),
        .testTarget(
            name: "JellyswarrmCoreTests",
            dependencies: ["JellyswarrmCore"],
            path: "Tests/JellyswarrmCoreTests"
        ),
    ]
)
