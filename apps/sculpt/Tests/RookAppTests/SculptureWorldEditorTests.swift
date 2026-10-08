import Foundation
import RookRendering
import RookSculpture
import Testing

@testable import RookApp

@MainActor
@Test func worldExplorationAndOverviewPreserveSavedContentAndUndoAtExactDistantCoordinates() throws {
    let anchor: Int64 = 9_007_199_254_741_099
    let library = try SculptureCompositionExamples.courtyard()
    let source = try SculptureWorld(
        title: "Explore exact positions",
        library: library,
        instances: [
            .init(id: "near", modelID: "garden", origin: .init(x: anchor, y: 0, z: 0)),
            .init(id: "far", modelID: "garden", origin: .init(x: anchor + 960, y: 0, z: 960)),
        ]
    )
    let draft = SculptureWorldDraft(world: source)
    let sceneID = draft.sceneRevision
    let documentID = draft.documentRevision
    let garden = try library.expanded(modelID: "garden")
    #expect(draft.showOverview())
    #expect(draft.focus.x == anchor + Int64((960 + garden.width - 1) / 2))
    #expect(draft.renderDistance >= 704 && draft.renderDistance <= 2048)
    draft.setNavigationMode(.explore)
    let start = draft.explorer
    for _ in 0..<12 { draft.stepExplore(forward: 1, right: 1, vertical: 1) }
    #expect(draft.explorer != start)
    #expect(draft.focus == draft.explorer.anchor)
    draft.setNavigationMode(.orbit)
    draft.visitModel("garden")
    #expect(draft.navigationMode == .explore)
    #expect(draft.focus.x == anchor)
    #expect(try draft.world() == source)
    #expect(draft.sceneRevision == sceneID && draft.documentRevision == documentID)
    #expect(!draft.hasChanges && !draft.canUndo && !draft.canRedo)
}

@MainActor
@Test func worldOverviewRefusesUnframeableExtentWithoutOverflowOrChangingDocument() throws {
    let source = try SculptureWorld(
        title: "Unbounded range",
        library: SculptureCompositionExamples.courtyard(),
        instances: [
            .init(id: "left", modelID: "garden", origin: .init(x: Int64.min, y: 0, z: 0)),
            .init(id: "right", modelID: "garden", origin: .init(x: Int64.max - 256, y: 0, z: 0)),
        ]
    )
    let draft = SculptureWorldDraft(world: source)
    let focus = draft.focus
    #expect(!draft.showOverview())
    #expect(draft.focus == focus)
    #expect(draft.overviewNotice?.contains("beyond") == true)
    #expect(try draft.world() == source)
    #expect(!draft.hasChanges && !draft.canUndo)
}

@MainActor
@Test func worldDraftStartsSparseAndKeepsDistantAnchorsWithoutExpandingSpace() throws {
    let draft = SculptureWorldDraft()
    let world = try draft.world()
    #expect(world.instances.count == 4)
    #expect(world.instances.map(\.origin.x) == [0, 96, 512, 1_000_000_000_000])
    #expect(world.instances.allSatisfy { $0.modelID == "garden" })
    #expect(world.library.models.count == 4)
    #expect(!draft.hasChanges && !draft.canUndo)
}

@MainActor
@Test func worldFocusDistancesAndCameraAreSessionStateAndReuseTheSceneRevision() {
    let draft = SculptureWorldDraft()
    let revision = draft.sceneRevision
    draft.focusX = "1000000000001"
    draft.focusY = "-1000000000001"
    draft.focusZ = "64"
    #expect(draft.applyFocus())
    draft.setRenderDistance(1024)
    draft.setDetailDistance(512)
    draft.setCamera(SculptureCamera(yaw: 1, pitch: 0.2, zoom: 0.8))
    #expect(draft.focus == SculptureWorldPoint(x: 1_000_000_000_001, y: -1_000_000_000_001, z: 64))
    #expect(draft.sceneRevision == revision)
    #expect(!draft.hasChanges && !draft.canUndo)
    draft.setRenderDistance(64)
    #expect(draft.detailDistance == 64)
    #expect(draft.sceneRevision == revision)
}

