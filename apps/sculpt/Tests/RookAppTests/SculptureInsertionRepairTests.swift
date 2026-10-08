import Foundation
import Observation
import RookSculpture
import Testing
import os

@testable import RookApp

@Suite("Insertion repairs", .serialized)
@MainActor
struct SculptureInsertionRepairTests {
    // MARK: - Native fallback does not depend on insertion order

    @Test func aNativeWorldFallsBackNativelyWhetherFilesArriveOneAtATimeOrTogether() throws {
        let huge = try hugeLeaf()
        let small = SculptureInsertionInput(scene: .voxels(try leaf("Small", glyph: 35)), sourceName: "small.3md")
        let large = SculptureInsertionInput(scene: .voxels(huge), sourceName: "huge.3md")

        let oneByOne = SculptureWorldDraft(world: try world())
        try oneByOne.insert([small])
        #expect(oneByOne.portableSnapshot == nil && !oneByOne.holdsPortableData)
        try oneByOne.insert([large])
        #expect(oneByOne.editingNotice?.contains("native Sculpt values") == true)
        #expect(oneByOne.instances.count == 2 && oneByOne.portableSnapshot == nil && !oneByOne.holdsPortableData)

        let together = SculptureWorldDraft(world: try world())
        try together.insert([small, large])
        #expect(together.instances.count == 2 && together.editingNotice?.contains("native Sculpt values") == true)
        let sameLibrary = try oneByOne.world().library == together.world().library
        #expect(sameLibrary)

        oneByOne.undo()
        oneByOne.undo()
        #expect(oneByOne.instances.isEmpty)
    }

    @Test func aSnapshotMintedByASharedEditDoesNotForceLaterInsertionsDownThePortablePath() async throws {
        let draft = SculptureWorldDraft(world: try world())
        draft.beginSharedEdit(modelID: "existing")
        let session = try #require(draft.sharedEdit)
        session.workspace.paint(SculptureCell(x: 0, y: 0, z: 0), start: true)
        session.workspace.endStroke()
        #expect(await draft.applySharedEdit())
        #expect(draft.portableSnapshot != nil, "The shared edit mints a snapshot for its own transaction.")
        #expect(!draft.holdsPortableData && draft.insertionSnapshot == nil)
        try draft.insert([.init(scene: .voxels(hugeLeaf()), sourceName: "huge.3md")])
        #expect(draft.editingNotice?.contains("native Sculpt values") == true)
        #expect(draft.instances.count == 1 && !draft.holdsPortableData)
    }

    @Test func portableDataTheDraftTrulyHoldsStillRefusesAnOversizedInsertionByName() throws {
        let parent = try world()
        let draft = SculptureWorldDraft(
            world: parent,
            portableSnapshot: try SculptureThreeMDCodec.capture(.world(parent))
        )
        #expect(draft.holdsPortableData && draft.insertionSnapshot != nil)
        do {
            try draft.insert([.init(scene: .voxels(hugeLeaf()), sourceName: "huge.3md")])
            Issue.record("An insertion past the portable limit was accepted over portable data")
        } catch SculptureInsertionError.portableLimitExceeded(let holdsParent, let sources) {
            #expect(holdsParent && sources.isEmpty)
        }
        #expect(try draft.world() == parent && !draft.hasChanges && !draft.canUndo)
    }

