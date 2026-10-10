import AppKit
import CoreGraphics
import Foundation
import RookSculpture
import SceneKit
import Testing

@testable import RookRendering

@Suite(.serialized)
@MainActor
struct SculptureLiveVoxelTests {
    @Test func gpuPickingMatchesTheExistingProjectionAtOffCenterPointsAndSeveralPoses() throws {
        var sculpture = try blankVolume(size: 9)
        sculpture.paint(SculptureCell(x: 4, y: 1, z: 2), glyph: 35)
        sculpture.paint(SculptureCell(x: 2, y: 5, z: 5), glyph: 111)
        sculpture.paint(SculptureCell(x: 6, y: 6, z: 3), glyph: 64)
        let scene = try SculptureVoxelSurfaceExtractor.extract(sculpture)
        let controller = SculptureLiveVoxelController()
        let view = controller.makeView()
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 320)
        let id = UUID()
        let poses = [
            SculptureCamera(yaw: 0, pitch: 0), SculptureCamera(yaw: -0.6, pitch: 0.7),
            SculptureCamera(yaw: 1.1, pitch: -0.4, zoom: 1.2), SculptureCamera(yaw: -.pi / 2, pitch: 0.2),
            SculptureCamera(yaw: -0.6, pitch: .pi / 2),
            SculptureCamera(yaw: -0.6, pitch: .pi / 2 + 0.2),
            SculptureCamera(yaw: 1.1, pitch: -.pi / 2),
            SculptureCamera(yaw: -0.6, pitch: .pi),
            SculptureCamera(yaw: -0.6, pitch: 0.35, zoom: 1.2, panX: 1.25, panY: -0.6),
        ]
        for camera in poses {
            controller.configure(
                scene: scene,
                sceneID: id,
                camera: camera,
                selectedLayer: 0,
                opacity: 0.35,
                emptyCells: []
            )
            SCNTransaction.flush()
            let reference = SculptureVoxelProjection.frame(
                sculpture,
                camera: camera,
                width: 400,
                height: 320,
                showsEmptyCells: false
            )
            var compared = 0
            for quad in reference.quads {
                let x = quad.vertices.reduce(0) { $0 + $1.x } / 4
                let y = quad.vertices.reduce(0) { $0 + $1.y } / 4
                guard x > 0, y > 0, x < 400, y < 320 else { continue }
                let expected = try #require(reference.hitTest(x: x, y: y))
                #expect(controller.hitTest(x: x, y: y) == expected)
                compared += 1
            }
            #expect(compared >= 3)
            #expect(controller.currentCamera == camera)
        }
        #expect(controller.installedSceneID == id)
        #expect(controller.meshInstallationCount == 1)
        #expect(controller.viewportSize == CGSize(width: 400, height: 320))
        #expect(controller.hitTest(x: -.infinity, y: 0) == nil)
        #expect(controller.hitTest(x: 400, y: 160) == nil)
    }

    @Test func gpuPickingChoosesTheNearestCubeOrGhostAndPreservesTheVolumeBoundary() throws {
        let controller = SculptureLiveVoxelController()
        let view = controller.makeView()
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 320)
        let camera = SculptureCamera(yaw: 0, pitch: 0)
        let empty = try blankVolume(size: 3)
        controller.configure(
            scene: try SculptureVoxelSurfaceExtractor.extract(empty),
            sceneID: UUID(),
            camera: camera,
            selectedLayer: 1,
            opacity: 0.35,
            emptyCells: [SculptureCell(x: 1, y: 1, z: 1)]
        )
        SCNTransaction.flush()
        let ghost = try #require(controller.hitTest(x: 160, y: 160))
        #expect(ghost.isEmpty)
        #expect(ghost.cell == SculptureCell(x: 1, y: 1, z: 1))
        #expect(ghost.paintCell == ghost.cell)

        var boundary = empty
        boundary.paint(SculptureCell(x: 1, y: 1, z: 2), glyph: 35)
        controller.configure(
            scene: try SculptureVoxelSurfaceExtractor.extract(boundary),
            sceneID: UUID(),
            camera: camera,
            selectedLayer: 1,
            opacity: 0.35,
            emptyCells: [SculptureCell(x: 1, y: 1, z: 1)]
        )
        SCNTransaction.flush()
        let front = try #require(controller.hitTest(x: 160, y: 160))
        #expect(!front.isEmpty)
        #expect(front.cell == SculptureCell(x: 1, y: 1, z: 2))
        #expect(front.face == .front)
        #expect(front.paintCell == nil)

        var rear = empty
        rear.paint(SculptureCell(x: 1, y: 1, z: 0), glyph: 111)
        controller.configure(
            scene: try SculptureVoxelSurfaceExtractor.extract(rear),
            sceneID: UUID(),
            camera: camera,
            selectedLayer: 2,
            opacity: 0.35,
            emptyCells: [SculptureCell(x: 1, y: 1, z: 2)]
        )
        SCNTransaction.flush()
        #expect(controller.hitTest(x: 160, y: 160)?.isEmpty == true)
        #expect(controller.hitTest(x: 160, y: 160)?.paintCell == SculptureCell(x: 1, y: 1, z: 2))
    }

    @Test func metalSnapshotRendersRealColoredGeometryAndRetainsNativeEvidence() throws {
        _ = NSApplication.shared
        var sculpture = try blankVolume(size: 7)
        for z in 2...4 {
            for y in 2...4 {
                for x in 2...4 {
                    sculpture.paint(SculptureCell(x: x, y: y, z: z), glyph: y == 2 ? 42 : x == 2 ? 111 : 64)
                }
            }
        }
        sculpture.paint(SculptureCell(x: 5, y: 1, z: 5), glyph: 43)
        let scene = try SculptureVoxelSurfaceExtractor.extract(sculpture)
        let controller = SculptureLiveVoxelController()
        let view = controller.makeView()
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 320)
        #expect(controller.renderingAPI == .metal)
        let folder = try evidenceFolder()
        let id = UUID()
        var receipts: [LiveReceipt] = []
        var images: Set<Data> = []
        for (name, camera) in [
            ("front", SculptureCamera(yaw: 0, pitch: 0)),
            ("orbit", SculptureCamera(yaw: -0.6, pitch: 0.7)),
            ("reverse", SculptureCamera(yaw: 1.8, pitch: 0.35)),
        ] {
            controller.configure(
                scene: scene,
                sceneID: id,
                camera: camera,
                selectedLayer: 3,
                opacity: 0.45,
                emptyCells: []
            )
            SCNTransaction.flush()
            let snapshot = view.snapshot()
            let image = try #require(snapshot.cgImage(forProposedRect: nil, context: nil, hints: nil))
            #expect(image.width >= 400 && image.height >= 320)
            let pixels = try rgbaPixels(image)
            let background = Array(pixels.prefix(3))
            var changedPixels = 0
            var colors: Set<UInt32> = []
            for index in stride(from: 0, to: pixels.count, by: 4) {
                if abs(Int(pixels[index]) - Int(background[0])) + abs(Int(pixels[index + 1]) - Int(background[1]))
                    + abs(Int(pixels[index + 2]) - Int(background[2])) > 12
                {
                    changedPixels += 1
                }
                colors.insert(UInt32(pixels[index]) << 16 | UInt32(pixels[index + 1]) << 8 | UInt32(pixels[index + 2]))
            }
            #expect(changedPixels > image.width * image.height / 50)
            #expect(colors.count > 32)
            let bitmap = NSBitmapImageRep(cgImage: image)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: folder.appendingPathComponent("\(name).png"), options: .atomic)
            images.insert(png)
            receipts.append(
                LiveReceipt(
                    pose: name,
                    width: image.width,
                    height: image.height,
                    yaw: camera.yaw,
                    pitch: camera.pitch,
                    renderer: "SceneKit Metal",
                    exteriorFaces: scene.surfaces.count,
                    changedPixels: changedPixels,
                    distinctColors: colors.count
                )
            )
        }
        #expect(images.count == 3)
        #expect(controller.meshInstallationCount == 1)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(receipts).write(to: folder.appendingPathComponent("receipt.json"), options: .atomic)
    }

    @Test func cameraResizeUsesTheSameMeshAndMatchesTheReferencePickingScale() throws {
        var sculpture = try blankVolume(size: 7)
        let cell = SculptureCell(x: 4, y: 1, z: 4)
        sculpture.paint(cell, glyph: 35)
        let scene = try SculptureVoxelSurfaceExtractor.extract(sculpture)
        let controller = SculptureLiveVoxelController()
        let view = controller.makeView()
        let camera = SculptureCamera(yaw: -0.4, pitch: 0.5)
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 320)
        controller.configure(
            scene: scene,
            sceneID: UUID(),
            camera: camera,
            selectedLayer: 0,
            opacity: 0.35,
            emptyCells: []
        )
        view.frame = CGRect(x: 0, y: 0, width: 640, height: 400)
        SCNTransaction.flush()
        let reference = SculptureVoxelProjection.frame(
            sculpture,
            camera: camera,
            width: 640,
            height: 400,
            showsEmptyCells: false
        )
        let quad = try #require(reference.quads.first)
        let x = quad.vertices.reduce(0) { $0 + $1.x } / 4
        let y = quad.vertices.reduce(0) { $0 + $1.y } / 4
        #expect(controller.hitTest(x: x, y: y) == reference.hitTest(x: x, y: y))
        #expect(controller.viewportSize == CGSize(width: 640, height: 400))
        #expect(controller.meshInstallationCount == 1)
    }

    @Test func denseGhostGridKeepsEveryPickTargetAndVisibleCubesWhenGridEdgesAreHidden() throws {
        _ = NSApplication.shared
        var sculpture = try Sculpture(
            title: "Dense ghost grid",
            width: 256,
            height: 256,
            layers: Array(repeating: Array(repeating: Sculpture.empty, count: 65_536), count: 3)
        )
        for y in 110...145 {
            for x in 110...145 { sculpture.paint(SculptureCell(x: x, y: y, z: 2), glyph: 43) }
        }
        let scene = try SculptureVoxelSurfaceExtractor.extract(sculpture)
        let emptyCells = (0..<65_536).map { SculptureCell(x: $0 % 256, y: $0 / 256, z: 1) }
        let controller = SculptureLiveVoxelController()
        let view = controller.makeView()
        view.frame = CGRect(x: 0, y: 0, width: 640, height: 480)
        let camera = SculptureCamera(yaw: 0, pitch: 0)
        controller.configure(
            scene: scene,
            sceneID: UUID(),
            camera: camera,
            selectedLayer: 1,
            opacity: 1,
            emptyCells: emptyCells
        )
        SCNTransaction.flush()
        let sceneRoot = try #require(view.scene?.rootNode)
        let ghostEdges = try #require(sceneRoot.childNode(withName: "voxel.empty-edges", recursively: false))
        let ghostFill = try #require(sceneRoot.childNode(withName: "voxel.empty-fill", recursively: false))
        let fillGeometry = try #require(ghostFill.geometry)
        let edgeGeometry = try #require(ghostEdges.geometry)
        #expect(ghostEdges.isHidden)
        #expect(!ghostFill.isHidden)
        #expect(fillGeometry.elements.first?.primitiveCount == 131_072)
        #expect(ghostFill.categoryBitMask == 2)
        let point = view.projectPoint(SCNVector3(-63.5, 63.5, 0))
        let hit = try #require(controller.hitTest(x: Double(point.x), y: 480 - Double(point.y)))
        #expect(hit.isEmpty)
        #expect(hit.paintCell == SculptureCell(x: 64, y: 64, z: 1))
        let image = try #require(view.snapshot().cgImage(forProposedRect: nil, context: nil, hints: nil))
        let pixels = try rgbaPixels(image)
        var bluePixels = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            if Int(pixels[index + 2]) > Int(pixels[index]) + 20,
                Int(pixels[index + 1]) > Int(pixels[index]) + 10
            {
                bluePixels += 1
            }
        }
        #expect(bluePixels > image.width * image.height / 2_000)
        let folder = try evidenceFolder()
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try png.write(to: folder.appendingPathComponent("dense-ghost-grid.png"), options: .atomic)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(
            DenseGridReceipt(
                width: image.width,
                height: image.height,
                retainedGhostTargets: emptyCells.count,
                ghostEdgesHidden: ghostEdges.isHidden,
                bluePixels: bluePixels
            )
        )
        .write(to: folder.appendingPathComponent("receipt.json"), options: .atomic)
        controller.updateCamera(SculptureCamera(yaw: 0, pitch: 0, zoom: 2))
        SCNTransaction.flush()
        #expect(!ghostEdges.isHidden)
        #expect(ghostFill.geometry === fillGeometry)
        #expect(ghostEdges.geometry === edgeGeometry)
        #expect(controller.meshInstallationCount == 1)
        controller.updateCamera(SculptureCamera(yaw: 0, pitch: 1.4, zoom: 2))
        #expect(ghostEdges.isHidden)
        #expect(ghostFill.geometry === fillGeometry)
    }

    private func blankVolume(size: Int) throws -> Sculpture {
        try Sculpture(
            title: "Live rendering fixture",
            width: size,
            height: size,
            layers: Array(repeating: Array(repeating: Sculpture.empty, count: size * size), count: size)
        )
    }

    private func evidenceFolder() throws -> URL {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folder = repository.appendingPathComponent(".build/verification/live-voxel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func rgbaPixels(_ image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
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
        return bytes
    }

    private struct LiveReceipt: Codable {
        let pose: String
        let width: Int
        let height: Int
        let yaw: Double
        let pitch: Double
        let renderer: String
        let exteriorFaces: Int
        let changedPixels: Int
        let distinctColors: Int
    }

    private struct DenseGridReceipt: Codable {
        let width: Int
        let height: Int
        let retainedGhostTargets: Int
        let ghostEdgesHidden: Bool
        let bluePixels: Int
    }
}
