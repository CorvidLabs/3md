import Foundation
import RookRendering
import RookSculpture
import Testing

@Test func singleVoxelSurfaceIncludesEveryFaceAndItsEmptyNeighborInStableOrder() throws {
    var sculpture = try surfaceVolume(width: 3, height: 3, depth: 3)
    let center = SculptureCell(x: 1, y: 1, z: 1)
    sculpture.paint(center, glyph: 64)
    let scene = try SculptureVoxelSurfaceExtractor.extract(sculpture)
    #expect(scene.width == 3 && scene.height == 3 && scene.depth == 3)
    #expect(scene.occupiedCount == 1)
    #expect(scene.surfaces.count == 6)
    #expect(scene.surfaces.map(\.face) == SculptureVoxelFace.allCases)
    #expect(scene.surfaces.allSatisfy { $0.cell == center && $0.glyph == 64 })
    #expect(
        scene.surfaces.map(\.adjacentCell) == [
            SculptureCell(x: 0, y: 1, z: 1), SculptureCell(x: 2, y: 1, z: 1),
            SculptureCell(x: 1, y: 0, z: 1), SculptureCell(x: 1, y: 2, z: 1),
            SculptureCell(x: 1, y: 1, z: 0), SculptureCell(x: 1, y: 1, z: 2),
        ]
    )
    #expect(try SculptureVoxelSurfaceExtractor.extract(sculpture) == scene)
}

@Test func neighboringMaterialsOmitSharedInteriorFaces() throws {
    let sculpture = try Sculpture(title: "Joined", width: 2, height: 1, layers: [[35, 64]])
    let scene = try SculptureVoxelSurfaceExtractor.extract(sculpture)
    #expect(scene.surfaces.count == 10)
    #expect(scene.surfaces.filter { $0.glyph == 35 }.count == 5)
    #expect(scene.surfaces.filter { $0.glyph == 64 }.count == 5)
    #expect(!scene.surfaces.contains { $0.cell.x == 0 && $0.face == .right })
    #expect(!scene.surfaces.contains { $0.cell.x == 1 && $0.face == .left })
    #expect(scene.surfaces.allSatisfy { $0.adjacentCell == nil })
    #expect(scene.surfaces.map(\.cell.x) == Array(repeating: 0, count: 5) + Array(repeating: 1, count: 5))
}

@Test func hollowVolumeRetainsCavityFacesWithoutExposingJoinedFaces() throws {
    var layers = Array(repeating: Array(repeating: UInt8(35), count: 9), count: 3)
    layers[1][4] = Sculpture.empty
    let sculpture = try Sculpture(title: "Cavity", width: 3, height: 3, layers: layers)
    let scene = try SculptureVoxelSurfaceExtractor.extract(sculpture)
    #expect(scene.occupiedCount == 26)
    #expect(scene.surfaces.count == 60)
    let cavity = SculptureCell(x: 1, y: 1, z: 1)
    #expect(scene.surfaces.filter { $0.adjacentCell == cavity }.count == 6)
    #expect(scene.surfaces.filter { $0.adjacentCell == nil }.count == 54)
    #expect(
        scene.surfaces.allSatisfy { surface in
            guard let adjacent = surface.adjacentCell else { return true }
            return sculpture.glyph(at: adjacent) == Sculpture.empty
        }
    )
}

@Test func sparseFinalCellOfMaximumVolumeHasSixCorrectlyBoundedFaces() throws {
    var sculpture = try surfaceVolume(width: 256, height: 256, depth: 256)
    let corner = SculptureCell(x: 255, y: 255, z: 255)
    sculpture.paint(corner, glyph: 111)
    let scene = try SculptureVoxelSurfaceExtractor.extract(sculpture)
    #expect(scene.width == 256 && scene.height == 256 && scene.depth == 256)
    #expect(scene.occupiedCount == 1 && scene.surfaces.count == 6)
    #expect(scene.surfaces.allSatisfy { $0.cell == corner && $0.glyph == 111 })
    #expect(scene.surfaces.filter { $0.adjacentCell == nil }.map(\.face) == [.right, .bottom, .front])
    #expect(
        scene.surfaces.compactMap(\.adjacentCell) == [
            SculptureCell(x: 254, y: 255, z: 255),
            SculptureCell(x: 255, y: 254, z: 255),
            SculptureCell(x: 255, y: 255, z: 254),
        ]
    )
}

