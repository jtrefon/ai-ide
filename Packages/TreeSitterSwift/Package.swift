// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TreeSitterSwift",
    platforms: [
        .macOS(.v10_13)
    ],
    products: [
        .library(name: "TreeSitterSwift", targets: ["TreeSitterSwift"])
    ],
    dependencies: [
        .package(url: "https://github.com/tree-sitter/tree-sitter", .upToNextMinor(from: "0.25.0"))
    ],
    targets: [
        .target(
            name: "TreeSitterSwiftC",
            dependencies: [
                .product(name: "TreeSitter", package: "tree-sitter")
            ],
            path: "Sources/TreeSitterSwiftC",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("src")
            ]
        ),
        .target(
            name: "TreeSitterSwift",
            dependencies: ["TreeSitterSwiftC"],
            path: "Sources/TreeSitterSwift",
            resources: [
                .copy("queries")
            ]
        )
    ]
)
