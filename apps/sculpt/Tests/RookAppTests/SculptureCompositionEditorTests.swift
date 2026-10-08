import RookSculpture
import Testing

@testable import RookApp

@MainActor
@Test func compositionDraftStartsWithSmallReferencedModelsAndDistinctMapCharacters() throws {
    let draft = SculptureCompositionDraft()
    let composition = try draft.composition()
    let expanded = try composition.expanded()
    #expect(draft.width == 3 && draft.height == 3 && draft.depth == 1)
    #expect(draft.tileWidth == 24 && draft.tileHeight == 24 && draft.tileDepth == 24)
    #expect(draft.rawRows == ["A.B", ".A.", "B.A"])
    #expect(draft.library.map(\.character) == ["A", "B"])
    #expect(composition.models.count == 3)
    #expect(expanded.width == 72 && expanded.height == 72 && expanded.depth == 24)
    let starters = SculptureExamples.compositionStarters
    #expect(expanded.occupiedCount == 3 * starters[0].sculpture.occupiedCount + 2 * starters[1].sculpture.occupiedCount)
    #expect(!draft.hasChanges)
}

@MainActor
@Test func compositionTilePlacementAndErasingDoNotAlterReferencedModels() throws {
    let draft = SculptureCompositionDraft()
    let library = draft.models
    let cell = SculptureCell(x: 1, y: 0, z: 0)
    draft.select(66)
    draft.paint(cell)
    #expect(draft.glyph(at: cell) == 66)
    #expect(draft.placementCount == 6)
    #expect(draft.selectedCell == cell)
    #expect(draft.hasChanges)
    draft.brush = .erase
    draft.paint(cell)
    #expect(draft.glyph(at: cell) == Sculpture.empty)
    #expect(draft.placementCount == 5)
    #expect(draft.models == library)
    _ = try draft.composition()
}

@MainActor
@Test func compositionShrinkRefusesOccupiedClippingAndKeepsSurvivingRowsAligned() {
    let draft = SculptureCompositionDraft()
    let original = draft.layers
    draft.resize(width: 2, height: 3, depth: 1)
    #expect(draft.width == 3)
    #expect(draft.layers == original)
    #expect(draft.error?.contains("Erase tiles") == true)
    draft.brush = .erase
    for y in 0..<3 { draft.paint(SculptureCell(x: 2, y: y, z: 0)) }
    draft.resize(width: 2, height: 3, depth: 1)
    #expect(draft.width == 2)
    #expect(draft.rawRows == ["A.", ".A", "B."])
    #expect(draft.error == nil)
}

@MainActor
@Test func compositionReopeningRetainsNestedGraphAndRotationChangesOnlyItsBinding() throws {
    let courtyard = try SculptureCompositionExamples.courtyard()
    let draft = SculptureCompositionDraft(composition: courtyard)
    #expect(try draft.composition() == courtyard)
    #expect(draft.models.count == 3)
    #expect(draft.rawRows == ["CCC"])
    #expect(draft.depth == 3)
    let models = draft.models
    draft.rotateSelected(1)
    do {
        _ = try draft.composition()
        Issue.record("A rotated 48 × 24 nested model incorrectly fit a 48 × 24 tile")
    } catch {
        #expect(error.localizedDescription.contains("24 × 48 × 48"))
        #expect(error.localizedDescription.contains("Increase the tile size"))
    }
    draft.setTileSize(width: 48, height: 48, depth: 48)
    let rotated = try draft.composition()
    #expect(draft.models == models)
    guard case .tiles(let root) = rotated.models[rotated.rootID] else {
        Issue.record("The root tile map was flattened")
        return
    }
    #expect(root.bindings.first?.quarterTurns == 1)
}

@MainActor
@Test func compositionInsertionRemapsEntireGraphAndKeepsRepeatedReferencesSelfContained() throws {
    let leaf = try Sculpture(title: "Tiny model", width: 1, height: 1, layers: [[35]])
    let map = try SculptureTileMap(
        width: 1,
        height: 1,
        layers: [[65]],
        tileSize: SculptureTileSize(width: 1, height: 1, depth: 1),
        bindings: [SculptureModelBinding(glyph: 65, modelID: "leaf")]
    )
    let incoming = try SculptureComposition(
        title: "Nested tiny model",
        rootID: "root",
        models: [
            "root": .tiles(map), "leaf": .sculpture(leaf),
        ]
    )
    let draft = SculptureCompositionDraft()
    // The starter map leaves its odd cells empty, so these two insertions replace nothing.
    draft.selectCell(SculptureCell(x: 1, y: 0, z: 0))
    try draft.insert([SculptureInsertionInput(scene: .composition(incoming))])
    let importedGlyph = draft.selectedGlyph
    let importedRoot = try #require(draft.selectedBinding?.modelID)
    #expect(importedRoot != "root" && importedRoot != "leaf")
    guard case .tiles(let importedMap) = draft.models[importedRoot] else {
        Issue.record("The imported root was not kept as a tile map")
        return
    }
    let importedLeaf = try #require(importedMap.bindings.first?.modelID)
    #expect(importedLeaf != "leaf" && importedLeaf != importedRoot)
    #expect(draft.models[importedLeaf] == .sculpture(leaf))
    let expanded = try draft.composition().expanded()
    #expect(draft.glyph(at: SculptureCell(x: 1, y: 0, z: 0)) == importedGlyph)
    #expect(expanded.glyph(at: SculptureCell(x: 24, y: 0, z: 0)) == 35)
    draft.selectCell(SculptureCell(x: 0, y: 1, z: 0))
    try draft.insert([SculptureInsertionInput(scene: .composition(incoming))])
    #expect(draft.selectedBinding?.modelID != importedRoot)
    #expect(try draft.composition().models.count == 7)
    #expect(draft.pendingInsertion == nil)
}

@MainActor
@Test func compositionTitleDraftAndBoundsErrorsDoNotDiscardMapOrLibrary() throws {
    let draft = SculptureCompositionDraft()
    let layers = draft.layers
    let library = draft.models
    draft.setTitle("")
    do {
        _ = try draft.composition()
        Issue.record("An empty composition title was accepted")
    } catch { #expect(error as? SculptureCompositionError == .invalidTitle) }
    #expect(draft.layers == layers && draft.models == library)
    draft.setTitle("My composition")
    draft.setTileSize(width: 256, height: 24, depth: 24)
    #expect(draft.tileWidth == 24)
    #expect(draft.error?.contains("exceeds 256") == true)
    #expect(draft.layers == layers)
    _ = try draft.composition()
}

@MainActor
@Test func cancelingCompositionPreparationNeverOpensTheCanceledSnapshot() async {
    let draft = SculptureCompositionDraft()
    var opened = false
    draft.prepare { _, _ in opened = true }
    draft.cancelPreparation()
    await Task.yield()
    #expect(!draft.isPreparing)
    #expect(draft.preview == nil)
    #expect(!opened)
}
