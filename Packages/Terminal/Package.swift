// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Terminal",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "Terminal",
            targets: ["Terminal"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.13.0"),
    ],
    targets: [
        .target(
            name: "Terminal",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ]
        ),
    ]
)
