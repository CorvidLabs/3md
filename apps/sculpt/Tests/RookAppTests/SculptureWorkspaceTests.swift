import Foundation
import RookSculpture
import Testing

@testable import RookApp

@MainActor @Test func paintStrokeUndoRestoresWholeStrokeAndRedoReappliesIt() {
    let workspace = SculptureWorkspace()
    workspace.replace(with: .blank())
    workspace.paint(SculptureCell(x: 1, y: 2, z: 0), start: true)
    workspace.paint(SculptureCell(x: 2, y: 2, z: 0), start: false)
    #expect(workspace.sculpture.occupiedCount == 2)
    #expect(workspace.isDirty)
    workspace.undo()
    #expect(workspace.sculpture.occupiedCount == 0)
    workspace.redo()
    #expect(workspace.sculpture.occupiedCount == 2)
}

@MainActor @Test func strokeBeginningOnUnchangedCellStillHasOneUndoStep() {
    let workspace = SculptureWorkspace()
    workspace.replace(with: .blank())
    workspace.erase = true
    workspace.paint(SculptureCell(x: 0, y: 0, z: 0), start: true)
    workspace.erase = false
    workspace.paint(SculptureCell(x: 1, y: 0, z: 0), start: false)
    workspace.undo()
    #expect(workspace.sculpture.occupiedCount == 0)
}

@MainActor @Test func savedSnapshotDoesNotMarkLaterEditsSavedAndFailedOpenDoesNotReplaceState() {
    let workspace = SculptureWorkspace()
    workspace.replace(with: .blank(), opened: true)
    let saved = workspace.sculpture
    workspace.paint(SculptureCell(x: 0, y: 0, z: 0), start: true)
    workspace.markSaved(saved)
    #expect(workspace.isDirty)
    workspace.markSaved(workspace.sculpture)
    #expect(!workspace.isDirty)
    let current = workspace.sculpture
    do {
        let parsed = try SculptureCodec.decode(Data("wrong".utf8))
        workspace.replace(with: parsed, opened: true)
        Issue.record("Invalid input unexpectedly opened.")
    } catch {}
    #expect(workspace.sculpture == current)
}

@MainActor @Test func layerUndoAndRedoKeepSelectionInBounds() {
    let workspace = SculptureWorkspace()
    workspace.replace(with: .blank())
    workspace.change { try $0.addLayer(after: 0) }
    workspace.layer = 1
    workspace.undo()
    #expect(workspace.layer == 0)
    workspace.redo()
    #expect(workspace.layer < workspace.sculpture.depth)
}

@MainActor @Test func fastDiagonalStrokeHasNoGapsAndOneUndoStep() {
    let workspace = SculptureWorkspace()
    workspace.replace(with: .blank())
    workspace.paint(SculptureCell(x: 1, y: 1, z: 0), start: true)
    workspace.paint(SculptureCell(x: 12, y: 12, z: 0), start: false)
    workspace.endStroke()
    for coordinate in 1...12 {
        #expect(workspace.sculpture.glyph(at: SculptureCell(x: coordinate, y: coordinate, z: 0)) == 35)
    }
    #expect(workspace.sculpture.occupiedCount == 12)
    workspace.undo()
    #expect(workspace.sculpture.occupiedCount == 0)
    #expect(!workspace.canUndo)
    workspace.redo()
    #expect(workspace.sculpture.occupiedCount == 12)
}

@MainActor @Test func largeBrushClipsToVolumeAndUndoRestoresAllChangedCells() {
    let workspace = SculptureWorkspace()
    workspace.replace(with: .blank())
    workspace.brushSize = 3
    workspace.paint(SculptureCell(x: 0, y: 0, z: 0), start: true)
    workspace.endStroke()
    #expect(workspace.sculpture.occupiedCount == 4)
    workspace.undo()
    #expect(workspace.sculpture.occupiedCount == 0)
    workspace.redo()
    workspace.erase = true
    workspace.paint(SculptureCell(x: 0, y: 0, z: 0), start: true)
    #expect(workspace.sculpture.occupiedCount == 0)
    workspace.undo()
    #expect(workspace.sculpture.occupiedCount == 4)
}

@MainActor @Test func fillStopsAtGlyphBoundaryAndRemainsOneUndoableChange() throws {
    let original = try Sculpture(
        title: "Fill regions",
        width: 5,
        height: 3,
        layers: [Array("..@....@....@..".utf8)]
    )
    let workspace = SculptureWorkspace()
    workspace.replace(with: original, opened: true)
    workspace.tool = .fill
    workspace.paint(SculptureCell(x: 0, y: 0, z: 0), start: true)
    workspace.endStroke()
    #expect(workspace.sculpture.occupiedCount == 9)
    for y in 0..<3 {
        #expect(workspace.sculpture.glyph(at: SculptureCell(x: 1, y: y, z: 0)) == 35)
        #expect(workspace.sculpture.glyph(at: SculptureCell(x: 2, y: y, z: 0)) == 64)
        #expect(workspace.sculpture.glyph(at: SculptureCell(x: 3, y: y, z: 0)) == Sculpture.empty)
    }
    workspace.undo()
    #expect(workspace.sculpture == original)
    #expect(!workspace.isDirty)
    #expect(!workspace.canUndo)
}