    @Test func theDraftsPortableFlagFollowsCarriedDataExportsAndReplacementAndUndoRestoresIt() throws {
        let parent = try composition()
        let draft = SculptureCompositionDraft(composition: parent)
        #expect(!draft.holdsPortableData && draft.insertionSnapshot == nil)
        try draft.insert([.init(scene: .voxels(leaf("Plain", glyph: 35)))])
        #expect(!draft.holdsPortableData && draft.portableSnapshot == nil)
        draft.selectCell(.init(x: 1, y: 0, z: 0))
        let annotated = try SculptureThreeMDCodec.capture(.voxels(leaf("Annotated", glyph: 64)))
        try draft.insert([.init(scene: .voxels(leaf("Annotated", glyph: 64)), snapshot: annotated)])
        #expect(draft.holdsPortableData && draft.portableSnapshot != nil && draft.insertionSnapshot != nil)
        draft.undo()
        #expect(!draft.holdsPortableData && draft.portableSnapshot == nil)
        draft.redo()
        #expect(draft.holdsPortableData && draft.portableSnapshot != nil)
        draft.undo()
        draft.undo()
        #expect(!draft.holdsPortableData && !draft.canUndo)

        // A portable export gives the person portable data. Replacing the graph discards it.
        let exported = try SculptureThreeMDCodec.capture(.composition(draft.composition()))
        draft.retainPortableSnapshot(exported)
        #expect(draft.holdsPortableData && draft.insertionSnapshot == exported)
        draft.replace(with: try SculptureCompositionExamples.courtyard())
        #expect(!draft.holdsPortableData && draft.portableSnapshot == nil)
        draft.undo()
        #expect(draft.holdsPortableData && draft.portableSnapshot == exported)
    }

    @Test func theWorldDraftsPortableFlagFollowsCarriedDataAndUndoRestoresIt() throws {
        let draft = SculptureWorldDraft(world: try world())
        try draft.insert([.init(scene: .voxels(leaf("Plain", glyph: 35)))])
        #expect(!draft.holdsPortableData && draft.portableSnapshot == nil)
        let annotated = try SculptureThreeMDCodec.capture(.voxels(leaf("Annotated", glyph: 64)))
        try draft.insert([.init(scene: .voxels(leaf("Annotated", glyph: 64)), snapshot: annotated)])
        #expect(draft.holdsPortableData && draft.portableSnapshot != nil)
        draft.undo()
        #expect(!draft.holdsPortableData && draft.portableSnapshot == nil)
        draft.redo()
        #expect(draft.holdsPortableData)
        draft.undo()
        draft.undo()
        let exported = try SculptureThreeMDCodec.capture(.world(draft.world()))
        draft.retainPortableSnapshot(exported)
        #expect(draft.holdsPortableData && draft.insertionSnapshot == exported)
    }

    @Test func largeNativeFilesInsertNativelyAndTheSameFilesWithPortableDataAreRefusedByName() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let huge = try hugeLeaf()
        let nativeFile = folder.appendingPathComponent("native-huge.3md")
        let portableFile = folder.appendingPathComponent("portable-huge.3md")
        try SculptureCodec.encode(huge).write(to: nativeFile)
        try SculptureThreeMDCodec.encode(SculptureThreeMDCodec.capture(.voxels(huge))).write(to: portableFile)
        let map = try SculptureTileMap(
            width: 1,
            height: 1,
            layers: [[Sculpture.empty]],
            tileSize: .init(width: 256, height: 256, depth: 256),
            bindings: []
        )
        let parent = try SculptureComposition(title: "One huge tile", rootID: "root", models: ["root": .tiles(map)])
        let draft = SculptureCompositionDraft(composition: parent)

        draft.importModels(from: [nativeFile])
        await wait { draft.isPreparing }
        #expect(draft.error == nil && draft.placementCount == 1 && draft.pendingInsertion == nil)
        #expect(draft.portableSnapshot == nil && !draft.holdsPortableData)
        #expect(draft.editingNotice?.contains("native Sculpt values") == true)
        draft.undo()
        #expect(try draft.composition() == parent)

