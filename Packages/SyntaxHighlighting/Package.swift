// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SyntaxHighlighting",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "SyntaxHighlighting",
            targets: ["SyntaxHighlighting"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/ChimeHQ/Neon", branch: "main"),
        .package(url: "https://github.com/CodeEditApp/CodeEditLanguages", from: "0.1.20"),
    ],
    targets: [
        .target(
            name: "SyntaxHighlighting",
            dependencies: [
                .product(name: "Neon", package: "Neon"),
                .product(name: "CodeEditLanguages", package: "CodeEditLanguages"),
            ]
        ),
    ]
)