@MainActor @Test func invalidTitleDraftIsPreservedWithoutModalErrorAndProtectsUnsavedWork() {
    let workspace = SculptureWorkspace()
    workspace.replace(with: .blank(), opened: true)
    workspace.titleDraft = ""
    #expect(workspace.isDirty)
    #expect(workspace.titleValidation != nil)
    #expect(!workspace.commitTitle())
    #expect(workspace.sculpture.title == "Untitled")
    #expect(workspace.titleDraft.isEmpty)
    #expect(workspace.error == nil)
    #expect(!workspace.canUndo)
    workspace.titleDraft = "Little island"
    #expect(workspace.commitTitle())
    #expect(workspace.sculpture.title == "Little island")
    workspace.undo()
    #expect(workspace.titleDraft == "Untitled")
    #expect(!workspace.isDirty)
    workspace.redo()
    #expect(workspace.titleDraft == "Little island")
    #expect(workspace.isDirty)
}

@MainActor @Test func clearingSliceKeepsOtherSlicesAndCanBeUndone() {
    let workspace = SculptureWorkspace()
    let original = Sculpture.orb()
    workspace.replace(with: original, opened: true)
    workspace.layer = 8
    workspace.clearLayer()
    #expect(workspace.sculpture.layers[8].allSatisfy { $0 == Sculpture.empty })
    #expect(workspace.sculpture.layers[7] == original.layers[7])
    workspace.undo()
    #expect(workspace.sculpture == original)
    #expect(!workspace.isDirty)
}

@MainActor @Test func changingCameraAndSelectionDoesNotDirtySavedDocument() {
    let workspace = SculptureWorkspace()
    workspace.replace(with: .orb(), opened: true)
    workspace.setViewpoint(.side)
    #expect(workspace.camera.yaw == .pi / 2)
    workspace.select(SculptureCell(x: 5, y: 4, z: 3))
    #expect(workspace.layer == 3)
    #expect(workspace.column == 5)
    #expect(workspace.row == 4)
    #expect(!workspace.isDirty)
    workspace.setViewpoint(.perspective)
    #expect(workspace.camera == SculptureCamera())
}

@MainActor @Test func structuredEditsShareHumanFillSemanticsAndBatchHasOneUndo() throws {
    let original = try Sculpture(title: "Shared", width: 3, height: 2, layers: [Array(".@..@.".utf8)])
    let workspace = SculptureWorkspace()
    workspace.replace(with: original, opened: true)
    workspace.brush = 43
    workspace.tool = .fill
    workspace.paint(SculptureCell(x: 0, y: 0, z: 0), start: true)
    workspace.endStroke()
    let structured = try SculptureCommandEngine.apply(.fill(x: 0, y: 0, z: 0, glyph: "+"), to: original)
    #expect(workspace.sculpture == structured)
    workspace.undo()
    let batch = try SculptureCommandBatch(commands: [
        .rename(title: "Agent copy"), .paint(x: 2, y: 1, z: 0, glyph: "#"),
    ])
    workspace.execute(batch)
    #expect(workspace.sculpture.title == "Agent copy")
    #expect(workspace.titleDraft == "Agent copy")
    #expect(workspace.sculpture.glyph(at: SculptureCell(x: 2, y: 1, z: 0)) == 35)
    workspace.undo()
    #expect(workspace.sculpture == original)
    #expect(!workspace.canUndo)
    #expect(!workspace.isDirty)
}

@MainActor @Test func invalidCommandBatchKeepsDocumentHistoryAndDraft() throws {
    let workspace = SculptureWorkspace()
    workspace.replace(with: .blank(), opened: true)
    workspace.titleDraft = "Draft still in progress"
    let original = workspace.sculpture
    workspace.execute(
        try SculptureCommandBatch(commands: [
            .paint(x: 0, y: 0, z: 0, glyph: "#"), .erase(x: 999, y: 0, z: 0),
        ])
    )
    #expect(workspace.sculpture == original)
    #expect(workspace.titleDraft == "Draft still in progress")
    #expect(!workspace.canUndo)
    #expect(workspace.error != nil)
}

private struct SliceEditFixtures: Decodable {
    let cases: [SliceEditCase]
}
private struct SliceEditCase: Decodable {
    let name: String
    let initial: [[String]]
    let expected: [[String]]
    let tool: String
    let glyph: String
    let size: Int
    let z: Int
    let path: [[Int]]
}

@MainActor @Test func browserSliceFixturesMatchNativeWorkspaceToolsAndWholeStrokeHistory() throws {
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { root.deleteLastPathComponent() }
    let fixtures = try JSONDecoder().decode(
        SliceEditFixtures.self,
        from: Data(contentsOf: root.appendingPathComponent("docs/evidence/viewer-slice/slice-parity.json"))
    )
    for item in fixtures.cases {
        let original = try Sculpture(
            title: item.name,
            width: item.initial[0][0].utf8.count,
            height: item.initial[0].count,
            layers: item.initial.map { Array($0.joined().utf8) }
        )
        let workspace = SculptureWorkspace()
        workspace.replace(with: original, opened: true)
        workspace.tool = item.tool == "erase" ? .erase : item.tool == "fill" ? .fill : .draw
        workspace.brush = item.glyph.utf8.first ?? 35
        workspace.brushSize = item.size
        for (index, point) in item.path.enumerated() {
            workspace.paint(SculptureCell(x: point[0], y: point[1], z: item.z), start: index == 0)
        }
        workspace.endStroke()
        #expect(workspace.sculpture.layers == item.expected.map { Array($0.joined().utf8) })
        #expect(workspace.canUndo == (item.initial != item.expected))
        if workspace.canUndo {
            workspace.undo()
            #expect(workspace.sculpture == original)
            #expect(!workspace.canUndo)
            workspace.redo()
            #expect(workspace.sculpture.layers == item.expected.map { Array($0.joined().utf8) })
        }
    }
}
