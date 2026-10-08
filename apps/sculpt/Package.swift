// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Rook",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RookCore", targets: ["RookCore"]),
        .library(name: "RookSculpture", targets: ["RookSculpture"]),
        .library(name: "RookRendering", targets: ["RookRendering"]),
        .library(name: "RookVerification", targets: ["RookVerification"]),
        .library(name: "RookTooling", targets: ["RookTooling"]),
        .executable(name: "Rook", targets: ["RookApp"]),
        .executable(name: "RookTool", targets: ["RookTool"]),
    ],
    dependencies: [
        .package(name: "3md", path: "../..")
    ],
    targets: [
        .target(name: "RookCore"),
        .target(name: "RookSculpture", dependencies: [.product(name: "ThreeMD", package: "3md")]),
        .target(name: "RookRendering", dependencies: ["RookSculpture"]),
        .executableTarget(name: "RookApp", dependencies: ["RookCore", "RookSculpture", "RookRendering"]),
        .target(name: "RookVerification"),
        .target(name: "RookTooling"),
        .executableTarget(
            name: "RookTool",
            dependencies: ["RookTooling", "RookVerification", "RookSculpture", "RookRendering"]
        ),
        .testTarget(name: "RookCoreTests", dependencies: ["RookCore"]),
        .testTarget(name: "RookSculptureTests", dependencies: ["RookSculpture"]),
        .testTarget(name: "RookRenderingTests", dependencies: ["RookRendering", "RookSculpture"]),
        .testTarget(name: "RookAppTests", dependencies: ["RookApp", "RookCore"]),
        .testTarget(name: "RookVerificationTests", dependencies: ["RookVerification"]),
        .testTarget(name: "RookToolingTests", dependencies: ["RookTooling"]),
        .testTarget(name: "RookToolTests", dependencies: ["RookTool", "RookSculpture"]),
    ],
    swiftLanguageModes: [.v6]
)
