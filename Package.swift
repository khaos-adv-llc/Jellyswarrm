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
        // FFmpegKit: to be added after SPM resolution verified.
        // The kingslay fork (https://github.com/kingslay/FFmpegKit) has no 1.0.0 tag —
        // lowest is 6.0.0 — so `from: "1.0.0"` failed to resolve and broke the whole
        // package, taking JellyswarrmCore/JellyswarrmUI imports down with it on the
        // macOS app target. Re-add with a real version constraint in a follow-up PR.
        // .package(url: "https://github.com/kingslay/FFmpegKit", from: "6.0.0"),
    ],
    targets: [
        .target(
            name: "JellyswarrmCore",
            dependencies: [
                .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift"),
                // .product(name: "FFmpegKit", package: "FFmpegKit"),
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
