import AppKit
import Foundation
import RookSculpture
import SceneKit
import Testing
import simd

@testable import RookRendering

struct SculptureVoxelMeshBuffersTests {
    @Test func packedBytesPreserveEveryMaterialFaceWindingAndStablePickingIndex() throws {
        var sculpture = try meshTestBlank(width: 7, height: 7, depth: 7)
        for (index, glyph) in Sculpture.palette.enumerated() {
            sculpture.paint(.init(x: 1 + index % 3 * 2, y: 1 + index / 3 * 2, z: 3), glyph: glyph)
        }
        let scene = try SculptureVoxelSurfaceExtractor.extract(sculpture)
        let buffers = try SculptureVoxelMeshBuffers.prepare(scene)
        let positions: [Float] = decode(buffers.positions)
        let colors: [Float] = decode(buffers.colors)
        let triangles: [UInt32] = decode(buffers.triangles)
        let lines: [UInt32] = decode(buffers.lines)
        #expect(scene.surfaces.count == 54)
        #expect(buffers.byteCount == scene.surfaces.count * 200)
        #expect(positions.count == scene.surfaces.count * 12)
        #expect(colors.count == scene.surfaces.count * 16)
        #expect(triangles.count == scene.surfaces.count * 6)
        #expect(lines.count == scene.surfaces.count * 8)
        for (index, surface) in scene.surfaces.enumerated() {
            let base = UInt32(index * 4)
            #expect(
                Array(triangles[(index * 6)..<(index * 6 + 6)]) == [base, base + 1, base + 2, base, base + 2, base + 3]
            )
            #expect(
                Array(lines[(index * 8)..<(index * 8 + 8)]) == [
                    base, base + 1, base + 1, base + 2, base + 2, base + 3, base + 3, base,
                ]
            )
            let vertices = (0..<4).map { vertex -> SIMD3<Float> in
                let offset = index * 12 + vertex * 3
                return SIMD3(positions[offset], positions[offset + 1], positions[offset + 2])
            }
            let normal = simd_cross(vertices[1] - vertices[0], vertices[2] - vertices[0])
            #expect(simd_dot(normal, outwardNormal(surface.face)) > 0.99)
            let center = SIMD3<Float>(Float(surface.cell.x - 3), Float(3 - surface.cell.y), Float(surface.cell.z - 3))
            #expect(vertices.allSatisfy { simd_abs($0 - center) == SIMD3<Float>(repeating: 0.5) })
            let tint = SculptureVoxelRasterizer.color(for: surface.glyph)
            let level = brightness(surface.face)
            for vertex in 0..<4 {
                let offset = index * 16 + vertex * 4
                #expect(colors[offset] == Float(tint.red * level))
                #expect(colors[offset + 1] == Float(tint.green * level))
                #expect(colors[offset + 2] == Float(tint.blue * level))
                #expect(colors[offset + 3] == 1)
            }
        }
        #expect(buffers.layerRanges == [3: NSRange(location: 0, length: scene.surfaces.count * 4)])
        #expect(buffers.selectionLines == [3: buffers.lines])
        let empty = try SculptureVoxelMeshBuffers.prepare(
            SculptureVoxelSurfaceExtractor.extract(meshTestBlank(width: 1, height: 1, depth: 1))
        )
        #expect(empty.byteCount == 0 && empty.layerRanges.isEmpty && empty.selectionLines.isEmpty)
    }

    @Test func ghostBuffersPreserveFilteringOrderDepthCoordinatesAndExactTargetCapacity() throws {
        let scene = try SculptureVoxelSurfaceExtractor.extract(meshTestBlank(width: 256, height: 256, depth: 1))
        let cells = [
            SculptureCell(x: -1, y: 0, z: 0), .init(x: 9, y: 4, z: 1),
            .init(x: 3, y: 2, z: 0), .init(x: 255, y: 255, z: 0), .init(x: 4, y: 3, z: 0),
        ]
        let filtered = try SculptureVoxelGhostBuffers.prepare(cells: cells, scene: scene, selectedLayer: 0)
        #expect(filtered.cells == Array(cells.suffix(3)))
        let positions: [Float] = decode(filtered.positions)
        #expect(positions[0] == -125 && positions[1] == 126 && positions[2] == 0)
        let grid = (0..<256).flatMap { y in (0..<256).map { x in SculptureCell(x: x, y: y, z: 0) } }
        let dense = try SculptureVoxelGhostBuffers.prepare(
            cells: grid + [.init(x: 4, y: 4, z: 0)],
            scene: scene,
            selectedLayer: 0
        )
        #expect(dense.cells.count == 65_536)
        #expect(dense.cells.first == .init(x: 0, y: 0, z: 0))
        #expect(dense.cells.last == .init(x: 255, y: 255, z: 0))
        #expect(dense.byteCount == 65_536 * 104)
        let triangles: [UInt32] = decode(dense.triangles)
        #expect(triangles.count == 65_536 * 6)
        #expect(triangles.last == UInt32(65_536 * 4 - 1))
    }

    @Test func placementChangesReuseImmutablePreparedModelsButDefinitionChangesInvalidateThem() throws {
        let initial = try meshTestWorld(origin: .init(x: 0, y: 0, z: 0), turns: 0, glyph: 35)
        let scene = try SculptureWorldScene.prepare(initial)
        let prior = try #require(scene.preparedMeshes["part"])
        let moved = try meshTestWorld(origin: .init(x: 20, y: -9, z: 7), turns: 1, glyph: 35)
        let reused = try SculptureWorldScene.prepare(moved, cachedModels: scene)
        #expect(reused.preparedMeshes["part"]?.identity == prior.identity)
        #expect(reused.world.instances[0].origin == moved.instances[0].origin)
        #expect(reused.world.instances[0].quarterTurns == 1)
        let changed = try meshTestWorld(origin: .init(x: 20, y: -9, z: 7), turns: 1, glyph: 111)
        let replaced = try SculptureWorldScene.prepare(changed, cachedModels: reused)
        #expect(replaced.preparedMeshes["part"]?.identity != prior.identity)
        #expect(replaced.models["part"]?.surfaces.allSatisfy { $0.glyph == 111 } == true)
        let changedColors = try #require(replaced.preparedMeshes["part"]?.colors)
        #expect(changedColors != prior.colors)
    }

    @Test func canceledWorkersNeverPublishPartialMeshGhostsOrReusedWorldScenes() async throws {
        let world = try meshTestWorld(origin: .init(x: 0, y: 0, z: 0), turns: 0, glyph: 35)
        let scene = try SculptureWorldScene.prepare(world)
        let surface = try #require(scene.models["part"])
        for operation in 0..<3 {
            let gate = MeshCancellationGate()
            let task = Task {
                await gate.wait()
                switch operation {
                case 0: _ = try SculptureVoxelMeshBuffers.prepare(surface)
                case 1:
                    _ = try SculptureVoxelGhostBuffers.prepare(
                        cells: [.init(x: 0, y: 0, z: 0)],
                        scene: surface,
                        selectedLayer: 0
                    )
                default: _ = try SculptureWorldScene.prepare(world, cachedModels: scene)
                }
            }
            task.cancel()
            await gate.release()
            await #expect(throws: CancellationError.self) { try await task.value }
        }
    }

    private func decode<T: BitwiseCopyable>(_ data: Data) -> [T] {
        data.withUnsafeBytes { bytes in
            stride(from: 0, to: bytes.count, by: MemoryLayout<T>.stride).map {
                bytes.loadUnaligned(fromByteOffset: $0, as: T.self)
            }
        }
    }

    private func outwardNormal(_ face: SculptureVoxelFace) -> SIMD3<Float> {
        switch face {
        case .left: SIMD3(-1, 0, 0)
        case .right: SIMD3(1, 0, 0)
        case .top: SIMD3(0, 1, 0)
        case .bottom: SIMD3(0, -1, 0)
        case .back: SIMD3(0, 0, -1)
        case .front: SIMD3(0, 0, 1)
        }
    }

    private func brightness(_ face: SculptureVoxelFace) -> Double {
        switch face {
        case .left: 0.85
        case .right: 0.61
        case .top: 0.96
        case .bottom: 0.5
        case .back: 0.63
        case .front: 0.83
        }
    }
}

