// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "{{project_name}}",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "{{project_name}}", targets: ["{{module_name}}"]),
    ],
    targets: [
        .executableTarget(name: "{{module_name}}"),
        .testTarget(name: "{{module_name}}Tests", dependencies: ["{{module_name}}"]),
    ]
)
