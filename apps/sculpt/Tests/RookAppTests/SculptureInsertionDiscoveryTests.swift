import Foundation
import RookRendering
import RookSculpture
import Testing
import ThreeMD

@testable import RookApp

@Suite("Insertion discoverability", .serialized)
@MainActor
struct SculptureInsertionDiscoveryTests {
    // MARK: - File menu and palette

    @Test func fileMenuActionsPresentTheSheetsImporterAndAreUnavailableWhileBusy() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("child.3md")
        try SculptureCodec.encode(leaf("Child", glyph: 35)).write(to: file)
        let draft = SculptureCompositionDraft(composition: try occupiedComposition())

        let actions = try #require(SculptureInsertionActions.actions(for: draft))
        #expect(draft.insertionRequest == nil)
        actions.insertFiles()
        #expect(draft.insertionRequest == .files)
        actions.insertFolder()
        #expect(draft.insertionRequest == .files, "A pending importer is not replaced by a second request.")
        draft.finishInsertionRequest()
        actions.insertFolder()
        #expect(draft.insertionRequest == .folder)
        draft.finishInsertionRequest()
        #expect(draft.insertionRequest == nil)

        draft.importModels(from: [file])
        #expect(draft.isPreparing && SculptureInsertionActions.actions(for: draft) == nil)
        draft.requestInsertion(.files)
        #expect(draft.insertionRequest == nil)
        await wait { draft.isPreparing }
        let pending = try #require(draft.pendingInsertion)
        #expect(SculptureInsertionActions.actions(for: draft) == nil)
        draft.requestInsertion(.folder)
        #expect(draft.insertionRequest == nil)
        draft.cancelPendingInsertion()
        #expect(SculptureInsertionActions.actions(for: draft) != nil)
        #expect(!draft.confirmInsertion(id: pending.id))

