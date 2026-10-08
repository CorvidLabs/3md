import AppKit
import CoreGraphics
import Darwin
import Foundation
import Metal
import RookSculpture
import SceneKit
import Testing

@testable import RookRendering

/// The ordinary case is small. Actual 1024-world rendering measurements require explicit release opt-in.
@Suite(.serialized)
@MainActor
struct SculptureVolumeStudyRenderingTests {
    @Test func smallWorldCountsAndCameraUpdatesRetainSharedMeshes() throws {
        let cube = try Sculpture(
            title: "Small rendering study",
            width: 2,
            height: 2,
            layers: [[35, 35, 35, 35], [35, 35, 35, 35]]
        )
        let map = try SculptureTileMap(
            width: 1,
            height: 1,
            layers: [[67]],
            tileSize: .init(width: 2, height: 2, depth: 2),
            bindings: [.init(glyph: 67, modelID: "cube")]
        )
        let library = try SculptureComposition(
            title: "Small study library",
            rootID: "root",
            models: ["root": .tiles(map), "cube": .sculpture(cube)]
        )
        let world = try SculptureWorld(
            title: "Small rendering counters",
            library: library,
            instances: [
                .init(id: "near", modelID: "cube", origin: .init(x: 0, y: 0, z: 0)),
                .init(id: "proxy", modelID: "cube", origin: .init(x: 12, y: 0, z: 0)),
                .init(id: "culled", modelID: "cube", origin: .init(x: 1_024, y: 0, z: 0)),
            ]
        )
        let prepared = try SculptureWorldScene.prepare(world)
        let controller = SculptureLiveWorldController()
        let view = controller.makeView()
        view.setFrameSize(CGSize(width: 400, height: 300))
        let sceneID = UUID()
        controller.configure(
            scene: prepared,
            sceneID: sceneID,
            focus: .init(x: 0, y: 0, z: 0),
            renderDistance: 16,
            detailDistance: 4,
            camera: .init()
        )
        let counts = counters(controller)
        #expect(counts.total == 3 && counts.visible == 2 && counts.fullDetail == 1 && counts.proxy == 1)
        #expect(counts.culled == 1 && counts.omitted == 0 && counts.coarse == 1 && counts.boundsFallback == 0)
        try requireBounds(counts, scene: prepared, view: view)
        let geometry = try #require(
            view.scene?.rootNode.childNode(withName: "world.instance.near", recursively: true)?.childNodes.first?
                .geometry
        )
        for index in 0..<8 { controller.updateCamera(camera(index, samples: 8)) }
        #expect(counters(controller) == counts)
        controller.configure(
            scene: prepared,
            sceneID: sceneID,
            focus: .init(x: 1, y: 0, z: 0),
            renderDistance: 16,
            detailDistance: 4,
            camera: .init()
        )
        #expect(controller.meshInstallationCount == 1)
        #expect(
            view.scene?.rootNode.childNode(withName: "world.instance.near", recursively: true)?.childNodes.first?
                .geometry === geometry
        )
    }

    /// Run with -c release and ROOK_VOLUME_STUDY_RENDERING=1 only in the coordinated benchmark lane.
    @Test func measure1024WorldMetalRendering() async throws {
        guard ProcessInfo.processInfo.environment["ROOK_VOLUME_STUDY_RENDERING"] == "1" else { return }
        #if DEBUG
        Issue.record("The opt-in rendering benchmark requires optimized Swift release tests (-c release).")
        return
        #else
        _ = NSApplication.shared
        let output = try artifactDirectories()
        print("Volume study rendering staged evidence: \(output.staging.path)")
        var fixtures: [FixtureReceipt] = []
        do {
            let factories: [(String, @Sendable () throws -> SculptureWorld)] = [
                ("dense-equivalent", { try SculptureVolumeStudyExamples.denseEquivalentWorld() }),
                ("landscape", { try SculptureVolumeStudyExamples.landscapeWorld() }),
            ]
            for (name, factory) in factories {
                try Task.checkCancellation()
                let prepared = try await prepare(factory)
                let scene = prepared.scene
                let world = scene.world
                let modelRecords = try scene.models.keys.sorted().map { id in
                    let model = try #require(scene.models[id])
                    let mesh = try #require(scene.preparedMeshes[id])
                    return ModelReceipt(
                        id: id,
                        width: model.width,
                        height: model.height,
                        depth: model.depth,
                        occupiedVoxels: model.occupiedCount,
                        exteriorFaces: model.surfaces.count,
                        packedMeshBytes: mesh.byteCount
                    )
                }
                try validateChunkWorld(world, models: modelRecords)
                let occupancy = try world.instances.reduce(Int64(0)) { count, instance in
                    count + Int64(try #require(scene.models[instance.modelID]).occupiedCount)
                }
                if name == "dense-equivalent" {
                    try #require(world.instances.count == 4_096 && modelRecords.count == 1)
                    try #require(occupancy == 1_073_741_824)
                }
                let controller = SculptureLiveWorldController()
                let view = controller.makeView()
                view.setFrameSize(CGSize(width: 800, height: 600))
                try #require(controller.renderingAPI == .metal)
                SCNTransaction.flush()
                let clearImage = try #require(view.snapshot().cgImage(forProposedRect: nil, context: nil, hints: nil))
                let device = try #require(view.device)
                let clearPixels = try imagePixels(clearImage)
                let clearBackground = Array(clearPixels.prefix(3)).map(Int.init)
                try #require(clearBackground.count == 3)
                try #require(
                    stride(from: 0, to: clearPixels.count, by: 4).allSatisfy { index in
                        (0..<3).allSatisfy { abs(Int(clearPixels[index + $0]) - clearBackground[$0]) <= 2 }
                    }
                )
                let sceneID = UUID()
                var cases: [CaseReceipt] = []
                for item in renderCases {
                    try Task.checkCancellation()
                    let clock = ContinuousClock()
                    let setupStart = clock.now
                    controller.configure(
                        scene: scene,
                        sceneID: sceneID,
                        focus: item.focus,
                        renderDistance: item.renderDistance,
                        detailDistance: item.detailDistance,
                        camera: camera(0, samples: 12)
                    )
                    let setupMilliseconds = milliseconds(setupStart.duration(to: clock.now))
                    let initial = counters(controller)
                    try requireBounds(initial, scene: scene, view: view)
                    try #require(controller.meshInstallationCount == scene.modelCount)

                    // This series submits only camera state. It never snapshots or waits for a GPU frame.
                    var submissions: [Double] = []
                    for index in 0..<120 {
                        try Task.checkCancellation()
                        let pose = camera(index, samples: 120)
                        let start = clock.now
                        controller.updateCamera(pose)
                        submissions.append(milliseconds(start.duration(to: clock.now)))
                    }
                    try #require(counters(controller) == initial)
                    SCNTransaction.flush()
                    _ = view.snapshot()  // An unmeasured warmup before the synchronized frame series.

                    // Camera submission is outside this timer. Flush + snapshot includes synchronization/readback.
                    var frames: [Double] = []
                    var images: [ImageReceipt] = []
                    for index in 0..<12 {
                        try Task.checkCancellation()
                        controller.updateCamera(camera(index, samples: 12))
                        let start = clock.now
                        SCNTransaction.flush()
                        let snapshot = view.snapshot()
                        frames.append(milliseconds(start.duration(to: clock.now)))
                        let image = try #require(snapshot.cgImage(forProposedRect: nil, context: nil, hints: nil))
                        let coverage = try imageCoverage(image, background: clearBackground)
                        try #require(image.width >= 800 && image.height >= 600 && coverage.changedPixels > 100)
                        let filename: String?
                        if index == 0 || index == 3 {
                            let name = "\(name)-\(item.name)-frame-\(index).png"
                            let png = try #require(
                                NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
                            )
                            try requireStaging(output)
                            try png.write(to: output.staging.appendingPathComponent(name), options: .atomic)
                            filename = name
                        } else {
                            filename = nil
                        }
                        images.append(
                            .init(
                                sample: index,
                                width: image.width,
                                height: image.height,
                                changedPixels: coverage.changedPixels,
                                coloredPixels: coverage.coloredPixels,
                                filename: filename
                            )
                        )
                    }
                    try #require(counters(controller) == initial)
                    cases.append(
                        .init(
                            name: item.name,
                            focus: item.focus,
                            renderDistance: item.renderDistance,
                            detailDistance: item.detailDistance,
                            controllerCounts: initial,
                            configurationMilliseconds: setupMilliseconds,
                            cameraSubmissions: TimingSamples(submissions),
                            synchronizedOffscreenFrames: TimingSamples(frames),
                            images: images
                        )
                    )
                    print(
                        "Volume study \(name)/\(item.name): \(initial.visible) visible, \(initial.fullDetail) detailed, \(initial.proxy) proxies, \(initial.omitted) omitted, \(initial.culled) culled"
                    )
                }
                fixtures.append(
                    .init(
                        name: name,
                        title: world.title,
                        logicalExtent: 1_024,
                        localChunkDimension: 64,
                        instancedOccupiedVoxels: occupancy,
                        definitionCount: world.library.models.count,
                        referencedPreparedModels: modelRecords,
                        generationMilliseconds: prepared.generationMilliseconds,
                        surfaceAndMeshPreparationMilliseconds: prepared.preparationMilliseconds,
                        metalDevice: device.name,
                        clearBackgroundRGB: clearBackground,
                        cases: cases
                    )
                )
            }
            let receipt = Receipt(
                schema: "sculpt-volume-study-metal-rendering-1",
                configuration: "optimized Swift release tests",
                platform: ProcessInfo.processInfo.operatingSystemVersionString,
                physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
                processorCount: ProcessInfo.processInfo.processorCount,
                suppliedSourceRevision: ProcessInfo.processInfo.environment["ROOK_VOLUME_STUDY_SOURCE_REVISION"],
                viewportWidthPoints: 800,
                viewportHeightPoints: 600,
                maximumVisibleInstances: SculptureLiveWorldController.maximumVisibleInstances,
                maximumFullDetailFaces: SculptureLiveWorldController.maximumFullDetailFaces,
                maximumPreparedFaces: SculptureWorldScene.maximumPreparedFaces,
                fixtures: fixtures,
                notes: [
                    "120 camera CPU submissions are separate from 12 synchronized offscreen snapshots per case.",
                    "Snapshot timing includes SceneKit flush, GPU synchronization and image readback; PNG encoding and pixel analysis are excluded.",
                    "Pixel coverage is measured against an unmeasured empty Metal view snapshot using the same color conversion.",
                    "The 1024 extent is an instanced world of reusable 64-cell models. Stored occupancy is not the number of voxels drawn by the GPU.",
                    "Live drawing retains the existing 512-instance and 500000-face budgets, with proxies, omitted placements and distance culling reported separately.",
                    "Exterior faces include each installed detailed and coarse model surface plus six per bounds fallback. Shared chunk boundaries are not globally merged.",
                    "These finite measurements do not establish on-screen FPS, billion-voxel GPU rendering, or performance on other hardware.",
                ]
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try Task.checkCancellation()
            try requireStaging(output)
            try encoder.encode(receipt).write(
                to: output.staging.appendingPathComponent("receipt.json"),
                options: .atomic
            )
            try Task.checkCancellation()
            try requireStaging(output)
            guard renamex_np(output.staging.path, output.destination.path, UInt32(RENAME_EXCL)) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            print("Volume study rendering evidence: \(output.destination.path)")
        } catch {
            let failure: [String: Any] = [
                "schema": "sculpt-volume-study-metal-rendering-failure-1", "error": error.localizedDescription,
                "completedFixtures": fixtures.count,
            ]
            if (try? requireStaging(output)) != nil,
                let data = try? JSONSerialization.data(withJSONObject: failure, options: [.prettyPrinted, .sortedKeys])
            {
                try? data.write(to: output.staging.appendingPathComponent("failure.json"), options: .atomic)
            }
            throw error
        }
        #endif
    }

    private var renderCases: [RenderCase] {
        [
            .init(
                name: "center-narrow",
                focus: .init(x: 512, y: 512, z: 512),
                renderDistance: 192,
                detailDistance: 128
            ),
            .init(
                name: "center-wide",
                focus: .init(x: 512, y: 512, z: 512),
                renderDistance: 1_024,
                detailDistance: 256
            ),
            .init(
                name: "shifted-narrow",
                focus: .init(x: 896, y: 512, z: 896),
                renderDistance: 192,
                detailDistance: 128
            ),
            .init(
                name: "ground-narrow",
                focus: .init(x: 512, y: 960, z: 512),
                renderDistance: 192,
                detailDistance: 128
            ),
            .init(
                name: "wide-detail-budget",
                focus: .init(x: 512, y: 512, z: 512),
                renderDistance: 1_024,
                detailDistance: 1_024
            ),
        ]
    }

    private func camera(_ sample: Int, samples: Int) -> SculptureCamera {
        .init(yaw: -0.6 + Double(sample) * 2 * .pi / Double(samples), pitch: 0.55, zoom: 0.9)
    }

    private func prepare(_ factory: @escaping @Sendable () throws -> SculptureWorld) async throws -> PreparedFixture {
        let task = Task.detached(priority: .userInitiated) {
            let clock = ContinuousClock()
            try Task.checkCancellation()
            let generationStart = clock.now
            let world = try factory()
            let generation = Self.milliseconds(generationStart.duration(to: clock.now))
            let preparationStart = clock.now
            let scene = try SculptureWorldScene.prepare(world)
            return PreparedFixture(
                scene: scene,
                generationMilliseconds: generation,
                preparationMilliseconds: Self.milliseconds(preparationStart.duration(to: clock.now))
            )
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func validateChunkWorld(_ world: SculptureWorld, models: [ModelReceipt]) throws {
        try #require(models.allSatisfy { $0.width == 64 && $0.height == 64 && $0.depth == 64 })
        try #require(Set(world.instances.map(\.origin)).count == world.instances.count)
        try #require(
            world.instances.allSatisfy { instance in
                instance.quarterTurns == 0
                    && [instance.origin.x, instance.origin.y, instance.origin.z].allSatisfy {
                        $0 >= 0 && $0 <= 960 && $0.isMultiple(of: 64)
                    }
            }
        )
        for axis in [world.instances.map(\.origin.x), world.instances.map(\.origin.y), world.instances.map(\.origin.z)]
        {
            try #require(axis.min() == 0 && axis.max() == 960)
        }
    }

    private func counters(_ controller: SculptureLiveWorldController) -> ControllerCounts {
        .init(
            total: controller.totalInstanceCount,
            visible: controller.visibleInstanceCount,
            fullDetail: controller.fullDetailInstanceCount,
            proxy: controller.proxyInstanceCount,
            coarse: controller.coarseInstanceCount,
            boundsFallback: controller.boundsProxyInstanceCount,
            omitted: controller.omittedInstanceCount,
            culled: controller.culledInstanceCount,
            detailBudgetProxy: controller.detailBudgetProxyInstanceCount,
            renderedExteriorFaces: controller.renderedExteriorFaceCount,
            meshInstallations: controller.meshInstallationCount
        )
    }

    private func requireBounds(_ counts: ControllerCounts, scene: SculptureWorldScene, view: SCNView) throws {
        try #require(counts.total == counts.visible + counts.omitted + counts.culled)
        try #require(counts.visible == counts.fullDetail + counts.proxy)
        try #require(counts.proxy == counts.coarse + counts.boundsFallback)
        try #require(counts.visible > 0 && counts.visible <= SculptureLiveWorldController.maximumVisibleInstances)
        try #require(counts.detailBudgetProxy <= counts.proxy)
        try #require(counts.renderedExteriorFaces <= SculptureLiveWorldController.maximumFullDetailFaces)
        var actualFaces = 0
        for instance in scene.world.instances {
            guard
                let fill = view.scene?.rootNode.childNode(
                    withName: "world.instance.\(instance.id)",
                    recursively: true
                )?.childNodes.first
            else { continue }
            switch fill.name {
            case "world.detail": actualFaces += try #require(scene.models[instance.modelID]?.surfaces.count)
            case "world.coarse": actualFaces += try #require(scene.coarseMeshes[instance.modelID]?.faceCount)
            case "world.proxy": actualFaces += 6
            default: Issue.record("Unknown installed world mesh")
            }
        }
        try #require(counts.renderedExteriorFaces == actualFaces)
    }

    private func imagePixels(_ image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let rendered = pixels.withUnsafeMutableBytes { buffer in
            guard
                let context = CGContext(
                    data: buffer.baseAddress,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: image.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
            return true
        }
        try #require(rendered)
        return pixels
    }

    private func imageCoverage(_ image: CGImage, background: [Int]) throws -> (changedPixels: Int, coloredPixels: Int) {
        let pixels = try imagePixels(image)
        var changed = 0, colored = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let channels = (0..<3).map { Int(pixels[index + $0]) }
            let difference = (0..<3).reduce(0) { $0 + abs(channels[$1] - background[$1]) }
            if difference > 24 {
                changed += 1
                if (channels.max() ?? 0) - (channels.min() ?? 0) > 18 { colored += 1 }
            }
        }
        return (changed, colored)
    }

    private func artifactDirectories() throws -> ArtifactDirectories {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let explicit = ProcessInfo.processInfo.environment["ROOK_VOLUME_STUDY_RENDERING_DIRECTORY"]
        if let explicit, !explicit.hasPrefix("/") || explicit.utf8.contains(0) {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let destination =
            explicit.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? repository.appendingPathComponent(
                ".build/verification/volume-study-rendering-\(UUID())",
                isDirectory: true
            )
        guard destination.standardizedFileURL.path != "/" else { throw CocoaError(.fileWriteInvalidFileName) }
        let parent = destination.deletingLastPathComponent().resolvingSymlinksInPath()
        if explicit == nil { try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true) }
        let target = parent.appendingPathComponent(destination.lastPathComponent, isDirectory: true)
        var information = stat()
        if lstat(target.path, &information) == 0 { throw CocoaError(.fileWriteFileExists) }
        guard errno == ENOENT else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let staging = parent.appendingPathComponent(
            "volume-study-rendering-stage-\(UUID())",
            isDirectory: true
        )
        guard mkdir(staging.path, 0o700) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard lstat(staging.path, &information) == 0,
            information.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
        else { throw CocoaError(.fileReadUnknown) }
        return ArtifactDirectories(
            destination: target,
            staging: staging,
            device: information.st_dev,
            inode: information.st_ino
        )
    }

    private func requireStaging(_ output: ArtifactDirectories) throws {
        var information = stat()
        guard lstat(output.staging.path, &information) == 0,
            information.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
            information.st_dev == output.device,
            information.st_ino == output.inode
        else { throw CocoaError(.fileReadUnknown) }
    }

    private func milliseconds(_ duration: Duration) -> Double { Self.milliseconds(duration) }
    private nonisolated static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    private struct RenderCase {
        let name: String; let focus: SculptureWorldPoint; let renderDistance: Int; let detailDistance: Int
    }
    private struct ArtifactDirectories {
        let destination: URL; let staging: URL; let device: dev_t; let inode: ino_t
    }
    private struct PreparedFixture: Sendable {
        let scene: SculptureWorldScene; let generationMilliseconds: Double; let preparationMilliseconds: Double
    }
    private struct ControllerCounts: Codable, Equatable {
        let total: Int; let visible: Int; let fullDetail: Int; let proxy: Int; let coarse: Int; let boundsFallback: Int
        let omitted: Int; let culled: Int
        let detailBudgetProxy: Int; let renderedExteriorFaces: Int; let meshInstallations: Int
    }
    private struct ModelReceipt: Codable {
        let id: String; let width: Int; let height: Int; let depth: Int; let occupiedVoxels: Int
        let exteriorFaces: Int; let packedMeshBytes: Int
    }
    private struct ImageReceipt: Codable {
        let sample: Int; let width: Int; let height: Int; let changedPixels: Int; let coloredPixels: Int;
        let filename: String?
    }
    private struct TimingSamples: Codable {
        let milliseconds: [Double]; let minimum: Double; let median: Double; let p95: Double; let maximum: Double
        init(_ values: [Double]) {
            milliseconds = values
            let ordered = values.sorted()
            minimum = ordered.first ?? 0; maximum = ordered.last ?? 0
            median = ordered.isEmpty ? 0 : (ordered[(ordered.count - 1) / 2] + ordered[ordered.count / 2]) / 2
            p95 = ordered.isEmpty ? 0 : ordered[max(0, Int(ceil(Double(ordered.count) * 0.95)) - 1)]
        }
    }
    private struct CaseReceipt: Codable {
        let name: String; let focus: SculptureWorldPoint; let renderDistance: Int; let detailDistance: Int
        let controllerCounts: ControllerCounts; let configurationMilliseconds: Double
        let cameraSubmissions: TimingSamples; let synchronizedOffscreenFrames: TimingSamples; let images: [ImageReceipt]
    }
    private struct FixtureReceipt: Codable {
        let name: String; let title: String; let logicalExtent: Int; let localChunkDimension: Int
        let instancedOccupiedVoxels: Int64; let definitionCount: Int; let referencedPreparedModels: [ModelReceipt]
        let generationMilliseconds: Double; let surfaceAndMeshPreparationMilliseconds: Double
        let metalDevice: String; let clearBackgroundRGB: [Int]; let cases: [CaseReceipt]
    }
    private struct Receipt: Codable {
        let schema: String; let configuration: String; let platform: String; let physicalMemoryBytes: UInt64
        let processorCount: Int; let suppliedSourceRevision: String?; let viewportWidthPoints: Int;
        let viewportHeightPoints: Int
        let maximumVisibleInstances: Int; let maximumFullDetailFaces: Int; let maximumPreparedFaces: Int
        let fixtures: [FixtureReceipt]; let notes: [String]
    }
}
