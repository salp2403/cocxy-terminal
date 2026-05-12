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
        .library(
            name: "CocxyShared",
            targets: ["CocxyShared"]
        ),
        .library(
            name: "CocxyInputClassifier",
            targets: ["CocxyInputClassifier"]
        ),
        .library(
            name: "CocxyCommandSignatures",
            targets: ["CocxyCommandSignatures"]
        ),
        .library(
            name: "CocxyCommandCorrections",
            targets: ["CocxyCommandCorrections"]
        ),
        .library(
            name: "CocxyVault",
            targets: ["CocxyVault"]
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
        .target(
            name: "CocxyShared",
            dependencies: [],
            path: "Shared"
        ),
        .target(
            name: "CocxyInputClassifier",
            dependencies: [],
            path: "Sources/Domain/InputClassifier",
            linkerSettings: [
                .linkedFramework("NaturalLanguage"),
            ]
        ),
        .target(
            name: "CocxyCommandSignatures",
            dependencies: [],
            path: "Sources/Domain/CommandSignatures"
        ),
        .target(
            name: "CocxyCommandCorrections",
            dependencies: [],
            path: "Sources/Domain/CommandCorrections"
        ),
        .target(
            name: "CocxyVault",
            dependencies: [],
            path: "Sources/Domain/Vault",
            linkerSettings: [
                .linkedFramework("Security"),
            ]
        ),
        // MARK: - Main App
        .executableTarget(
            name: "CocxyTerminal",
            dependencies: [
                "CocxyShared",
                "CocxyMarkdownLib",
                "CocxyInputClassifier",
                "CocxyCommandSignatures",
                "CocxyCommandCorrections",
                "CocxyVault",
                "CocxyTreeSitterABI",
                "CocxyCoreKit",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources",
            exclude: ["Domain/Markdown", "Domain/InputClassifier", "Domain/CommandSignatures", "Domain/CommandCorrections", "Domain/Vault", "CocxyTreeSitterABI"],
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
                .linkedFramework("NaturalLanguage"),
                .linkedFramework("CoreSpotlight"),
            ]
        ),
        .testTarget(
            name: "CocxyTerminalTests",
            dependencies: [
                "CocxyTerminal",
                "CocxyShared",
                "CocxyMarkdownLib",
                "CocxyInputClassifier",
                "CocxyCommandSignatures",
                "CocxyCommandCorrections",
                "CocxyVault",
                "CocxyTestRuntime",
            ],
            path: "Tests",
            exclude: ["Unit/CLITests", "TestRuntime"]
        ),
        .target(
            name: "CocxyTestRuntime",
            path: "Tests/TestRuntime"
        ),
        .binaryTarget(
            name: "CocxyCoreKit",
            path: "libs/CocxyCoreKit.xcframework"
        ),
        .target(
            name: "CocxyTreeSitterABI",
            path: "Sources/CocxyTreeSitterABI",
            publicHeadersPath: "include"
        ),

        // MARK: - CLI Companion
        .target(
            name: "CocxyCLILib",
            dependencies: ["CocxyShared", "CocxyInputClassifier", "CocxyCommandSignatures", "CocxyCommandCorrections", "CocxyVault"],
            path: "CLI/Lib"
        ),
        .executableTarget(
            name: "cocxy",
            dependencies: ["CocxyCLILib"],
            path: "CLI/Sources/Entry"
        ),
        .target(
            name: "CocxyDaemonLib",
            dependencies: ["CocxyShared", "CocxyCoreKit"],
            path: "Daemon/Lib"
        ),
        .executableTarget(
            name: "cocxyd",
            dependencies: ["CocxyDaemonLib"],
            path: "Daemon/Sources"
        ),
        .testTarget(
            name: "CocxyCLITests",
            dependencies: ["CocxyCLILib", "CocxyShared", "CocxyInputClassifier", "CocxyCommandSignatures", "CocxyCommandCorrections", "CocxyVault", "CocxyDaemonLib"],
            path: "Tests/Unit/CLITests"
        ),
    ]
)
