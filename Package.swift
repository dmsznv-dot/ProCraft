// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PixelCraftPro",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // Core graphics engine library (headless, embeddable, testable)
        .library(
            name: "PixelCraftEngine",
            targets: ["PixelCraftEngine"]
        ),
        // Standalone macOS graphic editor application executable
        .executable(
            name: "PixelCraftApp",
            targets: ["PixelCraftApp"]
        ),
    ],
    dependencies: [
        // Zero external package dependencies.
        // Pure Apple Silicon native stack using Metal, SwiftUI, AppKit, Vision, and CoreImage.
    ],
    targets: [
        // 1. PixelCraftEngine: Core Data Models, Metal Pipelines & Tool Services
        .target(
            name: "PixelCraftEngine",
            dependencies: [],
            path: "Sources/PixelCraftEngine",
            resources: [
                .process("Metal/Shaders")
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .define("PIXELCRAFT_ENGINE")
            ]
        ),
        
        // 2. PixelCraftApp: macOS Native UI (SwiftUI / AppKit / MTKView)
        .executableTarget(
            name: "PixelCraftApp",
            dependencies: [
                "PixelCraftEngine"
            ],
            path: "Sources/PixelCraftApp",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        
        // 3. PixelCraftEngineTests: Unit & Integration Test Suite
        .testTarget(
            name: "PixelCraftEngineTests",
            dependencies: [
                "PixelCraftEngine"
            ],
            path: "Tests/PixelCraftEngineTests",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
    ]
)
