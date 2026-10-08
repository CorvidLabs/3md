import Foundation
import RookSculpture
import Testing

@testable import RookRendering

@Suite("Bounded colored world silhouettes")
struct SculptureWorldCoarseMeshTests {
    @Test func emptyVolumeHasNoGeometryAndSmallModelsMatchFullDetail() throws {
        let empty = try volume(width: 31, height: 7, depth: 1)
        let emptyMesh = try SculptureWorldCoarseMesh.prepare(empty)
        #expect(emptyMesh.originalDimensions == SIMD3(31, 7, 1))
        #expect(emptyMesh.scene.width == 16 && emptyMesh.scene.height == 4 && emptyMesh.scene.depth == 1)
        #expect(emptyMesh.faceCount == 0 && emptyMesh.scene.occupiedCount == 0)
        #expect(emptyMesh.buffers.positions.isEmpty && emptyMesh.buffers.colors.isEmpty)
        #expect(emptyMesh.buffers.triangles.isEmpty && emptyMesh.buffers.lines.isEmpty)

        let single = try Sculpture(title: "One cell", width: 1, height: 1, layers: [[111]])
        let singleMesh = try SculptureWorldCoarseMesh.prepare(single)
        #expect(singleMesh.stride == 1 && singleMesh.scale == SIMD3<Float>(repeating: 1))
        #expect(singleMesh.faceCount == 6 && singleMesh.scene.occupiedCount == 1)
        var small = try volume(width: 16, height: 9, depth: 3)
        small.paint(.init(x: 1, y: 2, z: 0), glyph: 35)
        small.paint(.init(x: 2, y: 2, z: 0), glyph: 64)
        small.paint(.init(x: 15, y: 8, z: 2), glyph: 111)
        let detailed = try SculptureVoxelMeshBuffers.prepare(SculptureVoxelSurfaceExtractor.extract(small))
        let coarse = try SculptureWorldCoarseMesh.prepare(small)
        #expect(coarse.stride == 1 && coarse.scale == SIMD3<Float>(repeating: 1))
        #expect(coarse.scene == detailed.scene)
        #expect(coarse.buffers.positions == detailed.positions && coarse.buffers.colors == detailed.colors)
        #expect(coarse.buffers.triangles == detailed.triangles && coarse.buffers.lines == detailed.lines)
    }

