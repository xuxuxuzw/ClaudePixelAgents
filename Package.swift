// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ClaudePixelAgents",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudePixelAgents",
            path: "Sources/ClaudePixelAgents",
            resources: [
                .copy("webview"),
            ],
            linkerSettings: [
                .linkedFramework("WebKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ImageIO"),
            ]
        ),
    ]
)