@Suite(.serialized)
@MainActor
struct SculpturePreparedNativeMeshTests {
    @Test func selectedSliceOutlineMovesToTheChosenDepthInTheActualMetalImage() throws {
        var sculpture = try meshTestBlank(width: 9, height: 9, depth: 9)
        sculpture.paint(.init(x: 2, y: 4, z: 1), glyph: 35)
        sculpture.paint(.init(x: 6, y: 4, z: 7), glyph: 35)
        let scene = try SculptureVoxelSurfaceExtractor.extract(sculpture)
        let mesh = try SculptureVoxelMeshBuffers.prepare(scene)
        let controller = SculptureLiveVoxelController()
        let view = controller.makeView()
        view.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let id = UUID()
        for layer in [1, 7, 1] {
            controller.configure(
                scene: scene,
                sceneID: id,
                camera: .init(yaw: 0, pitch: 0),
                selectedLayer: layer,
                opacity: 0.35,
                emptyCells: [],
                preparedMesh: mesh
            )
            let root = try #require(view.scene?.rootNode)
            root.childNode(withName: "voxel.surface", recursively: false)?.isHidden = true
            root.childNode(withName: "voxel.edges", recursively: false)?.isHidden = true
            SCNTransaction.flush()
            let image = try #require(view.snapshot().cgImage(forProposedRect: nil, context: nil, hints: nil))
            let bitmap = NSBitmapImageRep(cgImage: image)
            var left = 0
            var right = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                        color.redComponent > 0.6, color.greenComponent > 0.45, color.blueComponent < 0.5
                    else { continue }
                    if x < bitmap.pixelsWide / 2 { left += 1 } else { right += 1 }
                }
            }
            #expect(
                layer == 1 ? left > 20 && right == 0 : right > 20 && left == 0,
                "Selected layer \(layer): actual amber pixels left=\(left), right=\(right)."
            )
        }
        #expect(controller.meshInstallationCount == 1)
    }

    @Test func preparedCanvasRetainsPickingAndSelectedOutlineWhenDenseGridLODChanges() throws {
        var sculpture = try meshTestBlank(width: 192, height: 64, depth: 192)
        sculpture.paint(.init(x: 96, y: 32, z: 96), glyph: 43)
        let scene = try SculptureVoxelSurfaceExtractor.extract(sculpture)
        let mesh = try SculptureVoxelMeshBuffers.prepare(scene)
        let ghosts = try SculptureVoxelGhostBuffers.prepare(
            cells: [.init(x: 95, y: 32, z: 96)],
            scene: scene,
            selectedLayer: 96
        )
        let controller = SculptureLiveVoxelController()
        let view = controller.makeView()
        view.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let id = UUID()
        controller.configure(
            scene: scene,
            sceneID: id,
            camera: .init(yaw: 0, pitch: 0, zoom: 0.5),
            selectedLayer: 96,
            opacity: 0.35,
            emptyCells: ghosts.cells,
            preparedMesh: mesh,
            preparedGhosts: ghosts
        )
        let root = try #require(view.scene?.rootNode)
        let fill = try #require(root.childNode(withName: "voxel.surface", recursively: false))
        let edges = try #require(root.childNode(withName: "voxel.edges", recursively: false))
        let selected = try #require(root.childNode(withName: "voxel.selected-edges", recursively: false))
        let geometry = try #require(fill.geometry)
        let source = try #require(geometry.sources(for: .vertex).first)
        #expect(source.data == mesh.positions)
        #expect(edges.isHidden && !selected.isHidden && !fill.isHidden)
        for zoom in [0.5, 2.0, 0.5] {
            controller.configure(
                scene: scene,
                sceneID: id,
                camera: .init(yaw: 0, pitch: 0, zoom: zoom),
                selectedLayer: 96,
                opacity: 0.65,
                emptyCells: ghosts.cells,
                preparedMesh: mesh,
                preparedGhosts: ghosts
            )
            SCNTransaction.flush()
            #expect(edges.isHidden == (zoom == 0.5))
            #expect(!selected.isHidden)
            #expect(fill.geometry === geometry)
            #expect(geometry.sources(for: .vertex).first === source)
            let occupied = view.projectPoint(SCNVector3(0.5, -0.5, 0.5))
            let empty = view.projectPoint(SCNVector3(-0.5, -0.5, 0.5))
            let hit = try #require(controller.hitTest(x: Double(occupied.x), y: 600 - Double(occupied.y)))
            let ghost = try #require(controller.hitTest(x: Double(empty.x), y: 600 - Double(empty.y)))
            #expect(hit.cell == .init(x: 96, y: 32, z: 96) && hit.face == .front && !hit.isEmpty)
            #expect(ghost.cell == .init(x: 95, y: 32, z: 96) && ghost.isEmpty)
        }
        #expect(controller.meshInstallationCount == 1)
    }

    @Test func movedAndRotatedWorldInstancesKeepActualModelGeometryAndNearestPicks() throws {
        let initial = try meshTestWorld(origin: .init(x: 0, y: 0, z: 0), turns: 0, glyph: 35)
        let scene = try SculptureWorldScene.prepare(initial)
        let controller = SculptureLiveWorldController()
        let view = controller.makeView()
        view.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        controller.configure(
            scene: scene,
            sceneID: UUID(),
            focus: .init(x: 0, y: 0, z: 0),
            renderDistance: 192,
            detailDistance: 192,
            camera: .init(yaw: 0, pitch: 0, zoom: 0.5)
        )
        let node = try #require(view.scene?.rootNode.childNode(withName: "world.instance.placed", recursively: true))
        let original = try #require(node.childNodes.first?.geometry)
        let source = try #require(original.sources(for: .vertex).first)
        let oldEdge = try #require(node.childNodes.first { $0.geometry?.elements.first?.primitiveType == .line })
        #expect(oldEdge.isHidden)
        let moved = try meshTestWorld(origin: .init(x: 7, y: 2, z: 3), turns: 1, glyph: 35)
        let next = try SculptureWorldScene.prepare(moved, cachedModels: scene)
        controller.configure(
            scene: next,
            sceneID: UUID(),
            focus: .init(x: 7, y: 2, z: 3),
            renderDistance: 16,
            detailDistance: 16,
            camera: .init(yaw: 0, pitch: 0, zoom: 1)
        )
        SCNTransaction.flush()
        let rotated = try #require(view.scene?.rootNode.childNode(withName: "world.instance.placed", recursively: true))
        #expect(rotated.childNodes.first?.geometry === original)
        #expect(original.sources(for: .vertex).first === source)
        #expect(controller.meshInstallationCount == 1)
        #expect(abs(rotated.eulerAngles.z + .pi / 2) < 0.0001)
        let edge = try #require(rotated.childNodes.first { $0.geometry?.elements.first?.primitiveType == .line })
        #expect(!edge.isHidden)
        let center = view.projectPoint(rotated.position)
        #expect(controller.hitTest(x: Double(center.x), y: 600 - Double(center.y)) == "placed")
        let changed = try meshTestWorld(origin: moved.instances[0].origin, turns: 1, glyph: 111)
        let replacement = try SculptureWorldScene.prepare(changed, cachedModels: next)
        controller.configure(
            scene: replacement,
            sceneID: UUID(),
            focus: .init(x: 7, y: 2, z: 3),
            renderDistance: 16,
            detailDistance: 16,
            camera: .init()
        )
        #expect(controller.meshInstallationCount == 2)
        let changedNode = try #require(
            view.scene?.rootNode.childNode(withName: "world.instance.placed", recursively: true)
        )
        #expect(changedNode.childNodes.first?.geometry !== original)
    }
}