    @Test func dominantNonemptyMaterialAndPaletteOrderTiesAreDeterministic() throws {
        var cells = [UInt8](repeating: Sculpture.empty, count: 64)
        cells[0] = 35
        cells[1] = 64
        cells[2] = 64
        cells[4] = 64
        cells[5] = 35
        cells[9] = 111
        let sculpture = try Sculpture(title: "Dominant bins", width: 64, height: 1, layers: [cells])
        let mesh = try SculptureWorldCoarseMesh.prepare(sculpture)
        #expect(mesh.stride == 4 && mesh.scene.occupiedCount == 3 && mesh.faceCount == 14)
        #expect(Set(mesh.scene.surfaces.filter { $0.cell.x == 0 }.map(\.glyph)) == [64])
        #expect(Set(mesh.scene.surfaces.filter { $0.cell.x == 1 }.map(\.glyph)) == [35])
        #expect(Set(mesh.scene.surfaces.filter { $0.cell.x == 2 }.map(\.glyph)) == [111])
        let repeated = try SculptureWorldCoarseMesh.prepare(sculpture)
        #expect(repeated.scene == mesh.scene)
        #expect(repeated.buffers.positions == mesh.buffers.positions && repeated.buffers.colors == mesh.buffers.colors)
        #expect(repeated.buffers.triangles == mesh.buffers.triangles && repeated.buffers.lines == mesh.buffers.lines)
        var oneMaterial = [UInt8](repeating: Sculpture.empty, count: 64)
        for x in [0, 4, 8] { oneMaterial[x] = 35 }
        let solid = try Sculpture(title: "One material", width: 64, height: 1, layers: [oneMaterial])
        let solidMesh = try SculptureWorldCoarseMesh.prepare(solid)
        #expect(
            mesh.buffers.positions == solidMesh.buffers.positions
                && mesh.buffers.triangles == solidMesh.buffers.triangles
        )
        #expect(mesh.buffers.colors != solidMesh.buffers.colors)
    }

    @Test func thinRoofTrunkAndGroundKeepARecognizableSilhouetteInsteadOfAFullBox() throws {
        var sculpture = try volume(width: 32, height: 32, depth: 32)
        for z in 0..<32 {
            for x in 0..<32 { sculpture.paint(.init(x: x, y: 31, z: z), glyph: 43) }
        }
        for z in 4..<28 {
            for x in 4..<28 { sculpture.paint(.init(x: x, y: 4, z: z), glyph: 64) }
        }
        for y in 5..<31 { sculpture.paint(.init(x: 16, y: y, z: 16), glyph: 111) }
        let silhouette = try SculptureWorldCoarseMesh.prepare(sculpture)
        let solid = try SculptureWorldCoarseMesh.prepare(volume(width: 32, height: 32, depth: 32, glyph: 35))
        #expect(silhouette.stride == 2 && silhouette.scale == SIMD3<Float>(repeating: 2))
        #expect(silhouette.scene.occupiedCount < solid.scene.occupiedCount)
        #expect(silhouette.faceCount > 6 && silhouette.faceCount < solid.faceCount)
        #expect(silhouette.scene.surfaces.contains { $0.cell == .init(x: 2, y: 2, z: 2) && $0.glyph == 64 })
        #expect(silhouette.scene.surfaces.contains { $0.cell == .init(x: 8, y: 10, z: 8) && $0.glyph == 111 })
        #expect(silhouette.scene.surfaces.contains { $0.cell.y == 15 && $0.glyph == 43 })
        #expect(!silhouette.scene.surfaces.contains { $0.cell == .init(x: 0, y: 7, z: 0) })
    }

    @Test func oddDimensionsAndPartialBinsPreserveRealExtentsAndCenter() throws {
        let sculpture = try volume(width: 31, height: 17, depth: 5, glyph: 35)
        let mesh = try SculptureWorldCoarseMesh.prepare(sculpture)
        #expect(mesh.originalDimensions == SIMD3(31, 17, 5))
        #expect(mesh.scene.width == 16 && mesh.scene.height == 9 && mesh.scene.depth == 3 && mesh.stride == 2)
        let bounds = scaledBounds(mesh)
        for axis in 0..<3 {
            let halfExtent = Float(mesh.originalDimensions[axis]) / 2
            #expect(abs(bounds.minimum[axis] + halfExtent) < 0.0001)
            #expect(abs(bounds.maximum[axis] - halfExtent) < 0.0001)
            #expect(abs(bounds.minimum[axis] + bounds.maximum[axis]) < 0.0001)
        }
    }

    @Test func maximumStrideCountsDenseBinsWithoutOverflowOrOversizedGrid() throws {
        let sculpture = try volume(width: 256, height: 16, depth: 16, glyph: 111)
        let mesh = try SculptureWorldCoarseMesh.prepare(sculpture)
        #expect(mesh.stride == 16 && mesh.scale == SIMD3<Float>(repeating: 16))
        #expect(mesh.scene.width == 16 && mesh.scene.height == 1 && mesh.scene.depth == 1)
        #expect(mesh.scene.occupiedCount == 16 && mesh.faceCount == 66)
        #expect(mesh.scene.surfaces.allSatisfy { $0.glyph == 111 })
        let bounds = scaledBounds(mesh)
        #expect(bounds.minimum == SIMD3<Float>(-128, -8, -8) && bounds.maximum == SIMD3<Float>(128, 8, 8))
    }

    @Test func disconnectedCoarseGridStaysBelowTheExplicitFaceAndByteBudgets() throws {
        let layers = (0..<16).map { z in
            (0..<256).map { offset in
                (offset % 16 + offset / 16 + z).isMultiple(of: 2) ? UInt8(35) : Sculpture.empty
            }
        }
        let sculpture = try Sculpture(title: "Disconnected grid", width: 16, height: 16, layers: layers)
        let mesh = try SculptureWorldCoarseMesh.prepare(sculpture)
        #expect(SculptureWorldCoarseMesh.maximumDimension == 16 && SculptureWorldCoarseMesh.maximumFaces == 24_576)
        #expect(mesh.scene.occupiedCount == 2_048 && mesh.faceCount == 12_288)
        #expect(mesh.faceCount <= SculptureWorldCoarseMesh.maximumFaces)
        #expect(mesh.buffers.byteCount <= SculptureWorldCoarseMesh.maximumFaces * 200)
    }

    @Test func cancellationReturnsNoPartialCoarseResult() async throws {
        let sculpture = try volume(width: 64, height: 32, depth: 16, glyph: 35)
        let barrier = CoarseMeshCancellationBarrier()
        let task = Task {
            await barrier.wait()
            return try SculptureWorldCoarseMesh.prepare(sculpture)
        }
        task.cancel()
        await barrier.release()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    private func volume(width: Int, height: Int, depth: Int, glyph: UInt8 = Sculpture.empty) throws -> Sculpture {
        try Sculpture(
            title: "Coarse fixture",
            width: width,
            height: height,
            layers: Array(repeating: Array(repeating: glyph, count: width * height), count: depth)
        )
    }

    private func scaledBounds(_ mesh: SculptureWorldCoarseMeshResult) -> (minimum: SIMD3<Float>, maximum: SIMD3<Float>)
    {
        mesh.buffers.positions.withUnsafeBytes { bytes in
            let positions = bytes.bindMemory(to: Float.self)
            var minimum = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
            var maximum = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
            for index in stride(from: 0, to: positions.count, by: 3) {
                let point = SIMD3(positions[index], positions[index + 1], positions[index + 2]) * mesh.scale
                for axis in 0..<3 {
                    minimum[axis] = min(minimum[axis], point[axis])
                    maximum[axis] = max(maximum[axis], point[axis])
                }
            }
            return (minimum, maximum)
        }
    }
}

private actor CoarseMeshCancellationBarrier {
    private var released = false
    private var waiter: CheckedContinuation<Void, Never>?
    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func release() { released = true; waiter?.resume(); waiter = nil }
}
