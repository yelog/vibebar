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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "VibeBarCore",
            exclude: ["CLAUDE.md"],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .executableTarget(
            name: "VibeBarAgent",
            dependencies: ["VibeBarCore"]
        ),
        .executableTarget(
            name: "VibeBarApp",
            dependencies: [
                "VibeBarCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            exclude: [
                "CLAUDE.md",
                "Resources/AppIcon.png",
                "Resources/AppIcon.icns",
                "Resources/VibeBar.entitlements",
            ],
            resources: [
                .process("Resources/claudeCode.png"),
                .process("Resources/codex.png"),
                .process("Resources/opencode.png"),
                .process("Resources/aider_final.png"),
                .process("Resources/gemini.png"),
                .process("Resources/github.png"),
            ]
        ),
        .executableTarget(
            name: "VibeBarCLI",
            dependencies: ["VibeBarCore"]
        ),
        .testTarget(
            name: "VibeBarCoreTests",
            dependencies: ["VibeBarCore"],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
    ]
)
