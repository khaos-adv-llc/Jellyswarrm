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
        // ffmpeg-kit SPM (maintained kingslay fork of retired Arthenica ffmpeg-kit)
        // wired for upcoming exotic-format direct play. Actual routing lands in a
        // follow-up PR — for now we just have the dependency available.
        // TODO: verify SPM resolution
        .package(url: "https://github.com/kingslay/FFmpegKit", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "JellyswarrmCore",
            dependencies: [
                .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift"),
                .product(name: "FFmpegKit", package: "FFmpegKit"),
            ],
            path: "Sources/JellyswarrmCore",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "JellyswarrmUI",
            dependencies: ["JellyswarrmCore"],
            path: "Sources/JellyswarrmUI",
            resources: [
                .process("Metal/HDRToneMap.metal"),
            ]
        ),
        .testTarget(
            name: "JellyswarrmCoreTests",
            dependencies: ["JellyswarrmCore"],
            path: "Tests/JellyswarrmCoreTests"
        ),
    ]
)
