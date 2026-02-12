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
            from: "1.0.0"
        ),
        .package(
            url: "https://github.com/facebook/zstd.git",
            branch: "dev"
        ),
        .package(
            url: "https://github.com/1024jp/GzipSwift.git",
            from: "6.0.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "xctestreport",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "libzstd", package: "zstd"),
                .product(name: "Gzip", package: "GzipSwift")
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
