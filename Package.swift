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
        )
    ],
    targets: [
        .executableTarget(
            name: "xctestreport",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
