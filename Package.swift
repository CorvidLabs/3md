// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "3md",
    products: [
        .library(name: "ThreeMD", targets: ["ThreeMD"]),
        .executable(name: "threemd", targets: ["ThreeMDCLI"]),
    ],
    targets: [
        .target(
            name: "ThreeMD",
            path: "Sources/ThreeMD",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "ThreeMDCLI",
            dependencies: ["ThreeMD"],
            path: "Sources/CLI",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "ThreeMDTests",
            dependencies: ["ThreeMD"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
    ]
)
