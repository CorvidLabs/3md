import RookSculpture
import Testing

@testable import RookApp

@Suite("Shared model draft editing", .serialized)
@MainActor
struct SculptureSharedModelDraftTests {
    @Test func compositionApplyUpdatesNestedReferencesAsOneParentUndoAndRedo() async throws {
        let composition = try fixture()
        let draft = SculptureCompositionDraft(composition: composition)
        draft.beginSharedEdit(modelID: "leaf")
        let session = try #require(draft.sharedEdit)
        session.workspace.execute(.paint(x: 0, y: 0, z: 0, glyph: "@"))
        #expect(try draft.composition() == composition)
        #expect(!draft.hasChanges && !draft.canUndo)
        #expect(await draft.applySharedEdit())
        let changed = try draft.composition()
        #expect(try changed.expanded().layers == [[64, 64]])
        #expect(draft.hasChanges && draft.canUndo && draft.sharedEdit == nil)
        draft.undo()
        #expect(try draft.composition() == composition)
        #expect(!draft.hasChanges && !draft.canUndo && draft.canRedo)
        draft.redo()
        #expect(try draft.composition() == changed)
        #expect(try SculptureCompositionCodec.decode(SculptureCompositionCodec.encode(changed)) == changed)
    }

    @Test func compositionCancelAndNoOpKeepReferenceWorkspaceAndHistoryExact() async throws {
        let draft = SculptureCompositionDraft(composition: try fixture())
        draft.selectLayer(0)
        let original = try draft.composition()
        let revision = draft.revision
        let selection = draft.selectedCell
        draft.beginSharedEdit(modelID: "leaf")
        let session = try #require(draft.sharedEdit)
        session.workspace.execute(.paint(x: 0, y: 0, z: 0, glyph: "@"))
        draft.cancelSharedEdit()
        #expect(try draft.composition() == original)
        #expect(draft.revision == revision && draft.selectedCell == selection)
        #expect(!draft.canUndo && !draft.hasChanges)
        draft.beginSharedEdit(modelID: "leaf")
        #expect(await draft.applySharedEdit())
        #expect(draft.revision == revision && !draft.canUndo && !draft.hasChanges)
    }

    @Test func compositionSessionRejectsChangedParentAndInvalidLeafWithoutOverwritingNewerState() async throws {
        let draft = SculptureCompositionDraft(composition: try fixture())
        draft.beginSharedEdit(modelID: "leaf")
        let session = try #require(draft.sharedEdit)
        session.workspace.execute(.paint(x: 0, y: 0, z: 0, glyph: "@"))
        draft.setTitle("Newer parent title")
        let newer = try draft.composition()
        #expect(!(await draft.applySharedEdit()))
        #expect(try draft.composition() == newer)
        #expect(session.error?.contains("changed after editing began") == true)
        draft.cancelSharedEdit()
        draft.beginSharedEdit(modelID: "leaf")
        let invalid = try #require(draft.sharedEdit)
        invalid.workspace.replace(with: try Sculpture(title: "Too wide", width: 2, height: 1, layers: [[35, 35]]))
        #expect(!(await draft.applySharedEdit()))
        #expect(try draft.composition() == newer)
        #expect(invalid.error?.contains("does not fit") == true)
    }

    @Test func compositionHistoryIncludesRootMapAndLibraryTogether() throws {
        let draft = SculptureCompositionDraft(composition: try fixture())
        let original = try draft.composition()
        draft.brush = .erase
        draft.paint(.init(x: 0, y: 0, z: 0))
        let erased = try draft.composition()
        #expect(erased != original)
        draft.undo()
        #expect(try draft.composition() == original && !draft.hasChanges)
        draft.redo()
        #expect(try draft.composition() == erased && draft.hasChanges)
    }

    @Test func savedRootEditsRemainCleanAfterSharedApplyUndoAndRetainNewerDirtyEdits() async throws {
        let draft = SculptureCompositionDraft(composition: try fixture())
        draft.brush = .erase
        draft.paint(.init(x: 0, y: 0, z: 0))
        let saved = try draft.composition()
        draft.markSaved(saved)
        #expect(!draft.hasChanges)
        draft.beginSharedEdit(modelID: "leaf")
        let session = try #require(draft.sharedEdit)
        session.workspace.execute(.paint(x: 0, y: 0, z: 0, glyph: "@"))
        #expect(await draft.applySharedEdit())
        #expect(draft.hasChanges)
        draft.undo()
        #expect(try draft.composition() == saved && !draft.hasChanges)
        draft.setTitle("Newer unsaved title")
        draft.markSaved(saved)
        #expect(draft.hasChanges && draft.title == "Newer unsaved title")
        draft.undo()
        #expect(try draft.composition() == saved && !draft.hasChanges)
    }

