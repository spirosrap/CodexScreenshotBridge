// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CodexScreenshotBridge",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "CodexScreenshotBridge",
            targets: ["CodexScreenshotBridge"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "CodexScreenshotBridge"
        ),
    ]
)
