// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "3md",
    products: [
        .library(name: "ThreeMD", targets: ["ThreeMD"])
    ],
    targets: [
        .target(
            name: "ThreeMD",
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
