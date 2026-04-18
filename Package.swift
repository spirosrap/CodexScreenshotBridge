// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CodexScreenshotBridge",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "CodexScreenshotBridgeCore",
            targets: ["CodexScreenshotBridgeCore"]
        ),
        .executable(
            name: "CodexScreenshotBridge",
            targets: ["CodexScreenshotBridgeApp"]
        ),
    ],
    targets: [
        .target(
            name: "CodexScreenshotBridgeCore",
            path: "Sources/CodexScreenshotBridge"
        ),
        .executableTarget(
            name: "CodexScreenshotBridgeApp",
            dependencies: ["CodexScreenshotBridgeCore"],
            path: "Sources/CodexScreenshotBridgeApp"
        ),
        .executableTarget(
            name: "CodexScreenshotBridgeTestRunner",
            dependencies: ["CodexScreenshotBridgeCore"],
            path: "Tests/CodexScreenshotBridgeTests"
        ),
    ]
)
