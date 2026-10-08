import RookRendering
import RookSculpture
import Testing

@testable import RookApp

private func frontHit(_ sculpture: Sculpture) throws -> SculptureVoxelHit {
    let frame = SculptureVoxelProjection.frame(
        sculpture,
        camera: SculptureCamera(yaw: 0, pitch: 0),
        width: 500,
        height: 500
    )
    return try #require(frame.hitTest(x: 250, y: 250))
}

@MainActor @Test func cubeSurfacePaintingAddsTheNeighborAndUndoRestoresTheOriginal() throws {
    var volume = try Sculpture(
        title: "Cube editing",
        width: 3,
        height: 3,
        layers: Array(repeating: Array(repeating: Sculpture.empty, count: 9), count: 3)
    )
    volume.paint(SculptureCell(x: 1, y: 1, z: 1), glyph: 35)
    let workspace = SculptureWorkspace()
    workspace.replace(with: volume, opened: true)
    workspace.brush = 64
    workspace.brushSize = 5  // Slice brushes do not unexpectedly stamp an entire 3D face.
    let hit = try frontHit(volume)
    #expect(hit.paintCell == SculptureCell(x: 1, y: 1, z: 2))
    #expect(workspace.paintVoxel(hit, start: true))
    workspace.endStroke()
    #expect(workspace.sculpture.occupiedCount == 2)
    #expect(workspace.sculpture.glyph(at: hit.cell) == 35)
    #expect(workspace.sculpture.glyph(at: try #require(hit.paintCell)) == 64)
    #expect(workspace.layer == 2)
    workspace.undo()
    #expect(workspace.sculpture == volume)
    #expect(!workspace.canUndo)
    #expect(!workspace.isDirty)
    workspace.redo()
    #expect(workspace.sculpture.occupiedCount == 2)
}

@MainActor @Test func cubeEraseTargetsTheClickedCubeAndFullBoundaryDoesNotCreateHistory() throws {
    var volume = try Sculpture(
        title: "Boundary",
        width: 3,
        height: 3,
        layers: Array(repeating: Array(repeating: Sculpture.empty, count: 9), count: 3)
    )
    volume.paint(SculptureCell(x: 1, y: 1, z: 2), glyph: 35)
    let workspace = SculptureWorkspace()
    workspace.replace(with: volume, opened: true)
    let hit = try frontHit(volume)
    #expect(hit.paintCell == nil)
    #expect(!workspace.paintVoxel(hit, start: true))
    #expect(!workspace.canUndo)
    workspace.tool = .erase
    #expect(workspace.paintVoxel(hit, start: true))
    workspace.endStroke()
    #expect(workspace.sculpture.occupiedCount == 0)
    workspace.undo()
    #expect(workspace.sculpture == volume)
}

@MainActor @Test func emptySliceCanStartACubeAndPresentationDoesNotDirtyTheDocument() throws {
    let volume = try Sculpture(
        title: "Empty",
        width: 3,
        height: 3,
        layers: Array(repeating: Array(repeating: Sculpture.empty, count: 9), count: 3)
    )
    let workspace = SculptureWorkspace()
    workspace.replace(with: volume, opened: true)
    workspace.renderStyle = .ascii
    workspace.renderStyle = .cubes
    workspace.cubeOpacity = 0.6
    workspace.paintsIn3D = true
    #expect(!workspace.isDirty)
    let generation = workspace.documentGeneration
    let frame = SculptureVoxelProjection.frame(
        volume,
        camera: SculptureCamera(yaw: 0, pitch: 0),
        width: 500,
        height: 500,
        selectedLayer: 1
    )
    let hit = try #require(frame.hitTest(x: 250, y: 250))
    #expect(hit.isEmpty)
    #expect(workspace.paintVoxel(hit, start: true))
    workspace.endStroke()
    #expect(workspace.sculpture.occupiedCount == 1)
    workspace.undo()
    #expect(workspace.sculpture == volume)
    workspace.replace(with: volume)
    #expect(workspace.documentGeneration != generation)
}