@MainActor
@Test func worldPlacementUndoAndRedoPreserveExactInt64OriginsAndSharedLibrary() throws {
    let draft = SculptureWorldDraft()
    let original = try draft.world()
    draft.focusX = "1000000000001"
    draft.focusY = String(Int64.min)
    draft.focusZ = "-65"
    draft.placeAtFocus()
    let placed = try #require(draft.selectedInstance)
    #expect(placed.origin == SculptureWorldPoint(x: 1_000_000_000_001, y: Int64.min, z: -65))
    #expect(draft.instances.count == 5 && draft.hasChanges)
    #expect(try draft.world().library == original.library)
    draft.undo()
    #expect(try draft.world() == original)
    #expect(!draft.hasChanges)
    draft.redo()
    #expect(draft.instances.last == placed)
    #expect(draft.selectedInstanceID == placed.id)
    #expect(draft.focusX == "1000000000001")
}

@MainActor
@Test func worldFocusOverflowAndUnsafePlacementLeaveInstancesUnchanged() {
    let draft = SculptureWorldDraft()
    let original = draft.instances
    draft.focusX = String(Int64.max)
    #expect(draft.applyFocus())
    draft.moveFocus(axis: 0, delta: 64)
    #expect(draft.focus.x == Int64.max)
    #expect(draft.error?.contains("exceed the Int64") == true)
    draft.placeAtFocus()
    #expect(draft.instances == original)
    #expect(draft.error?.contains("minus 256") == true)
    draft.focusX = String(Int64.min)
    #expect(draft.applyFocus())
    draft.moveFocus(axis: 0, delta: -64)
    #expect(draft.focus.x == Int64.min)
    #expect(draft.instances == original)
    #expect(!draft.hasChanges)
}

@MainActor
@Test func worldSelectedRotationDeletionAndUndoNeverChangeModelDefinitions() throws {
    let draft = SculptureWorldDraft()
    let original = try draft.world()
    let selection = try #require(draft.selectedInstanceID)
    let origin = try #require(draft.selectedInstance?.origin)
    draft.rotate(1)
    #expect(draft.selectedInstance?.quarterTurns == 1)
    #expect(draft.selectedInstance?.origin == origin)
    draft.deleteSelected()
    #expect(draft.instances.count == 3 && draft.selectedInstanceID == nil)
    draft.undo()
    #expect(draft.selectedInstanceID == selection)
    #expect(draft.selectedInstance?.quarterTurns == 1)
    draft.undo()
    #expect(try draft.world() == original)
    #expect(draft.library == original.library)
    #expect(!draft.hasChanges)
}

@MainActor
@Test func worldPaginationBoundsRowsAndSelectionCanRevealADistantInstance() throws {
    let library = try SculptureCompositionExamples.courtyard()
    let instances = try (0..<205).map { index in
        try SculptureWorldInstance(
            id: "placement-\(index)",
            modelID: "garden",
            origin: SculptureWorldPoint(x: Int64(index) * 64, y: 0, z: 0)
        )
    }
    let world = try SculptureWorld(title: "Many placements", library: library, instances: instances)
    let draft = SculptureWorldDraft(world: world)
    let revision = draft.sceneRevision
    #expect(draft.pageCount == 3 && draft.pageInstances.count == 100)
    draft.selectInstance("placement-204")
    #expect(draft.page == 2 && draft.pageInstances.count == 5)
    draft.jumpToSelected()
    #expect(draft.focus.x == 13_056)
    #expect(draft.focusX == "13056")
    #expect(draft.sceneRevision == revision && !draft.hasChanges)
}

@MainActor
@Test func unsavedWorldRestorationAndTitleDraftProtectPublicationWithoutLosingPlacements() throws {
    let draft = SculptureWorldDraft()
    let instances = draft.instances
    let revision = draft.sceneRevision
    draft.markUnsaved()
    #expect(draft.hasChanges)
    draft.setTitle("")
    do {
        _ = try draft.world()
        Issue.record("An empty world title was published")
    } catch { #expect(error as? SculptureWorldError == .invalidTitle) }
    #expect(draft.instances == instances)
    #expect(draft.sceneRevision == revision)
    let (renderTitle, _, _) = draft.renderInput()
    #expect(renderTitle == "World draft")
    draft.undo()
    #expect(draft.title == "Growing garden")
    #expect(draft.hasChanges)
}

@MainActor
@Test func cancelingWorldModelPreparationDoesNotOpenAnAbandonedCopy() async {
    let draft = SculptureWorldDraft()
    var opened = false
    draft.openModel { _ in opened = true }
    draft.cancelModelPreparation()
    await Task.yield()
    #expect(!draft.isOpeningModel)
    #expect(!opened)
    #expect(!draft.hasChanges)
}
