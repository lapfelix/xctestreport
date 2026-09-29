// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "xctestreport",
    platforms: [
        .macOS(.v10_15)
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-argument-parser.git",
            from: "1.8.2"
        ),
        .package(
            url: "https://github.com/facebook/zstd.git",
            from: "1.5.7"
        )
    ],
    targets: [
        .executableTarget(
            name: "xctestreport",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "libzstd", package: "zstd")
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "xctestreportTests",
            dependencies: [
                "xctestreport"
            ]
        )
    ]
)
