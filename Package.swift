// swift-tools-version: 5.10
// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import PackageDescription

let package = Package(
    name: "CocxyTerminal",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "CocxyMarkdownLib",
            targets: ["CocxyMarkdownLib"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "CocxyMarkdownLib",
            dependencies: [],
            path: "Sources/Domain/Markdown"
        ),
        // MARK: - Main App
        .executableTarget(
            name: "CocxyTerminal",
            dependencies: [
                "CocxyMarkdownLib",
                "CocxyCoreKit",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources",
            exclude: ["Domain/Markdown"],
            resources: [
                .process("App/Assets.xcassets"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("IOSurface"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("Carbon"),
            ]
        ),
        .testTarget(
            name: "CocxyTerminalTests",
            dependencies: [
                "CocxyTerminal",
                "CocxyMarkdownLib",
            ],
            path: "Tests",
            exclude: ["Unit/CLITests"]
        ),
        .binaryTarget(
            name: "CocxyCoreKit",
            path: "libs/CocxyCoreKit.xcframework"
        ),

        // MARK: - CLI Companion
        .target(
            name: "CocxyCLILib",
            dependencies: [],
            path: "CLI/Lib"
        ),
        .executableTarget(
            name: "cocxy",
            dependencies: ["CocxyCLILib"],
            path: "CLI/Sources/Entry"
        ),
        .testTarget(
            name: "CocxyCLITests",
            dependencies: ["CocxyCLILib"],
            path: "Tests/Unit/CLITests"
        ),
    ]
)