        draft.importModels(from: [portableFile])
        await wait { draft.isPreparing }
        let message = try #require(draft.error)
        #expect(message.contains("portable-huge.3md") && message.contains("portable limit"))
        #expect(try draft.composition() == parent && !draft.hasChanges)
    }

    // MARK: - Apply lock

    @Test func historyIsUnavailableWhileApplyValidatesAndAStaleApplyKeepsTheSessionOpen() async throws {
        let parent = try occupiedComposition()
        let draft = SculptureCompositionDraft(composition: parent)
        draft.beginSharedEdit(modelID: "existing")
        let session = try #require(draft.sharedEdit)
        session.workspace.paint(SculptureCell(x: 0, y: 0, z: 0), start: true)
        session.workspace.endStroke()
        let painted = session.workspace.sculpture
        #expect(SculptureHistoryActions.actions(for: draft).canUndo)

        let apply = Task { await draft.applySharedEdit() }
        await Task.yield()
        #expect(session.isApplying)
        let locked = SculptureHistoryActions.actions(for: draft)
        #expect(!locked.canUndo && !locked.canRedo)
        locked.undo()
        #expect(session.workspace.sculpture == painted, "Routed menu Undo must not change a model while Apply runs.")
        // An edit that bypasses the lock still cannot be published as if it were the validated content.
        session.workspace.undo()
        #expect(await apply.value == false)
        #expect(draft.sharedEdit?.id == session.id && !session.isApplying)
        #expect(session.error?.isEmpty == false)
        #expect(try draft.composition() == parent && !draft.hasChanges && !draft.canUndo)
        #expect(SculptureHistoryActions.actions(for: draft).canRedo)
    }

    @Test func aWorldApplyAlsoRejectsContentThatChangedWhileItWasValidated() async throws {
        let parent = try world()
        let draft = SculptureWorldDraft(world: parent)
        draft.beginSharedEdit(modelID: "existing")
        let session = try #require(draft.sharedEdit)
        session.workspace.paint(SculptureCell(x: 0, y: 0, z: 0), start: true)
        session.workspace.endStroke()
        let apply = Task { await draft.applySharedEdit() }
        await Task.yield()
        #expect(session.isApplying && !SculptureHistoryActions.actions(for: draft).canUndo)
        session.workspace.undo()
        #expect(await apply.value == false)
        #expect(draft.sharedEdit?.id == session.id && !session.isApplying && session.error?.isEmpty == false)
        #expect(try draft.world() == parent && !draft.hasChanges)
        // Applying the unchanged content again succeeds and publishes it.
        session.workspace.paint(SculptureCell(x: 0, y: 0, z: 0), start: true)
        session.workspace.endStroke()
        #expect(await draft.applySharedEdit())
        #expect(draft.sharedEdit == nil && draft.hasChanges)
    }

    // MARK: - Menu labels

    @Test func sharedModelMenusTellSameTitleAndSizeModelsApartOnlyWhenTheyCollide() throws {
        let twin = try leaf("Twin", glyph: 35)
        let map = try SculptureTileMap(
            width: 3,
            height: 1,
            layers: [[65, 66, Sculpture.empty]],
            tileSize: .init(width: 4, height: 4, depth: 4),
            bindings: [try .init(glyph: 65, modelID: "twin-a"), try .init(glyph: 66, modelID: "twin-b")]
        )
        let parent = try SculptureComposition(
            title: "Twins",
            rootID: "root",
            models: [
                "root": .tiles(map), "twin-a": .sculpture(twin), "twin-b": .sculpture(twin),
                "twin-c": .sculpture(twin), "solo": .sculpture(leaf("Solo", glyph: 64)),
            ]
        )
        let draft = SculptureCompositionDraft(composition: parent)
        let choices = draft.editableModels
        #expect(choices.map(\.id) == ["solo", "twin-a", "twin-b", "twin-c"], "Identifiers stay stable.")
        #expect(
            choices.map(\.label) == [
                "Solo (1 × 1 × 1 cells)", "Twin (1 × 1 × 1 cells), bound to A", "Twin (1 × 1 × 1 cells), bound to B",
                "Twin (1 × 1 × 1 cells), unbound",
            ]
        )
        #expect(choices.map(\.accessibilityLabel)[1] == "Twin, 1 × 1 × 1 cells, bound to A")
        #expect(choices.map(\.accessibilityLabel)[0] == "Solo, 1 × 1 × 1 cells")
        #expect(choices.allSatisfy { !$0.label.contains("twin-") && !$0.accessibilityLabel.contains("twin-") })

        let world = try SculptureWorld(
            title: "Twin world",
            library: parent,
            instances: [try .init(id: "placed", modelID: "twin-b", origin: .init(x: 5, y: -6, z: 7))]
        )
        let worldChoices = SculptureWorldDraft(world: world).editableModels
        #expect(worldChoices.map(\.id) == ["solo", "twin-a", "twin-b", "twin-c"])
        #expect(
            worldChoices.map(\.label) == [
                "Solo (1 × 1 × 1 cells)", "Twin (1 × 1 × 1 cells), unplaced",
                "Twin (1 × 1 × 1 cells), at 5, -6, 7", "Twin (1 × 1 × 1 cells), unplaced",
            ]
        )
        #expect(worldChoices[2].accessibilityLabel == "Twin, 1 × 1 × 1 cells, at 5, -6, 7")
    }

    // MARK: - Resolved volume and byte budget in the app reader

    @Test func theAppReaderRefusesByNameWhenTheResolvedVolumeBudgetIsFullBeforeDecodingAnyFile() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        // The root has two free cells so only the volume budget can refuse the files.
        var models: [String: SculptureCompositionModel] = [
            "root": .tiles(
                try SculptureTileMap(
                    width: 2,
                    height: 1,
                    layers: [[Sculpture.empty, Sculpture.empty]],
                    tileSize: .init(width: 128, height: 256, depth: 256),
                    bindings: []
                )
            )
        ]
        for id in ["a", "b", "c"] { models[id] = try volumeModel() }
        let full = try SculptureComposition(title: "Full volume", rootID: "root", models: models)
        let plan = try SculptureInsertionPlan(composition: full, at: .init(x: 0, y: 0, z: 0))

        let compact = try SculptureBinaryCodec.encode(leaf("Tiny", glyph: 35))
        var claimed = compact
        for offset in stride(from: 12, to: 18, by: 2) { claimed[offset] = 0; claimed[offset + 1] = 1 }
        claimed[12] = 128
        claimed[13] = 0  // 128 wide so it fits a tile and only the volume budget can refuse it.
        // The first file only claims a large volume in its header and has no body, so refusing it proves no decode ran.
        try Data(claimed.prefix(60 + 4)).write(to: folder.appendingPathComponent("a-huge.3mdb"))
        try SculptureCodec.encode(leaf("Leaf", glyph: 35)).write(to: folder.appendingPathComponent("b-leaf.3md"))
        let budget = SculptureComposition.maximumResolvedVoxelBytes
        #expect(
            throws: SculptureInsertionError.resolvedVolumeExceeded(source: "a-huge.3mdb", maximum: budget)
        ) {
            try SculptureInsertionFiles.read(
                [folder.appendingPathComponent("b-leaf.3md"), folder.appendingPathComponent("a-huge.3mdb")],
                plan: plan
            )
        }
        #expect(
            throws: SculptureInsertionError.resolvedVolumeExceeded(source: "b-leaf.3md", maximum: budget)
        ) {
            try SculptureInsertionFiles.read([folder.appendingPathComponent("b-leaf.3md")], plan: plan)
        }
    }

    @Test func theByteBudgetIsAdmittedForEveryFileBeforeAnyEarlierFileIsDecoded() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        // The first file would fail to decode. The second exceeds the byte budget and must be refused first.
        try Data("not a model".utf8).write(to: folder.appendingPathComponent("a-garbage.3md"))
        let oversized = folder.appendingPathComponent("b-oversized.3mdb")
        try Data().write(to: oversized)
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: UInt64(SculptureInsertionPlan.maximumBytes + 1))
        try handle.close()
        #expect(
            throws: SculptureInsertionError.aggregateBytesExceeded(
                source: "b-oversized.3mdb",
                maximum: SculptureInsertionPlan.maximumBytes
            )
        ) {
            try SculptureInsertionFiles.read([folder.appendingPathComponent("a-garbage.3md"), oversized])
        }
    }

    // MARK: - Canvas

    @Test func theCompositionCanvasHoldsAWholeFolderAndNamesTheLayerItSpillsInto() throws {
        let draft = SculptureCompositionDraft.insertionCanvas()
        #expect(draft.expandedDimensions == "256 × 256 × 256" && draft.width == 4 && draft.depth == 4)
        let plan = try SculptureInsertionPlan(composition: draft.composition(), at: .init(x: 0, y: 0, z: 0))
        try plan.admitFileCount(63)
        #expect(throws: SculptureInsertionError.tooManyModels(current: 1, incoming: 64, maximum: 64)) {
            try plan.admitFileCount(64)
        }
        let inputs = try (0..<20).map { SculptureInsertionInput(scene: .voxels(try leaf("Model \($0)", glyph: 35))) }
        try draft.insert(inputs)
        #expect(draft.pendingInsertion == nil && draft.placementCount == 20)
        #expect(draft.insertionNotice?.contains("20 models") == true)
        #expect(draft.insertionNotice?.contains("continued into another layer") == true)
    }

    // MARK: - Command availability and the importer

    @Test func commandAvailabilityIsOneDecisionForTheFileMenuEditMenuAndPalette() async throws {
        let draft = SculptureCompositionDraft(composition: try composition())
        let worldDraft = SculptureWorldDraft(world: try world())
        let idle = SculptureEditorActivity()
        let blocking: [WritableKeyPath<SculptureEditorActivity, Bool>] = [
            \.isOpening, \.isExporting, \.isSaving, \.isGraphSaving, \.isPortableSaving, \.hasGraphSaveSession,
        ]
        func busy(_ keyPath: WritableKeyPath<SculptureEditorActivity, Bool>) -> SculptureEditorActivity {
            var activity = idle
            activity[keyPath: keyPath] = true
            return activity
        }
        typealias Availability = SculptureEditorCommandAvailability

        #expect(Availability.documentActionsAvailable(sheet: .none, activity: idle))
        for sheet in [SculptureSheetContext.other, .composition(draft), .world(worldDraft)] {
            #expect(!Availability.documentActionsAvailable(sheet: sheet, activity: idle))
        }
        for keyPath in blocking {
            #expect(!Availability.documentActionsAvailable(sheet: .none, activity: busy(keyPath)))
            #expect(Availability.insertionActions(sheet: .composition(draft), activity: busy(keyPath)) == nil)
            #expect(Availability.insertionActions(sheet: .world(worldDraft), activity: busy(keyPath)) == nil)
        }
        #expect(Availability.insertionActions(sheet: .composition(draft), activity: idle) != nil)
        #expect(Availability.insertionActions(sheet: .world(worldDraft), activity: idle) != nil)
        #expect(Availability.insertionActions(sheet: .none, activity: idle) == nil)
        #expect(Availability.insertionActions(sheet: .other, activity: idle) == nil)

        #expect(Availability.sheetHistory(sheet: .none, activity: idle) == nil)
        for sheet in [SculptureSheetContext.other, .none] {
            let history = Availability.sheetHistory(sheet: sheet, activity: busy(\.hasGraphSaveSession))
            #expect(history != nil && history?.canUndo == false && history?.canRedo == false)
        }
        let other = try #require(Availability.sheetHistory(sheet: .other, activity: idle))
        #expect(!other.canUndo && !other.canRedo)
        draft.setTitle("Edited")
        let routed = try #require(Availability.sheetHistory(sheet: .composition(draft), activity: idle))
        #expect(routed.canUndo)

        let palette = SculptureInsertionPalette.actions(enabled: false) { _, _ in }
        #expect(palette.count == 4 && palette.allSatisfy { !$0.enabled })
        let enabled = SculptureInsertionPalette.actions { _, _ in }
        #expect(enabled.allSatisfy { $0.enabled })
    }

    @Test func aDelayedImporterRequestIsPresentedDroppedOrLeftAloneByTheLiveState() {
        typealias Presentation = SculptureInsertionPresentation
        #expect(Presentation.decide(request: .files, canPresent: true, isPresenting: false) == .present(.files))
        #expect(Presentation.decide(request: .folder, canPresent: true, isPresenting: false) == .present(.folder))
        #expect(Presentation.decide(request: .files, canPresent: false, isPresenting: false) == .discard)
        #expect(Presentation.decide(request: nil, canPresent: true, isPresenting: false) == .idle)
        #expect(Presentation.decide(request: .files, canPresent: true, isPresenting: true) == .idle)
        #expect(Presentation.decide(request: .files, canPresent: false, isPresenting: true) == .idle)
    }

    // MARK: - Menu state tracks history

    @Test func historyAvailabilityIsObservedSoMenusRefreshWhenADraftEdits() throws {
        let draft = SculptureCompositionDraft(composition: try composition())
        let composition = Flag()
        withObservationTracking {
            _ = draft.canUndo
        } onChange: {
            composition.raise()
        }
        draft.setTitle("Edited")
        #expect(composition.raised, "A composition edit must invalidate readers of canUndo.")
        let redo = Flag()
        withObservationTracking {
            _ = draft.canRedo
        } onChange: {
            redo.raise()
        }
        draft.undo()
        #expect(redo.raised, "Undo must invalidate readers of canRedo.")

        let worldDraft = SculptureWorldDraft(world: try world())
        let world = Flag()
        withObservationTracking {
            _ = worldDraft.canUndo
        } onChange: {
            world.raise()
        }
        worldDraft.setTitle("Edited")
        #expect(world.raised)
        let worldRedo = Flag()
        withObservationTracking {
            _ = worldDraft.canRedo
        } onChange: {
            worldRedo.raise()
        }
        worldDraft.undo()
        #expect(worldRedo.raised)

        let published = Flag()
        withObservationTracking {
            _ = SculptureHistoryActions.actions(for: draft)
        } onChange: {
            published.raise()
        }
        draft.redo()
        #expect(published.raised, "The published sheet history must refresh with the draft.")
    }

    // MARK: - Fixtures

    private final class Flag: Sendable {
        private let state = OSAllocatedUnfairLock(initialState: false)
        var raised: Bool { state.withLock { $0 } }
        func raise() { state.withLock { $0 = true } }
    }

    private func leaf(_ title: String, glyph: UInt8) throws -> Sculpture {
        try Sculpture(title: title, width: 1, height: 1, layers: [[glyph]])
    }

    private func hugeLeaf() throws -> Sculpture {
        try Sculpture(
            title: "Huge leaf",
            width: 256,
            height: 256,
            layers: Array(repeating: Array(repeating: 35, count: 256 * 256), count: 256)
        )
    }

    private func volumeModel() throws -> SculptureCompositionModel {
        .tiles(
            try SculptureTileMap(
                width: 1,
                height: 1,
                layers: [[Sculpture.empty]],
                tileSize: .init(width: 256, height: 256, depth: 256),
                bindings: []
            )
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

    private func world() throws -> SculptureWorld {
        try SculptureWorld(title: "Parent world", library: occupiedComposition(), instances: [])
    }

    private func temporaryDirectory() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("RookRepair-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return folder
    }

    private func wait(_ isRunning: () -> Bool) async {
        for _ in 0..<2_000_000 where isRunning() { await Task.yield() }
        #expect(!isRunning())
    }
}
