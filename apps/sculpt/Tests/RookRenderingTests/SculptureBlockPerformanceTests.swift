import AppKit
import Foundation
import RookSculpture
import SceneKit
import Testing

@testable import RookRendering

struct SculptureBlockPerformanceTests {
    /// Opt-in timings describe this machine; correctness does not depend on a wall-clock threshold.
    @Test @MainActor func measureLargeLandscapePreparationAndCameraWork() async throws {
        guard let phase = ProcessInfo.processInfo.environment["ROOK_PERFORMANCE_PHASE"] else { return }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let sculpture = try SculptureDocumentCodec.decode(
            Data(contentsOf: root.appendingPathComponent("Examples/Blockhaven/blockhaven.3mdb"))
        )
        let clock = ContinuousClock()
        func milliseconds(_ duration: Duration) -> Double {
            let parts = duration.components
            return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
        }
        var extraction: [Double] = []
        var scene: SculptureVoxelScene?
        for _ in 0..<5 {
            let start = clock.now
            scene = try SculptureVoxelSurfaceExtractor.extract(sculpture)
            extraction.append(milliseconds(start.duration(to: clock.now)))
        }
        let prepared = try #require(scene)
        #expect(prepared.surfaces.count == 136_274)
        let packingStart = clock.now
        let buffers = try await Task.detached { try SculptureVoxelMeshBuffers.prepare(prepared) }.value
        let packing = milliseconds(packingStart.duration(to: clock.now))
        var projection: [Double] = []
        for index in 0..<4 {
            let start = clock.now
            let frame = SculptureVoxelProjection.frame(
                sculpture,
                camera: .init(yaw: Double(index) * .pi / 2, pitch: 0.75, zoom: 0.9),
                width: 576,
                height: 648,
                selectedLayer: nil,
                showsEmptyCells: false
            )
            projection.append(milliseconds(start.duration(to: clock.now)))
            #expect(!frame.isOverBudget && !frame.quads.isEmpty)
        }
        let controller = SculptureLiveVoxelController()
        let view = controller.makeView()
        view.setFrameSize(CGSize(width: 800, height: 600))
        let id = UUID()
        let installStart = clock.now
        controller.configure(
            scene: prepared,
            sceneID: id,
            camera: .init(pitch: 0.75),
            selectedLayer: 96,
            opacity: 0.8,
            emptyCells: [],
            preparedMesh: buffers
        )
        let install = milliseconds(installStart.duration(to: clock.now))
        let cameraStart = clock.now
        for index in 0..<240 {
            controller.updateCamera(.init(yaw: Double(index) * .pi / 120, pitch: 0.75, zoom: 0.9))
        }
        let cameraUpdates = milliseconds(cameraStart.duration(to: clock.now))
        #expect(controller.meshInstallationCount == 1)
        SCNTransaction.flush()
        let snapshotStart = clock.now
        let image = try #require(view.snapshot().cgImage(forProposedRect: nil, context: nil, hints: nil))
        let snapshot = milliseconds(snapshotStart.duration(to: clock.now))
        #expect(image.width >= 800 && image.height >= 600)
        var cachedProjection: [Double] = []
        for index in 0..<4 {
            let start = clock.now
            let frame = SculptureVoxelProjection.frame(
                prepared,
                camera: .init(yaw: Double(index) * .pi / 2, pitch: 0.75, zoom: 0.9),
                width: 576,
                height: 648
            )
            cachedProjection.append(milliseconds(start.duration(to: clock.now)))
            #expect(!frame.isOverBudget && !frame.quads.isEmpty)
        }
        let world = try SculptureWorldCodec.decode(
            Data(contentsOf: root.appendingPathComponent("Examples/Blockhaven/blockhaven-world.3md"))
        )
        let worldStart = clock.now
        let worldScene = try await Task.detached { try SculptureWorldScene.prepare(world) }.value
        let worldPreparation = milliseconds(worldStart.duration(to: clock.now))
        let first = try #require(world.instances.first)
        let moved = try SculptureWorldInstance(
            id: first.id,
            modelID: first.modelID,
            origin: .init(x: first.origin.x + 1, y: first.origin.y, z: first.origin.z),
            quarterTurns: first.quarterTurns
        )
        let movedWorld = try SculptureWorld(
            title: world.title,
            library: world.library,
            instances: [moved] + Array(world.instances.dropFirst())
        )
        let cachedWorldStart = clock.now
        let movedScene = try await Task.detached {
            try SculptureWorldScene.prepare(movedWorld, cachedModels: worldScene)
        }.value
        let cachedWorld = milliseconds(cachedWorldStart.duration(to: clock.now))
        #expect(movedScene.modelCount == worldScene.modelCount)
        #expect(
            worldScene.preparedMeshes.allSatisfy { key, mesh in
                movedScene.preparedMeshes[key]?.identity == mesh.identity
            }
        )
        let folder = root.appendingPathComponent(".build/verification/blockhaven-performance-\(phase)-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try png.write(to: folder.appendingPathComponent("native.png"), options: .atomic)
        let record: [String: Any] = [
            "phase": phase, "configuration": "optimized Swift release tests", "occupiedCells": sculpture.occupiedCount,
            "exteriorFaces": prepared.surfaces.count, "extractionMilliseconds": extraction,
            "fourScalarProjectionMilliseconds": projection, "mainActorMeshInstallMilliseconds": install,
            "workerMeshPackingMilliseconds": packing, "packedMeshBytes": buffers.byteCount,
            "fourCachedProjectionMilliseconds": cachedProjection,
            "worldInitialPreparationMilliseconds": worldPreparation,
            "worldMovedCachedPreparationMilliseconds": cachedWorld,
            "240CameraUpdatesMilliseconds": cameraUpdates, "nativeSnapshotMilliseconds": snapshot,
            "meshInstallations": controller.meshInstallationCount,
            "note": "CPU timings and a synchronized snapshot; not an on-screen FPS measurement",
        ]
        try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
            .write(to: folder.appendingPathComponent("receipt.json"), options: .atomic)
        print("Blockhaven performance evidence: \(folder.path)")
    }
}
