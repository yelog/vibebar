// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "VibeBar",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "VibeBarCore",
            targets: ["VibeBarCore"]
        ),
        .executable(
            name: "vibebar-agent",
            targets: ["VibeBarAgent"]
        ),
        .executable(
            name: "VibeBarApp",
            targets: ["VibeBarApp"]
        ),
        .executable(
            name: "vibebar",
            targets: ["VibeBarCLI"]
        ),
    ],
    targets: [
        .target(
            name: "VibeBarCore"
        ),
        .executableTarget(
            name: "VibeBarAgent",
            dependencies: ["VibeBarCore"]
        ),
        .executableTarget(
            name: "VibeBarApp",
            dependencies: ["VibeBarCore"]
        ),
        .executableTarget(
            name: "VibeBarCLI",
            dependencies: ["VibeBarCore"]
        ),
    ]
)
