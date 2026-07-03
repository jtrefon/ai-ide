// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VectorStore",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "VectorStore",
            targets: ["VectorStore"]
        ),
    ],
    targets: [
        .target(
            name: "CFAISSWrapper",
            dependencies: [],
            exclude: [],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("Libraries/include"),
            ],
            linkerSettings: [
                .linkedLibrary("faiss_full"),
                .linkedLibrary("c++"),
                .linkedLibrary("omp"),
                .unsafeFlags(["-LLibraries/arm64"]),
                .unsafeFlags(["-L/opt/homebrew/opt/libomp/lib"]),
                .unsafeFlags(["-framework", "Accelerate"]),
            ]
        ),
        .target(
            name: "VectorStore",
            dependencies: ["CFAISSWrapper"]
        ),
        .testTarget(
            name: "VectorStoreTests",
            dependencies: ["VectorStore"]
        ),
    ]
)
