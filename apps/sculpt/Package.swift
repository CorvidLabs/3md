// swift-tools-version: 6.0
import PackageDescription

let threeMD: Target.Dependency = .product(name: "ThreeMD", package: "3md")

#if os(macOS)
let products: [Product] = [
    .library(name: "RookCore", targets: ["RookCore"]),
    .library(name: "RookSculpture", targets: ["RookSculpture"]),
    .library(name: "RookRendering", targets: ["RookRendering"]),
    .library(name: "RookVerification", targets: ["RookVerification"]),
    .library(name: "RookTooling", targets: ["RookTooling"]),
    .executable(name: "Rook", targets: ["RookApp"]),
    .executable(name: "RookTool", targets: ["RookTool"]),
]

let targets: [Target] = [
    .target(name: "RookCore"),
    .target(name: "RookSculpture", dependencies: [threeMD]),
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
]
#else
// Linux unit tests build the model, verification, and tooling targets.
// The Mac app, renderer, and Rook executables stay on macOS.
let products: [Product] = [
    .library(name: "RookCore", targets: ["RookCore"]),
    .library(name: "RookSculpture", targets: ["RookSculpture"]),
    .library(name: "RookVerification", targets: ["RookVerification"]),
    .library(name: "RookTooling", targets: ["RookTooling"]),
]

let targets: [Target] = [
    .target(name: "RookCore"),
    .target(name: "RookSculpture", dependencies: [threeMD, "CLzfse"]),
    .target(name: "RookVerification"),
    .target(name: "RookTooling"),
    // Noble's liblzfse-dev ships the header and shared library without a pkg-config file.
    .systemLibrary(name: "CLzfse", providers: [.apt(["liblzfse-dev"])]),
    .testTarget(name: "RookCoreTests", dependencies: ["RookCore"]),
    .testTarget(name: "RookSculptureTests", dependencies: ["RookSculpture"]),
    .testTarget(name: "RookVerificationTests", dependencies: ["RookVerification"]),
    .testTarget(name: "RookToolingTests", dependencies: ["RookTooling"]),
]
#endif

let package = Package(
    name: "Rook",
    platforms: [.macOS(.v14)],
    products: products,
    dependencies: [
        .package(name: "3md", path: "../..")
    ],
    targets: targets,
    swiftLanguageModes: [.v6]
)