private func meshTestBlank(width: Int, height: Int, depth: Int) throws -> Sculpture {
    try Sculpture(
        title: "Mesh fixture",
        width: width,
        height: height,
        layers: Array(repeating: Array(repeating: Sculpture.empty, count: width * height), count: depth)
    )
}

private func meshTestWorld(origin: SculptureWorldPoint, turns: Int, glyph: UInt8) throws -> SculptureWorld {
    let leaf = try Sculpture(title: "Shared part", width: 3, height: 2, layers: [Array(repeating: glyph, count: 6)])
    let map = try SculptureTileMap(
        width: 1,
        height: 1,
        layers: [[65]],
        tileSize: .init(width: 3, height: 2, depth: 1),
        bindings: [.init(glyph: 65, modelID: "part")]
    )
    let library = try SculptureComposition(
        title: "Mesh library",
        rootID: "root",
        models: ["root": .tiles(map), "part": .sculpture(leaf)]
    )
    let instance = try SculptureWorldInstance(id: "placed", modelID: "part", origin: origin, quarterTurns: turns)
    return try SculptureWorld(title: "Mesh world", library: library, instances: [instance])
}

private actor MeshCancellationGate {
    private var released = false
    private var waiter: CheckedContinuation<Void, Never>?
    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func release() { released = true; waiter?.resume(); waiter = nil }
}