        draft.beginSharedEdit(modelID: "existing")
        #expect(draft.sharedEdit != nil && SculptureInsertionActions.actions(for: draft) == nil)
        draft.cancelSharedEdit()
        #expect(SculptureInsertionActions.actions(for: draft) != nil)
        #expect(try draft.composition() == occupiedComposition() && !draft.hasChanges && !draft.canUndo)
    }

    @Test func worldMenuActionsFollowTheSameRulesAndNeverChangeTheWorld() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("child.3md")
        try SculptureCodec.encode(leaf("Child", glyph: 35)).write(to: file)
        let parent = try world()
        let draft = SculptureWorldDraft(world: parent)
        let actions = try #require(SculptureInsertionActions.actions(for: draft))
        actions.insertFolder()
        #expect(draft.insertionRequest == .folder)
        draft.finishInsertionRequest()
        actions.insertFiles()
        #expect(draft.insertionRequest == .files)
        draft.finishInsertionRequest()

        draft.importModels(from: [file])
        #expect(draft.isOpeningModel && SculptureInsertionActions.actions(for: draft) == nil)
        draft.requestInsertion(.files)
        #expect(draft.insertionRequest == nil)
        await wait { draft.isOpeningModel }
        #expect(SculptureInsertionActions.actions(for: draft) != nil)
        draft.undo()

        draft.beginSharedEdit(modelID: "existing")
        #expect(draft.sharedEdit != nil && SculptureInsertionActions.actions(for: draft) == nil)
        draft.cancelSharedEdit()
        #expect(try draft.world() == parent && !draft.hasChanges && !draft.canUndo)
    }

    @Test func commandPaletteOffersInsertionWithSearchableKeywordsAndOpensTheMatchingSheet() throws {
        var opened: [String] = []
        let actions = SculptureInsertionPalette.actions { destination, kind in
            opened.append("\(destination.rawValue).\(kind.rawValue)")
        }
        #expect(
            actions.map(\.id) == [
                "composition.insert", "composition.insert.folder", "world.insert", "world.insert.folder",
            ]
        )
        #expect(
            actions.map(\.title) == [
                "Insert 3md into a new composition…", "Insert a model folder into a new composition…",
                "Insert 3md into a new world…", "Insert a model folder into a new world…",
            ]
        )
        for action in actions {
            #expect(action.enabled && !action.detail.isEmpty && !action.symbol.isEmpty)
            #expect(!action.title.contains("\u{2014}") && !action.detail.contains("\u{2014}"))
        }
        for query in ["insert", "import", "add", "model", "file", "folder", "3md"] {
            let matches = SculptureCommandSearch.matches(actions, query: query)
            #expect(!matches.isEmpty, "The command palette must find insertion by '\(query)'.")
        }
        #expect(
            SculptureCommandSearch.matches(actions, query: "import folder").map(\.id).sorted() == [
                "composition.insert.folder", "world.insert.folder",
            ]
        )
        #expect(
            SculptureCommandSearch.matches(actions, query: "add world").map(\.id) == [
                "world.insert", "world.insert.folder",
            ]
        )
        for action in actions { action.perform() }
        #expect(opened == ["composition.files", "composition.folder", "world.files", "world.folder"])
    }

    @Test func insertionCanvasesStartEmptyAndAcceptTheFirstFileWithoutReplacingAnything() throws {
        let compositionDraft = SculptureCompositionDraft.insertionCanvas()
        let blank = try compositionDraft.composition()
        guard case .tiles(let map) = blank.models[blank.rootID] else {
            Issue.record("The canvas needs a tile map"); return
        }
        #expect(map.bindings.isEmpty && blank.models.count == 1 && compositionDraft.placementCount == 0)
        #expect(!compositionDraft.hasChanges && compositionDraft.canInsert)
        compositionDraft.requestInsertion(.files)
        #expect(compositionDraft.insertionRequest == .files)
        try compositionDraft.insert([.init(scene: .voxels(leaf("First model", glyph: 35, width: 64)))])
        #expect(compositionDraft.pendingInsertion == nil && compositionDraft.placementCount == 1)
        #expect(compositionDraft.library.map(\.title) == ["First model"])
        #expect(compositionDraft.hasChanges && compositionDraft.canUndo)

        let worldDraft = SculptureWorldDraft.insertionCanvas()
        #expect(worldDraft.instances.isEmpty && !worldDraft.hasChanges && worldDraft.canInsert)
        try worldDraft.insert([.init(scene: .voxels(leaf("First model", glyph: 35)))])
        #expect(worldDraft.instances.count == 1 && worldDraft.hasChanges && worldDraft.canUndo)
        #expect(worldDraft.modelTitle(for: worldDraft.instances[0].modelID) == "First model")
    }

    // MARK: - Menu Undo and Redo

    @Test func menuUndoActsOnTheOpenSheetAndNeverChangesTheHiddenSculpture() throws {
        let workspace = SculptureWorkspace()
        workspace.replace(with: .blank(), opened: true)
        workspace.paint(SculptureCell(x: 0, y: 0, z: 0), start: true)
        workspace.endStroke()
        let painted = workspace.sculpture
        #expect(workspace.canUndo)

        let draft = SculptureCompositionDraft(composition: try composition())
        try draft.insert([.init(scene: .voxels(leaf("Inserted", glyph: 35)))])
        let inserted = try draft.composition()
        workspace.hasOpenSheet = true
        let sheet = SculptureHistoryActions.actions(for: draft)
        #expect(SculptureHistoryRouting.canUndo(sheet: sheet, workspace: workspace))
        #expect(!SculptureHistoryRouting.canRedo(sheet: sheet, workspace: workspace))

        SculptureHistoryRouting.undo(sheet: sheet, workspace: workspace)
        #expect(try draft.composition() == composition() && !draft.canUndo)
        #expect(workspace.sculpture == painted && workspace.canUndo, "The hidden sculpture must not change.")
        let afterUndo = SculptureHistoryActions.actions(for: draft)
        #expect(SculptureHistoryRouting.canRedo(sheet: afterUndo, workspace: workspace))
        SculptureHistoryRouting.redo(sheet: afterUndo, workspace: workspace)
        #expect(try draft.composition() == inserted)
        #expect(workspace.sculpture == painted)
        // Nothing left to redo or undo in the sheet, but the covered sculpture still has history it must ignore.
        SculptureHistoryRouting.redo(sheet: SculptureHistoryActions.actions(for: draft), workspace: workspace)
        #expect(workspace.sculpture == painted)
    }

    @Test func menuUndoFallsBackToTheMainSculptureOnlyWhenNoSheetCoversIt() throws {
        let workspace = SculptureWorkspace()
        workspace.replace(with: .blank(), opened: true)
        workspace.paint(SculptureCell(x: 0, y: 0, z: 0), start: true)
        workspace.endStroke()
        #expect(workspace.sculpture.occupiedCount == 1)
        // A covered sculpture is protected even if the focused sheet value is missing, such as Settings frontmost.
        workspace.hasOpenSheet = true
        #expect(!SculptureHistoryRouting.canUndo(sheet: nil, workspace: workspace))
        SculptureHistoryRouting.undo(sheet: nil, workspace: workspace)
        #expect(workspace.sculpture.occupiedCount == 1)
        #expect(!SculptureHistoryRouting.canUndo(sheet: .unavailable, workspace: workspace))
        SculptureHistoryRouting.undo(sheet: .unavailable, workspace: workspace)
        #expect(workspace.sculpture.occupiedCount == 1)
        workspace.hasOpenSheet = false
        #expect(SculptureHistoryRouting.canUndo(sheet: nil, workspace: workspace))
        SculptureHistoryRouting.undo(sheet: nil, workspace: workspace)
        #expect(workspace.sculpture.occupiedCount == 0)
        #expect(SculptureHistoryRouting.canRedo(sheet: nil, workspace: workspace))
        SculptureHistoryRouting.redo(sheet: nil, workspace: workspace)
        #expect(workspace.sculpture.occupiedCount == 1)
    }

    @Test func sheetHistoryIsUnavailableWhileBusyAndFollowsAnOpenSharedEdit() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("incoming.3md")
        try SculptureCodec.encode(leaf("Incoming", glyph: 35)).write(to: file)
        let draft = SculptureCompositionDraft(composition: try occupiedComposition())
        draft.setTitle("Edited title")
        #expect(SculptureHistoryActions.actions(for: draft).canUndo)
        draft.importModels(from: [file])
        #expect(!SculptureHistoryActions.actions(for: draft).canUndo)
        await wait { draft.isPreparing }
        _ = try #require(draft.pendingInsertion)
        #expect(!SculptureHistoryActions.actions(for: draft).canUndo)
        draft.cancelPendingInsertion()
        #expect(SculptureHistoryActions.actions(for: draft).canUndo)

        draft.beginSharedEdit(modelID: "existing")
        let session = try #require(draft.sharedEdit)
        let nested = SculptureHistoryActions.actions(for: draft)
        #expect(!nested.canUndo, "A shared edit starts with no history of its own.")
        session.workspace.paint(SculptureCell(x: 0, y: 0, z: 0), start: true)
        session.workspace.endStroke()
        let edited = session.workspace.sculpture
        let afterPaint = SculptureHistoryActions.actions(for: draft)
        #expect(afterPaint.canUndo)
        afterPaint.undo()
        #expect(session.workspace.sculpture != edited)
        #expect(draft.title == "Edited title" && draft.canUndo, "The parent history is untouched by a shared edit.")
    }

    @Test func worldSheetHistoryRoutesAndStaysUnavailableWhileItsPreparationRuns() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("child.3md")
        try SculptureCodec.encode(leaf("Child", glyph: 35)).write(to: file)
        let draft = SculptureWorldDraft(world: try world())
        try draft.insert([.init(scene: .voxels(leaf("Placed", glyph: 64)))])
        let placed = try draft.world()
        #expect(SculptureHistoryActions.actions(for: draft).canUndo)
        draft.importModels(from: [file])
        #expect(!SculptureHistoryActions.actions(for: draft).canUndo)
        await wait { draft.isOpeningModel }
        #expect(draft.instances.count == placed.instances.count + 1)
        SculptureHistoryActions.actions(for: draft).undo()
        #expect(try draft.world() == placed)
        #expect(SculptureHistoryActions.actions(for: draft).canRedo)
    }

    // MARK: - Example replacement, hand-off and Explore

    @Test func replacingTheDraftWithAnExampleClearsStalePortableDataAndUndoRestoresIt() throws {
        let parent = try occupiedComposition()
        let captured = try identifiedSnapshot(.composition(parent), prefix: "original")
        let draft = SculptureCompositionDraft(composition: parent, portableSnapshot: captured)
        let courtyard = try SculptureCompositionExamples.courtyard()
        draft.replace(with: courtyard)
        #expect(try draft.composition() == courtyard)
        #expect(draft.portableSnapshot == nil, "The old snapshot describes the replaced graph.")
        draft.undo()
        #expect(try draft.composition() == parent && draft.portableSnapshot == captured)
        draft.redo()
        #expect(try draft.composition() == courtyard && draft.portableSnapshot == nil)
        // Replacing with an identical graph keeps the snapshot, which still describes it.
        let same = SculptureCompositionDraft(composition: parent, portableSnapshot: captured)
        same.replace(with: parent)
        #expect(same.portableSnapshot == captured)
    }

    @Test func useInAWorldCarriesTheCompositionsPortableMetadataAndNestedTitles() async throws {
        let composition = try nestedParent()
        let snapshot = try identifiedSnapshot(.composition(composition), prefix: "handoff")
        #expect(SculptureThreeMDCodec.modelTitle(for: "nested", in: snapshot) == "Nested child")
        var delivered: SculptureWorldHandoff?
        let draft = SculptureCompositionDraft(composition: composition, portableSnapshot: snapshot)
        draft.prepareWorldHandoff { delivered = $0 }
        #expect(draft.isPreparing && !draft.canUseInWorld)
        await wait { draft.isPreparing }
        let handoff = try #require(delivered)
        #expect(handoff.notice == nil && handoff.world.library == composition)
        let carried = try #require(handoff.snapshot)
        #expect(carried.scene == .world(handoff.world))
        #expect(SculptureThreeMDCodec.modelTitle(for: "nested", in: carried) == "Nested child")
        let source = try portableGraph(snapshot)
        let carriedGraph = try portableGraph(carried)
        let oldNested = try #require(source.entry(id: "nested"))
        let newNested = try #require(carriedGraph.entry(id: "nested"))
        #expect(newNested.document.planes.compactMap(\.stableID) == oldNested.document.planes.compactMap(\.stableID))
        #expect(newNested.references.compactMap(\.stableID) == oldNested.references.compactMap(\.stableID))
        #expect(newNested.references.map(\.attributes) == oldNested.references.map(\.attributes))
        let oldRoot = try #require(source.entry(id: "root"))
        let newRoot = try #require(carriedGraph.entry(id: "root"))
        #expect(newRoot.references.map(\.attributes) == oldRoot.references.map(\.attributes))
        #expect(newRoot.document.metadata["author"] == "handoff")
        #expect(newRoot.document.preamble == oldRoot.document.preamble)
        let reopened = SculptureWorldDraft(world: handoff.world, portableSnapshot: carried, notice: handoff.notice)
        #expect(reopened.modelChoices.first { $0.id == "nested" }?.title == "Nested child")
        #expect(try SculptureThreeMDCodec.decode(SculptureThreeMDCodec.encode(carried)) == carried)
        #expect(!draft.hasChanges && !draft.canUndo)
    }

    @Test func useInAWorldWithoutPortableDataOrBeyondPortableCapacityFallsBackWithAPlainNotice() async throws {
        let plain = try await SculptureWorldHandoff.prepare(composition: nestedParent(), snapshot: nil)
        #expect(plain.snapshot == nil && plain.notice == nil)
        #expect(plain.world.instances.map(\.modelID) == ["root"])

        let huge = try hugeComposition()
        let earlier = try SculptureThreeMDCodec.capture(.composition(nestedParent()))
        let fallback = try await SculptureWorldHandoff.prepare(composition: huge, snapshot: earlier)
        #expect(fallback.snapshot == nil)
        #expect(fallback.notice?.contains("portable") == true)
        #expect(fallback.world.title == huge.title)
    }

    @Test func cancelingAWorldHandoffNeverDeliversIt() async throws {
        let composition = try nestedParent()
        let draft = SculptureCompositionDraft(composition: composition)
        var delivered = false
        draft.prepareWorldHandoff { _ in delivered = true }
        draft.cancelPreparation()
        for _ in 0..<200 { await Task.yield() }
        #expect(!delivered && !draft.isPreparing && draft.error == nil)
    }

    @Test func insertingAtAnUnchangedFocusKeepsTheExploreEyeWherever() throws {
        let draft = SculptureWorldDraft(world: try world())
        draft.setNavigationMode(.explore)
        for _ in 0..<3 { draft.stepExplore(forward: 1, right: 1, vertical: 1) }
        let eye = draft.explorer
        #expect(eye.offset != .zero && draft.focus == eye.anchor)
        try draft.insert([.init(scene: .voxels(leaf("Inserted", glyph: 35)))])
        #expect(draft.explorer == eye, "Insert must not rebuild the explorer and snap the eye to its anchor.")
        draft.placeAtFocus()
        #expect(draft.explorer == eye && draft.instances.count == 2)
        draft.moveSelectedToFocus()
        #expect(draft.explorer == eye)
        draft.focusX = " +\(draft.focus.x) "
        #expect(draft.applyFocus() && draft.explorer == eye)
        #expect(draft.focusX == String(draft.focus.x), "Equivalent typed coordinates are normalized in place.")
        // Jump to it always brings the eye to the instance, even when the focus already matches.
        let target = try #require(draft.selectedInstance).origin
        #expect(target == draft.focus)
        draft.jumpToSelected()
        #expect(draft.explorer.anchor == target && draft.explorer.offset == .zero)
        #expect(draft.explorer.yaw == eye.yaw && draft.explorer.pitch == eye.pitch)
        #expect(draft.explorer != eye)
        draft.focusX = String(draft.focus.x + 100)
        #expect(draft.applyFocus())
        #expect(draft.explorer.offset == .zero && draft.explorer.anchor == draft.focus)
    }

    @Test func openingEditableVoxelsEndsTheNavigationPauseAndCatchesTheFocusUpWithTheExploreAnchor() async throws {
        let draft = SculptureWorldDraft(world: try world())
        draft.setNavigationMode(.explore)
        let origin = draft.focus
        var opened = false
        draft.selectModel("root")
        draft.openModel { _ in opened = true }
        #expect(draft.isOpeningModel)
        for _ in 0..<40 { draft.stepExplore(forward: 1, right: 1, vertical: 0) }
        #expect(draft.explorer.anchor != origin && draft.focus == origin)
        await wait { draft.isOpeningModel }
        #expect(opened)
        #expect(draft.focus == draft.explorer.anchor && draft.focusX == String(draft.focus.x))
    }

    @Test func walkingWhileAnInsertionPreparesDoesNotRefuseItAndFocusCatchesUpAfterwards() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("child.3md")
        try SculptureCodec.encode(leaf("Child", glyph: 35)).write(to: file)
        let draft = SculptureWorldDraft(world: try world())
        draft.setNavigationMode(.explore)
        let origin = draft.focus
        draft.importModels(from: [file])
        #expect(draft.isOpeningModel)
        // Enough steps to rebase the explorer's anchor, which normally moves the focus.
        for _ in 0..<40 { draft.stepExplore(forward: 1, right: 1, vertical: 0) }
        #expect(draft.explorer.anchor != origin && draft.focus == origin)
        await wait { draft.isOpeningModel }
        #expect(draft.error == nil, "Walking must not make the result look like a changed parent.")
        #expect(draft.instances.last?.origin == origin && draft.instances.count == 1)
        #expect(draft.focus == draft.explorer.anchor && draft.focusX == String(draft.focus.x))
        draft.undo()
        #expect(draft.instances.isEmpty)
    }

    // MARK: - Status, plurals and labels

    @Test func batchesNameTheirFirstAndLastTilesAndSayWhenTheyContinueOntoAnotherRowOrLayer() throws {
        let map = try SculptureTileMap(
            width: 2,
            height: 2,
            layers: [[UInt8](repeating: Sculpture.empty, count: 4), [UInt8](repeating: Sculpture.empty, count: 4)],
            tileSize: .init(width: 2, height: 2, depth: 2),
            bindings: []
        )
        let parent = try SculptureComposition(title: "Two layers", rootID: "root", models: ["root": .tiles(map)])
        let inputs = try (0..<3).map { SculptureInsertionInput(scene: .voxels(try leaf("Model \($0)", glyph: 35))) }
        let draft = SculptureCompositionDraft(composition: parent)
        draft.selectCell(.init(x: 1, y: 1, z: 0))
        try draft.insert(inputs)
        let layerNotice = try #require(draft.insertionNotice)
        #expect(
            layerNotice.contains("Inserted 3 models from column 2, row 2, layer 1 through column 2, row 1, layer 2")
        )
        #expect(layerNotice.contains("continued into another layer"))
        draft.undo()
        #expect(draft.insertionNotice == nil)

        draft.selectCell(.init(x: 1, y: 0, z: 0))
        try draft.insert(Array(inputs.prefix(2)))
        let rowNotice = try #require(draft.insertionNotice)
        #expect(rowNotice.contains("from column 2, row 1, layer 1 through column 1, row 2, layer 1"))
        #expect(rowNotice.contains("continued onto the next row"))
        draft.undo()

        draft.selectCell(.init(x: 0, y: 0, z: 0))
        try draft.insert(Array(inputs.prefix(1)))
        #expect(draft.insertionNotice == "Inserted 1 model at column 1, row 1, layer 1.")
        draft.setTitle("Edited")
        #expect(draft.insertionNotice == nil, "Any later edit clears the previous announcement.")
        #expect(SculptureCompositionDraft.insertionSummary(for: []) == nil)
    }

    @Test func replacementQuestionAndSummaryUseCorrectPlurals() throws {
        let parent = try occupiedComposition()
        let draft = SculptureCompositionDraft(composition: parent)
        try draft.insert([.init(scene: .voxels(leaf("Only one", glyph: 35)))])
        let single = try #require(draft.pendingInsertion)
        #expect(single.question == "Replace 1 occupied tile?")
        #expect(single.targetSummary.hasPrefix("1 model, from column 1, row 1, layer 1"))
        #expect(!single.question.contains("1 tiles") && !single.targetSummary.contains("1 models"))
        draft.cancelPendingInsertion()
        draft.selectCell(.init(x: 0, y: 0, z: 0))
        try draft.insert([
            .init(scene: .voxels(leaf("First", glyph: 35))), .init(scene: .voxels(leaf("Second", glyph: 64))),
            .init(scene: .voxels(leaf("Third", glyph: 43))),
        ])
        let several = try #require(draft.pendingInsertion)
        #expect(several.question == "Replace 2 occupied tiles?")
        #expect(several.targetSummary.hasPrefix("3 models, from"))
    }

    @Test func labelsShowModelTitlesAndDimensionsNeverGeneratedIDs() throws {
        let draft = SculptureCompositionDraft(composition: try composition())
        try draft.insert([.init(scene: .voxels(leaf("Watchtower", glyph: 35, width: 3)))])
        let choice = try #require(draft.editableModels.first)
        #expect(choice.id.hasPrefix("insert-model"))
        #expect(choice.label == "Watchtower (3 × 1 × 1 cells)")
        #expect(choice.accessibilityLabel == "Watchtower, 3 × 1 × 1 cells")
        #expect(!choice.label.contains("insert-model") && !choice.accessibilityLabel.contains("insert-model"))

        let worldDraft = SculptureWorldDraft(world: try world())
        try worldDraft.insert([.init(scene: .voxels(leaf("Watchtower", glyph: 35, width: 3)))])
        let placed = try #require(worldDraft.instances.last)
        #expect(placed.id == "insert-instance-1" && placed.modelID.hasPrefix("insert-model"))
        #expect(worldDraft.modelTitle(for: placed.modelID) == "Watchtower")
        #expect(worldDraft.modelAccessibilityLabel(for: placed.modelID) == "Watchtower, 3 × 1 × 1 cells")
        #expect(worldDraft.editableModels.map(\.label).contains("Watchtower (3 × 1 × 1 cells)"))
        let nested = try #require(worldDraft.modelChoices.first { $0.id == worldDraft.library.rootID })
        #expect(nested.dimensions == "16 × 4 × 4")
        #expect(worldDraft.modelTitle(for: "unknown-model") == "unknown-model")
    }

    // MARK: - Native capacity

    @Test func nativeSaveAndInsertionRefuseGraphsThatWouldNotReopen() async throws {
        let first = try tall()
        let second = try tall()
        let map = try SculptureTileMap(
            width: 2,
            height: 1,
            layers: [[65, 66]],
            tileSize: .init(width: 1, height: 256, depth: 256),
            bindings: [try .init(glyph: 65, modelID: "first"), try .init(glyph: 66, modelID: "second")]
        )
        let over = try SculptureComposition(
            title: "Too tall to reopen",
            rootID: "root",
            models: ["root": .tiles(map), "first": .sculpture(first), "second": .sculpture(second)]
        )
        let job = SculptureGraphSaveJob()
        job.start(.composition(over))
        for _ in 0..<100_000 where job.isRunning { await Task.yield() }
        #expect(job.result == nil)
        #expect(job.error?.contains("too large to reopen") == true)
        let world = try SculptureWorld(title: "Too tall world", library: over, instances: [])
        job.start(.world(world))
        for _ in 0..<100_000 where job.isRunning { await Task.yield() }
        #expect(job.result == nil && job.error?.contains("too large to reopen") == true)

        // The insertion that would create such a graph is refused and the parent is untouched.
        let singleMap = try SculptureTileMap(
            width: 2,
            height: 1,
            layers: [[65, Sculpture.empty]],
            tileSize: .init(width: 1, height: 256, depth: 256),
            bindings: [try .init(glyph: 65, modelID: "first")]
        )
        let parent = try SculptureComposition(
            title: "Tall parent",
            rootID: "root",
            models: ["root": .tiles(singleMap), "first": .sculpture(first)]
        )
        let draft = SculptureCompositionDraft(composition: parent)
        draft.selectCell(.init(x: 1, y: 0, z: 0))
        do {
            try draft.insert([.init(scene: .voxels(second), sourceName: "second.3md")])
            Issue.record("An insertion that cannot reopen was accepted")
        } catch SculptureCompositionError.tooLargeToReopen {
        }
        #expect(try draft.composition() == parent && !draft.hasChanges && !draft.canUndo)
        #expect(draft.pendingInsertion == nil && draft.insertionNotice == nil)
    }

    @Test func largeNativeParentsInsertWithNativeValuesAndExplainTheFallback() throws {
        let huge = try hugeComposition()
        let draft = SculptureCompositionDraft(composition: huge)
        try draft.insert([.init(scene: .voxels(leaf("Tiny", glyph: 35)))])
        #expect(draft.portableSnapshot == nil && draft.hasChanges && draft.canUndo)
        #expect(draft.editingNotice?.contains("native Sculpt values") == true)
        #expect(draft.insertionNotice == "Inserted 1 model at column 1, row 1, layer 1.")
        #expect(draft.library.map(\.title) == ["Tiny"])
        draft.undo()
        #expect(draft.placementCount == 0 && draft.editingNotice == nil)
    }

    // MARK: - Fixtures

    private func leaf(_ title: String, glyph: UInt8, width: Int = 1) throws -> Sculpture {
        try Sculpture(title: title, width: width, height: 1, layers: [Array(repeating: glyph, count: width)])
    }

    private func tall() throws -> Sculpture {
        try Sculpture(
            title: "Tall",
            width: 1,
            height: 256,
            layers: [[UInt8]](repeating: [UInt8](repeating: Sculpture.empty, count: 256), count: 256)
        )
    }

    private func composition() throws -> SculptureComposition {
        let map = try SculptureTileMap(
            width: 4,
            height: 1,
            layers: [[Sculpture.empty, Sculpture.empty, Sculpture.empty, Sculpture.empty]],
            tileSize: .init(width: 4, height: 4, depth: 4),
            bindings: []
        )
        return try SculptureComposition(title: "Parent map", rootID: "root", models: ["root": .tiles(map)])
    }

    private func occupiedComposition() throws -> SculptureComposition {
        let map = try SculptureTileMap(
            width: 4,
            height: 1,
            layers: [[65, Sculpture.empty, 65, Sculpture.empty]],
            tileSize: .init(width: 4, height: 4, depth: 4),
            bindings: [.init(glyph: 65, modelID: "existing")]
        )
        return try SculptureComposition(
            title: "Occupied parent",
            rootID: "root",
            models: ["root": .tiles(map), "existing": .sculpture(leaf("Existing castle", glyph: 42))]
        )
    }

    /// A root binding one nested map, which in turn binds a shared leaf. The nested map has a readable title.
    private func nestedParent() throws -> SculptureComposition {
        let nested = try SculptureTileMap(
            width: 2,
            height: 1,
            layers: [[66, 66]],
            tileSize: .init(width: 1, height: 1, depth: 1),
            bindings: [.init(glyph: 66, modelID: "leaf")]
        )
        let root = try SculptureTileMap(
            width: 1,
            height: 1,
            layers: [[65]],
            tileSize: .init(width: 2, height: 1, depth: 1),
            bindings: [.init(glyph: 65, modelID: "nested")]
        )
        return try SculptureComposition(
            title: "Hand-off parent",
            rootID: "root",
            models: ["root": .tiles(root), "nested": .tiles(nested), "leaf": .sculpture(leaf("Shared", glyph: 64))]
        )
    }

    private func world() throws -> SculptureWorld {
        try SculptureWorld(title: "Parent world", library: occupiedComposition(), instances: [])
    }

    /// An empty 256-cell root fits native storage but exceeds the portable definition limit.
    private func hugeComposition() throws -> SculptureComposition {
        let dimension = Sculpture.maximumDimension
        let root = try SculptureTileMap(
            width: dimension,
            height: dimension,
            layers: Array(repeating: Array(repeating: Sculpture.empty, count: dimension * dimension), count: dimension),
            tileSize: .init(width: 1, height: 1, depth: 1),
            bindings: []
        )
        return try SculptureComposition(title: "Native capacity", rootID: "root", models: ["root": .tiles(root)])
    }

    private func temporaryDirectory() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("RookDiscovery-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return folder
    }

    private func wait(_ isRunning: () -> Bool) async {
        for _ in 0..<100_000 where isRunning() { await Task.yield() }
        #expect(!isRunning())
    }

    /// The portable snapshot's complete graph, read through its canonical content.
    private func portableGraph(_ snapshot: SculptureThreeMDSnapshot) throws -> DocumentComposition {
        try DocumentCompositionCodec.decode(Data(snapshot.revision.canonicalContent.utf8))
    }

    private func identifiedSnapshot(_ scene: SculptureScene, prefix: String) throws -> SculptureThreeMDSnapshot {
        let captured = try SculptureThreeMDCodec.capture(scene)
        let graph = try DocumentCompositionCodec.decode(Data(captured.revision.canonicalContent.utf8))
        let entries = graph.entries.map { entry in
            let planes = entry.document.planes.enumerated().map { index, plane in
                var attributes = plane.attributes
                attributes["3md-id"] = "\(prefix)-plane-\(entry.id)-\(index)"
                attributes["material"] = "\(prefix)-\(entry.id)"
                return Plane(
                    z: plane.z,
                    label: plane.label,
                    x: plane.x,
                    y: plane.y,
                    attributes: attributes,
                    body: plane.body
                )
            }
            let source = entry.document
            var metadata = source.metadata
            metadata["author"] = prefix
            let document = Document(
                version: source.version,
                axis: source.axis,
                title: entry.id == "nested" ? "Nested child" : source.title,
                metadata: metadata,
                preamble: "Notes for \(entry.id).",
                planes: planes
            )
            let references = entry.references.enumerated().map { index, reference in
                var attributes = reference.attributes
                attributes["3md-id"] = "\(prefix)-ref-\(entry.id)-\(index)"
                attributes["caption"] = "\(prefix) caption \(index)"
                return DocumentReference(targetID: reference.targetID, attributes: attributes)
            }
            return DocumentEntry(id: entry.id, document: document, references: references)
        }
        let custom = try DocumentComposition(rootID: graph.rootID, entries: entries)
        return try SculptureThreeMDCodec.decode(DocumentCompositionCodec.encode(custom))
    }
}