@Test func cachedOccupancySupportsBoundsAndIndependentSurfaceSnapshotsAfterEditing() throws {
    var sculpture = try surfaceVolume(width: 4, height: 4, depth: 2)
    let first = try SculptureVoxelSurfaceExtractor.extract(sculpture)
    #expect(first.surfaces.isEmpty && first.occupiedCount == 0)
    #expect(!sculpture.containsOccupiedCells(inLayer: -1))
    #expect(!sculpture.containsOccupiedCells(inLayer: 2))
    #expect(!sculpture.containsOccupiedCells(inRow: -1, ofLayer: 0))
    #expect(!sculpture.containsOccupiedCells(inRow: 4, ofLayer: 0))
    #expect(!sculpture.containsOccupiedCells(inRow: 0, ofLayer: 2))
    sculpture.paint(SculptureCell(x: 3, y: 0, z: 1), glyph: 35)
    #expect(sculpture.containsOccupiedCells(inLayer: 1))
    #expect(sculpture.containsOccupiedCells(inRow: 0, ofLayer: 1))
    let second = try SculptureVoxelSurfaceExtractor.extract(sculpture)
    try sculpture.rotateLayer(at: 1)
    #expect(!sculpture.containsOccupiedCells(inRow: 0, ofLayer: 1))
    #expect(sculpture.containsOccupiedCells(inRow: 3, ofLayer: 1))
    let third = try SculptureVoxelSurfaceExtractor.extract(sculpture)
    #expect(second.surfaces.allSatisfy { $0.cell == SculptureCell(x: 3, y: 0, z: 1) })
    #expect(third.surfaces.allSatisfy { $0.cell == SculptureCell(x: 3, y: 3, z: 1) })
    #expect(first.surfaces.isEmpty)
}

@Test func disconnectedSurfaceBudgetThrowsInsteadOfReturningPartialGeometry() throws {
    let size = 64
    let layers = (0..<size).map { z in
        (0..<(size * size)).map { index in
            (index % size + index / size + z).isMultiple(of: 2) ? UInt8(35) : Sculpture.empty
        }
    }
    let sculpture = try Sculpture(title: "Surface limit", width: size, height: size, layers: layers)
    #expect(SculptureVoxelSurfaceExtractor.maximumFaces == 500_000)
    #expect(sculpture.occupiedCount * 6 > SculptureVoxelSurfaceExtractor.maximumFaces)
    #expect(throws: SculptureVoxelSurfaceError.tooManyFaces) {
        _ = try SculptureVoxelSurfaceExtractor.extract(sculpture)
    }
}

@Test func cancelledSurfaceExtractionReturnsNoPartialScene() async throws {
    let sculpture = Sculpture.orb()
    #expect(!(try SculptureVoxelSurfaceExtractor.extract(sculpture)).surfaces.isEmpty)
    let barrier = SurfaceCancellationBarrier()
    let task = Task {
        await barrier.wait()
        return try SculptureVoxelSurfaceExtractor.extract(sculpture)
    }
    task.cancel()
    await barrier.release()
    await #expect(throws: CancellationError.self) { try await task.value }
}

private func surfaceVolume(width: Int, height: Int, depth: Int) throws -> Sculpture {
    try Sculpture(
        title: "Surface volume",
        width: width,
        height: height,
        layers: Array(repeating: Array(repeating: Sculpture.empty, count: width * height), count: depth)
    )
}

private actor SurfaceCancellationBarrier {
    private var released = false
    private var waiter: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func release() {
        released = true
        waiter?.resume()
        waiter = nil
    }
}
