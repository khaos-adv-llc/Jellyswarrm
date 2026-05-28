// swift-tools-version: 5.10
// Jellyswarrm — A native SwiftUI Jellyfin client
// GPL v3 with App Store exception. Inspired by Fladder (https://github.com/DonutWare/Fladder)

import PackageDescription

let package = Package(
    name: "Jellyswarrm",
    platforms: [
        .iOS("26.0"),
        .tvOS("26.0"),
        .macOS("26.0"),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "JellyswarrmCore", targets: ["JellyswarrmCore"]),
        .library(name: "JellyswarrmUI", targets: ["JellyswarrmUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jellyfin/jellyfin-sdk-swift", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "JellyswarrmCore",
            dependencies: [
                .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift"),
            ],
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