    @Test func worldSharedApplyAndUniqueBothIncludeLibraryInDirtyAndUndoHistory() async throws {
        let initial = try world()
        let draft = SculptureWorldDraft(world: initial)
        let geometry = draft.sceneRevision
        draft.beginSharedEdit(modelID: "leaf")
        let session = try #require(draft.sharedEdit)
        session.workspace.execute(.paint(x: 0, y: 0, z: 0, glyph: "@"))
        #expect(await draft.applySharedEdit())
        let changed = try draft.world()
        #expect(draft.hasChanges && draft.sceneRevision != geometry)
        #expect(changed.instances == initial.instances)
        #expect(try changed.library.expanded().layers == [[64, 64]])
        draft.undo()
        #expect(try draft.world() == initial && !draft.hasChanges && !draft.canUndo)
        draft.redo()
        #expect(try draft.world() == changed)
        draft.selectInstance("first")
        await draft.makeSelectedUnique()
        let unique = try draft.world()
        #expect(unique.instances[0].modelID != "leaf")
        #expect(unique.instances[1] == changed.instances[1])
        #expect(unique.library.models.count == changed.library.models.count + 1)
        #expect(draft.selectedModelID == unique.instances[0].modelID)
        draft.undo()
        #expect(try draft.world() == changed)
        draft.redo()
        #expect(try draft.world() == unique)
        #expect(try SculptureWorldCodec.decode(SculptureWorldCodec.encode(unique)) == unique)
    }

    @Test func worldCancelNoOpAndStaleSessionRetainExactDocumentAndScene() async throws {
        let initial = try world()
        let draft = SculptureWorldDraft(world: initial)
        let geometry = draft.sceneRevision
        let revision = draft.documentRevision
        draft.beginSharedEdit(modelID: "leaf")
        let cancelled = try #require(draft.sharedEdit)
        cancelled.workspace.execute(.paint(x: 0, y: 0, z: 0, glyph: "@"))
        draft.cancelSharedEdit()
        #expect(try draft.world() == initial && !draft.hasChanges && !draft.canUndo)
        #expect(draft.sceneRevision == geometry && draft.documentRevision == revision)
        draft.beginSharedEdit(modelID: "leaf")
        #expect(await draft.applySharedEdit())
        #expect(draft.sceneRevision == geometry && draft.documentRevision == revision)
        draft.beginSharedEdit(modelID: "leaf")
        let stale = try #require(draft.sharedEdit)
        stale.workspace.execute(.paint(x: 0, y: 0, z: 0, glyph: "@"))
        draft.setTitle("Changed parent")
        let newer = try draft.world()
        #expect(!(await draft.applySharedEdit()))
        #expect(try draft.world() == newer)
        #expect(stale.error?.contains("changed after editing began") == true)
    }

    @Test func cancellationNeverPublishesChildAndNestedMapIsNotMadeUnique() async throws {
        let initial = try world()
        let draft = SculptureWorldDraft(world: initial)
        draft.beginSharedEdit(modelID: "leaf")
        let session = try #require(draft.sharedEdit)
        session.workspace.execute(.paint(x: 0, y: 0, z: 0, glyph: "@"))
        let applying = Task { @MainActor in
            while !Task.isCancelled { await Task.yield() }
            return await draft.applySharedEdit()
        }
        applying.cancel()
        #expect(!(await applying.value))
        #expect(try draft.world() == initial && !draft.hasChanges && !draft.canUndo)
        draft.cancelSharedEdit()
        draft.selectModel("root")
        draft.placeAtFocus()
        let beforeUnique = try draft.world()
        await draft.makeSelectedUnique()
        #expect(try draft.world() == beforeUnique)
        #expect(draft.error?.contains("nested tile map") == true)
    }

    private func fixture() throws -> SculptureComposition {
        let leaf = try Sculpture(title: "Shared leaf", width: 1, height: 1, layers: [[35]])
        let map = try SculptureTileMap(
            width: 2,
            height: 1,
            layers: [[65, 65]],
            tileSize: .init(width: 1, height: 1, depth: 1),
            bindings: [SculptureModelBinding(glyph: 65, modelID: "leaf")]
        )
        return try SculptureComposition(
            title: "Shared composition",
            rootID: "root",
            models: [
                "root": .tiles(map), "leaf": .sculpture(leaf),
            ]
        )
    }

    private func world() throws -> SculptureWorld {
        try SculptureWorld(
            title: "Shared world",
            library: fixture(),
            instances: [
                SculptureWorldInstance(id: "first", modelID: "leaf", origin: .init(x: 0, y: 0, z: 0)),
                SculptureWorldInstance(id: "second", modelID: "leaf", origin: .init(x: 100, y: 0, z: 0)),
            ]
        )
    }
}
