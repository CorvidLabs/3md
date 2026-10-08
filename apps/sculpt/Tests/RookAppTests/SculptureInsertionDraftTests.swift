import Foundation
import RookSculpture
import Testing
import ThreeMD

@testable import RookApp

@Suite("Native model insertion", .serialized)
@MainActor
struct SculptureInsertionDraftTests {
    @Test func compositionBatchPlacesNestedModelsAndRestoresTheCompleteSnapshotWithOneUndo() throws {
        let parent = try composition()
        let baseline = try identifiedSnapshot(.composition(parent), prefix: "parent")
        let child = try nestedComposition()
        let childSnapshot = try identifiedSnapshot(.composition(child), prefix: "child")
        let first = try leaf("First", glyph: 35)
        let draft = SculptureCompositionDraft(composition: parent, portableSnapshot: baseline)

        try draft.insert([
            .init(scene: .voxels(first)),
            .init(scene: .composition(child), snapshot: childSnapshot),
        ])

        let inserted = try draft.composition()
        let captured = try #require(draft.portableSnapshot)
        guard case .tiles(let map) = inserted.models[inserted.rootID] else {
            Issue.record("Insertion flattened the parent map")
            return
        }
        #expect(map.layers == [[65, 66, Sculpture.empty, Sculpture.empty]])
        #expect(try map.tileSize == .init(width: 4, height: 4, depth: 4))
        try #require(map.bindings.count == 2)
        #expect(inserted.models.count == 5)
        #expect(inserted.models[map.bindings[0].modelID] == .sculpture(first))
        guard case .tiles(let nested) = inserted.models[map.bindings[1].modelID] else {
            Issue.record("The inserted child lost its nested map")
            return
        }
        #expect(nested.bindings.count == 1 && nested.layers == [[67, 67]])
        let nestedLeaf = try #require(nested.bindings.first?.modelID)
        #expect(inserted.models[nestedLeaf] == child.models["leaf"])
        let unused = try #require(child.models["unused"])
        #expect(inserted.models.values.contains(unused))
        let expanded = try inserted.expanded()
        #expect(expanded.glyph(at: .init(x: 0, y: 0, z: 0)) == 35)
        #expect(expanded.glyph(at: .init(x: 4, y: 0, z: 0)) == 64)
        #expect(draft.selectedGlyph == 66 && draft.hasChanges && draft.canUndo && !draft.canRedo)
        #expect(draft.library.first { $0.id == 66 }?.title == "Nested child")
        #expect(captured.scene == .composition(inserted) && captured.revision != baseline.revision)
        #expect(captured.revision.canonicalContent.contains("parent-plane-root-0"))
        #expect(captured.revision.canonicalContent.contains("child-ref-root-0"))
        #expect(captured.revision.canonicalContent.contains("kept-opaque-reference"))
        #expect(
            try SculptureThreeMDCodec.decode(SculptureThreeMDCodec.encode(captured)).scene == .composition(inserted)
        )

        draft.undo()
        #expect(try draft.composition() == parent && draft.portableSnapshot == baseline)
        #expect(!draft.hasChanges && !draft.canUndo && draft.canRedo)
        draft.redo()
        #expect(try draft.composition() == inserted && draft.portableSnapshot == captured)
        #expect(draft.hasChanges && draft.canUndo && !draft.canRedo)
    }

    @Test func worldBatchPlacesAtExactFocusAndKeepsLibraryAndSnapshotInOneHistoryEntry() throws {
        let parent = try world()
        let baseline = try identifiedSnapshot(.world(parent), prefix: "world")
        let draft = SculptureWorldDraft(world: parent, portableSnapshot: baseline)
        let focus = SculptureWorldPoint(x: 9_007_199_254_740_993, y: Int64.min, z: Int64.max - 300)
        draft.focusX = String(focus.x)
        draft.focusY = String(focus.y)
        draft.focusZ = String(focus.z)
        let first = try leaf("First", glyph: 35, width: 2)
        let nested = try nestedComposition()

        try draft.insert([.init(scene: .voxels(first)), .init(scene: .composition(nested))])

        let inserted = try draft.world()
        let captured = try #require(draft.portableSnapshot)
        #expect(inserted.instances.count == parent.instances.count + 2)
        #expect(Array(inserted.instances.prefix(parent.instances.count)) == parent.instances)
        let placements = Array(inserted.instances.suffix(2))
        try #require(placements.count == 2)
        #expect(placements[0].origin == focus)
        #expect(placements[1].origin == .init(x: focus.x + 3, y: focus.y, z: focus.z))
        #expect(placements.allSatisfy { $0.quarterTurns == 0 })
        #expect(inserted.library.models[placements[0].modelID] == .sculpture(first))
        guard case .tiles = inserted.library.models[placements[1].modelID] else {
            Issue.record("The placed nested child was flattened")
            return
        }
        #expect(inserted.library.models.count == parent.library.models.count + 4)
        #expect(draft.selectedInstanceID == placements[1].id && draft.selectedModelID == placements[1].modelID)
        #expect(draft.modelChoices.first { $0.id == placements[1].modelID }?.title == "Nested child")
        #expect(captured.scene == .world(inserted) && captured.revision != baseline.revision)
        #expect(captured.revision.canonicalContent.contains("world-plane-root-0"))
        #expect(draft.hasChanges && draft.canUndo && !draft.canRedo)
        let binary = try SculptureThreeMDCodec.encode(captured, format: .binary(compression: .none))
        #expect(try SculptureThreeMDCodec.decode(binary) == captured)

        draft.undo()
        #expect(try draft.world() == parent && draft.portableSnapshot == baseline)
        #expect(!draft.hasChanges && !draft.canUndo && draft.canRedo)
        draft.redo()
        #expect(try draft.world() == inserted && draft.portableSnapshot == captured)
        #expect(draft.hasChanges && draft.canUndo && !draft.canRedo)
    }

    @Test func compositionRefusalsNeverPublishAPartialBatchOrCreateHistory() throws {
        let parent = try composition()
        let captured = try SculptureThreeMDCodec.capture(.composition(parent))
        let draft = SculptureCompositionDraft(composition: parent, portableSnapshot: captured)
        let revision = draft.revision
        let valid = SculptureInsertionInput(scene: .voxels(try leaf("Valid", glyph: 35)))
        let unsupported = SculptureInsertionInput(scene: .world(try world()))
        #expect(throws: SculptureInsertionError.unsupportedChild) { try draft.insert([valid, unsupported]) }
        #expect(throws: SculptureInsertionError.noInputs) { try draft.insert([]) }
        #expect(throws: SculptureInsertionError.insufficientCells(needed: 5, available: 4)) {
            try draft.insert(Array(repeating: valid, count: 5))
        }
        #expect(
            throws: SculptureInsertionError.modelDoesNotFit(
                source: "Too wide",
                required: "5 × 1 × 1",
                current: "4 × 4 × 4"
            )
        ) {
            try draft.insert([valid, .init(scene: .voxels(leaf("Too wide", glyph: 35, width: 5)))])
        }
        let mismatched = SculptureInsertionInput(
            scene: valid.scene,
            snapshot: try SculptureThreeMDCodec.capture(.voxels(leaf("Other", glyph: 64)))
        )
        #expect(throws: SculptureInsertionError.mismatchedSnapshot) { try draft.insert([mismatched]) }
        #expect(try draft.composition() == parent && draft.portableSnapshot == captured)
        #expect(draft.revision == revision && !draft.hasChanges && !draft.canUndo && !draft.canRedo)
    }

    @Test func failedInsertionRetainsAnExistingRedoAndSavedBaseline() throws {
        let parent = try composition()
        let draft = SculptureCompositionDraft(composition: parent)
        let input = SculptureInsertionInput(scene: .voxels(try leaf("Inserted", glyph: 35)))
        try draft.insert([input])
        let changed = try draft.composition()
        let changedSnapshot = draft.portableSnapshot
        draft.undo()
        #expect(!draft.hasChanges && !draft.canUndo && draft.canRedo)
        #expect(throws: SculptureInsertionError.noInputs) { try draft.insert([]) }
        #expect(try draft.composition() == parent && draft.portableSnapshot == nil)
        #expect(!draft.hasChanges && !draft.canUndo && draft.canRedo)
        draft.redo()
        #expect(try draft.composition() == changed && draft.portableSnapshot == changedSnapshot)
        draft.markSaved(changed)
        #expect(!draft.hasChanges)
        draft.undo()
        #expect(draft.hasChanges)
        draft.redo()
        #expect(!draft.hasChanges)
    }

    @Test func exhaustedGlyphLedgerRefusesInsertionWithoutChangingTheMapOrHistory() throws {
        let bindings = try (33...126).map(UInt8.init).filter { $0 != Sculpture.empty }.map {
            try SculptureModelBinding(glyph: $0, modelID: "leaf")
        }
        let map = try SculptureTileMap(
            width: 1,
            height: 1,
            layers: [[65]],
            tileSize: .init(width: 1, height: 1, depth: 1),
            bindings: bindings
        )
        let parent = try SculptureComposition(
            title: "Full ledger",
            rootID: "root",
            models: ["root": .tiles(map), "leaf": .sculpture(leaf("Existing", glyph: 35))]
        )
        let draft = SculptureCompositionDraft(composition: parent)
        #expect(throws: SculptureInsertionError.noAvailableGlyph(needed: 1, available: 0)) {
            try draft.insert([.init(scene: .voxels(leaf("Incoming", glyph: 64)))])
        }
        #expect(try draft.composition() == parent && draft.portableSnapshot == nil)
        #expect(!draft.hasChanges && !draft.canUndo && !draft.canRedo)
    }

    @Test func worldRefusalsKeepExactDocumentHistoryAndPortableSnapshot() throws {
        let parent = try world()
        let baseline = try SculptureThreeMDCodec.capture(.world(parent))
        let draft = SculptureWorldDraft(world: parent, portableSnapshot: baseline)
        let revision = draft.documentRevision
        let geometry = draft.sceneRevision
        let input = SculptureInsertionInput(scene: .voxels(try leaf("Wide", glyph: 35, width: 256)))
        #expect(throws: SculptureInsertionError.noInputs) { try draft.insert([]) }
        #expect(throws: SculptureInsertionError.unsupportedChild) { try draft.insert([.init(scene: .world(parent))]) }
        draft.focusX = String(Int64.max - 256)
        #expect(throws: SculptureInsertionError.coordinateOverflow) { try draft.insert([input, input]) }
        draft.focusX = String(Int64.max)
        #expect(throws: SculptureWorldError.invalidOrigin) { try draft.insert([input]) }
        #expect(try draft.world() == parent && draft.portableSnapshot == baseline)
        #expect(draft.documentRevision == revision && draft.sceneRevision == geometry)
        #expect(!draft.hasChanges && !draft.canUndo && !draft.canRedo)
    }

    @Test func multiselectUsesNaturalFilenameOrderNotSelectionOrderAndRetainsPortableInputs() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let one = try leaf("One", glyph: 35)
        let two = try leaf("Two", glyph: 64)
        let tenth = try nestedComposition()
        let tenthSnapshot = try identifiedSnapshot(.composition(tenth), prefix: "selected")
        let first = folder.appendingPathComponent("model1.3md")
        let second = folder.appendingPathComponent("model2.3md")
        let last = folder.appendingPathComponent("model10.3mdb")
        try SculptureCodec.encode(one).write(to: first)
        try SculptureCodec.encode(two).write(to: second)
        try SculptureThreeMDCodec.encode(tenthSnapshot, format: .binary(compression: .none)).write(to: last)
        let inputs = try SculptureInsertionFiles.read([last, first, second])
        try #require(inputs.count == 3)
        #expect(inputs.map(\.scene) == [.voxels(one), .voxels(two), .composition(tenth)])
        #expect(inputs.map(\.sourceName) == ["model1.3md", "model2.3md", "model10.3mdb"])
        #expect(inputs[0].snapshot == nil && inputs[2].snapshot == tenthSnapshot)
        #expect(try SculptureInsertionFiles.read([first, second, last]) == inputs)
    }

    @Test func equalFilenamesInDifferentFoldersKeepAStablePathOrder() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let left = folder.appendingPathComponent("left")
        let right = folder.appendingPathComponent("right")
        for directory in [left, right] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        }
        try SculptureCodec.encode(leaf("Left", glyph: 35)).write(to: left.appendingPathComponent("model.3md"))
        try SculptureCodec.encode(leaf("Right", glyph: 64)).write(to: right.appendingPathComponent("model.3md"))
        let a = left.appendingPathComponent("model.3md")
        let b = right.appendingPathComponent("model.3md")
        let forward = try SculptureInsertionFiles.read([a, b])
        let backward = try SculptureInsertionFiles.read([b, a])
        #expect(forward == backward)
        #expect(forward.map(\.scene.title) == ["Left", "Right"])
    }

    @Test func recursiveFolderSelectionSkipsHiddenUnsupportedAndSymbolicEntries() throws {
        let temporary = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let folder = temporary.appendingPathComponent("models")
        let nested = folder.appendingPathComponent("nested")
        let hidden = folder.appendingPathComponent(".hidden")
        let outside = temporary.appendingPathComponent("outside")
        for directory in [nested, hidden, outside] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let first = try leaf("First", glyph: 35)
        let second = try leaf("Second", glyph: 64)
        let skipped = try leaf("Skipped", glyph: 42)
        let a = folder.appendingPathComponent("a.3md")
        let b = nested.appendingPathComponent("b.3MDB")
        try SculptureCodec.encode(first).write(to: a)
        try SculptureDocumentCodec.encode(second, format: .compact).write(to: b)
        try SculptureCodec.encode(skipped).write(to: hidden.appendingPathComponent("hidden.3md"))
        try SculptureCodec.encode(skipped).write(to: outside.appendingPathComponent("outside.3md"))
        try Data("ignored".utf8).write(to: folder.appendingPathComponent("notes.txt"))
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link.3md"), withDestinationURL: a)
        try FileManager.default.createSymbolicLink(
            at: folder.appendingPathComponent("linked-folder"),
            withDestinationURL: outside
        )
        let inputs = try SculptureInsertionFiles.readFolder(folder)
        #expect(throws: (any Error).self) {
            try SculptureInsertionFiles.readFolder(folder.appendingPathComponent("linked-folder"))
        }
        #expect(inputs.map(\.scene) == [.voxels(first), .voxels(second)])
        #expect(try inputs == SculptureInsertionFiles.read([b, a]))
    }

    @Test func fileSelectionRefusesEmptyUnsupportedSymlinkAndOversizedInputsNamingTheFileAndLimit() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("valid.3md")
        try SculptureCodec.encode(leaf("Valid", glyph: 35)).write(to: file)
        let invalid = folder.appendingPathComponent("invalid.3md")
        try Data("not a model".utf8).write(to: invalid)
        let link = folder.appendingPathComponent("link.3md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        #expect(throws: SculptureInsertionError.noInputs) { try SculptureInsertionFiles.read([]) }
        #expect(throws: SculptureInsertionError.self) { try SculptureInsertionFiles.read([folder]) }
        #expect(throws: SculptureInsertionError.self) { try SculptureInsertionFiles.read([link]) }
        #expect(throws: (any Error).self) { try SculptureInsertionFiles.read([file, invalid]) }
        #expect(throws: (any Error).self) { try SculptureInsertionFiles.readFolder(folder) }
        let count = SculptureInsertionFiles.maximumFiles + 1
        #expect(throws: SculptureInsertionError.tooManyFiles(count: count, maximum: count - 1)) {
            try SculptureInsertionFiles.read(Array(repeating: file, count: count))
        }
        let oversized = folder.appendingPathComponent("oversized.3mdb")
        try Data().write(to: oversized)
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: UInt64(SculptureInsertionFiles.maximumBytes + 1))
        try handle.close()
        do {
            _ = try SculptureInsertionFiles.read([oversized])
            Issue.record("An oversized file was accepted")
        } catch SculptureInsertionError.aggregateBytesExceeded(let source, let maximum) {
            #expect(source == "oversized.3mdb" && maximum == SculptureInsertionFiles.maximumBytes)
            let message = SculptureInsertionError.aggregateBytesExceeded(source: source, maximum: maximum)
                .localizedDescription
            #expect(message.contains("oversized.3mdb") && message.contains("20 MiB"))
        }
        let empty = folder.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: false)
        try Data("not a model".utf8).write(to: empty.appendingPathComponent("notes.txt"))
        do {
            _ = try SculptureInsertionFiles.readFolder(empty)
            Issue.record("An empty folder was accepted")
        } catch SculptureInsertionError.source(let name, let reason) {
            #expect(name == "empty" && reason == SculptureInsertionFiles.Failure.emptyFolder.localizedDescription)
        }
        let tooMany = folder.appendingPathComponent("too-many")
        try FileManager.default.createDirectory(at: tooMany, withIntermediateDirectories: false)
        for index in 0...SculptureInsertionFiles.maximumFiles {
            try Data().write(to: tooMany.appendingPathComponent("model-\(index).3md"))
        }
        do {
            _ = try SculptureInsertionFiles.readFolder(tooMany)
            Issue.record("A folder with too many files was accepted")
        } catch SculptureInsertionError.source(let name, let reason) {
            #expect(name == "too-many")
            #expect(reason.contains("\(count) files") && reason.contains("\(count - 1)"))
        }
    }

    @Test func earlyChecksRefuseAnOversizedBatchBeforeDecodingEveryFile() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        // Two invalid files would each fail to decode. The batch is refused by count and cells before either is read.
        let broken = (0..<2).map { folder.appendingPathComponent("broken-\($0).3md") }
        for url in broken { try Data("not a model".utf8).write(to: url) }
        let parent = try SculptureComposition(
            title: "One cell",
            rootID: "root",
            models: [
                "root": .tiles(
                    try SculptureTileMap(
                        width: 1,
                        height: 1,
                        layers: [[Sculpture.empty]],
                        tileSize: .init(width: 4, height: 4, depth: 4),
                        bindings: []
                    )
                )
            ]
        )
        let plan = try SculptureInsertionPlan(composition: parent, at: .init(x: 0, y: 0, z: 0))
        #expect(throws: SculptureInsertionError.insufficientCells(needed: 2, available: 1)) {
            try SculptureInsertionFiles.read(broken, plan: plan)
        }
        // A model too large for the tile is refused by name right after its own decode, before later files are read.
        let wide = folder.appendingPathComponent("a-wide.3md")
        try SculptureCodec.encode(leaf("Wide", glyph: 35, width: 5)).write(to: wide)
        let afterWide = try SculptureComposition(
            title: "Two cells",
            rootID: "root",
            models: [
                "root": .tiles(
                    try SculptureTileMap(
                        width: 2,
                        height: 1,
                        layers: [[Sculpture.empty, Sculpture.empty]],
                        tileSize: .init(width: 4, height: 4, depth: 4),
                        bindings: []
                    )
                )
            ]
        )
        let second = try SculptureInsertionPlan(composition: afterWide, at: .init(x: 0, y: 0, z: 0))
        #expect(
            throws: SculptureInsertionError.modelDoesNotFit(
                source: "a-wide.3md",
                required: "5 × 1 × 1",
                current: "4 × 4 × 4"
            )
        ) {
            try SculptureInsertionFiles.read([broken[0], wide], plan: second)
        }
    }

    @Test func cancelledFileReadsAndDraftInsertionNeverPublishOrCreateHistory() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("valid.3md")
        try SculptureCodec.encode(leaf("Valid", glyph: 35)).write(to: file)
        let reading = Task.detached {
            while !Task.isCancelled { await Task.yield() }
            return try SculptureInsertionFiles.read([file])
        }
        reading.cancel()
        await #expect(throws: CancellationError.self) { try await reading.value }
        let scanning = Task.detached {
            while !Task.isCancelled { await Task.yield() }
            return try SculptureInsertionFiles.readFolder(folder)
        }
        scanning.cancel()
        await #expect(throws: CancellationError.self) { try await scanning.value }

        let parent = try composition()
        let captured = try SculptureThreeMDCodec.capture(.composition(parent))
        let compositionDraft = SculptureCompositionDraft(composition: parent, portableSnapshot: captured)
        compositionDraft.importModels(from: [file])
        compositionDraft.cancelPreparation()
        let originalWorld = try world()
        let worldSnapshot = try SculptureThreeMDCodec.capture(.world(originalWorld))
        let worldDraft = SculptureWorldDraft(world: originalWorld, portableSnapshot: worldSnapshot)
        worldDraft.importFolder(from: folder)
        worldDraft.cancelModelPreparation()
        for _ in 0..<100 { await Task.yield() }
        #expect(try compositionDraft.composition() == parent && compositionDraft.portableSnapshot == captured)
        #expect(!compositionDraft.isPreparing && !compositionDraft.hasChanges && !compositionDraft.canUndo)
        #expect(try worldDraft.world() == originalWorld && worldDraft.portableSnapshot == worldSnapshot)
        #expect(!worldDraft.isOpeningModel && !worldDraft.hasChanges && !worldDraft.canUndo)
    }

    @Test func nativeFolderInsertionAutomaticallyPlacesTheBatchAndUnsupportedSelectionIsAtomic() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try leaf("First", glyph: 35)
        let second = try leaf("Second", glyph: 64)
        try SculptureCodec.encode(second).write(to: folder.appendingPathComponent("b.3md"))
        try SculptureCodec.encode(first).write(to: folder.appendingPathComponent("a.3md"))
        let parent = try composition()
        let draft = SculptureCompositionDraft(composition: parent)
        draft.importFolder(from: folder)
        await wait { draft.isPreparing }
        let inserted = try draft.composition()
        #expect(draft.error == nil && draft.hasChanges && draft.canUndo)
        #expect(try inserted.expanded().glyph(at: .init(x: 0, y: 0, z: 0)) == 35)
        #expect(try inserted.expanded().glyph(at: .init(x: 4, y: 0, z: 0)) == 64)
        draft.undo()
        #expect(try draft.composition() == parent && !draft.hasChanges && !draft.canUndo && draft.canRedo)
        let invalid = folder.appendingPathComponent("invalid.3md")
        try Data("unsupported".utf8).write(to: invalid)
        draft.importModels(from: [folder.appendingPathComponent("a.3md"), invalid])
        await wait { draft.isPreparing }
        #expect(draft.error != nil)
        #expect(try draft.composition() == parent && draft.portableSnapshot == nil)
        #expect(!draft.hasChanges && !draft.canUndo && draft.canRedo)
    }

    @Test func worldInsertionRejectsAParentChangedDuringFilePreparation() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("child.3md")
        try SculptureCodec.encode(leaf("Child", glyph: 35)).write(to: file)
        let parent = try world()
        let captured = try SculptureThreeMDCodec.capture(.world(parent))
        let draft = SculptureWorldDraft(world: parent, portableSnapshot: captured)
        draft.importModels(from: [file])
        draft.setTitle("Newer parent")
        let newer = try draft.world()
        await wait { draft.isOpeningModel }
        #expect(try draft.world() == newer && draft.portableSnapshot == captured)
        #expect(draft.error?.contains("changed while insertion") == true)
        #expect(draft.hasChanges && draft.canUndo && !draft.canRedo)
        draft.undo()
        #expect(try draft.world() == parent && !draft.hasChanges && !draft.canUndo)
    }

    @Test func selectToolChoosesTheInsertionStartWithoutPaintingOrChangingHistory() throws {
        let parent = try occupiedComposition()
        let captured = try identifiedSnapshot(.composition(parent), prefix: "selection")
        let draft = SculptureCompositionDraft(composition: parent, portableSnapshot: captured)
        let revision = draft.revision
        draft.brush = .select
        draft.paint(.init(x: 2, y: 0, z: 0))
        draft.paint(.init(x: 3, y: 0, z: 0))
        draft.selectCell(.init(x: 99, y: 0, z: 0))
        #expect(draft.selectedCell == .init(x: 3, y: 0, z: 0))
        #expect(draft.insertionStartDescription == "Insertion start: column 4, row 1, layer 1.")
        #expect(try draft.composition() == parent && draft.portableSnapshot == captured)
        #expect(draft.revision == revision && !draft.hasChanges && !draft.canUndo && !draft.canRedo)
    }

    @Test func occupiedTargetsRequireConfirmationAndCancelPreservesTheCompleteParent() throws {
        let parent = try occupiedComposition()
        let captured = try identifiedSnapshot(.composition(parent), prefix: "confirmation")
        let draft = SculptureCompositionDraft(composition: parent, portableSnapshot: captured)
        let revision = draft.revision
        let inputs = [
            SculptureInsertionInput(scene: .voxels(try leaf("First incoming", glyph: 35))),
            SculptureInsertionInput(scene: .composition(try nestedComposition())),
        ]
        try draft.insert(inputs)
        let pending = try #require(draft.pendingInsertion)
        #expect(pending.replacementCount == 1)
        #expect(pending.targets.map(\.cell) == [.init(x: 0, y: 0, z: 0), .init(x: 1, y: 0, z: 0)])
        #expect(pending.targets.map(\.incomingTitle) == ["First incoming", "Nested child"])
        #expect(pending.targets[0].currentGlyph == 65 && pending.targets[0].currentTitle == "Existing castle")
        #expect(pending.targets[1].currentGlyph == Sculpture.empty)
        #expect(pending.targetSummary.contains("column 1, row 1, layer 1"))
        #expect(pending.targetSummary.contains("column 2, row 1, layer 1"))
        #expect(draft.isBusy && !draft.canUseInWorld)
        #expect(try draft.composition() == parent && draft.portableSnapshot == captured && draft.revision == revision)
        #expect(!draft.hasChanges && !draft.canUndo && !draft.canRedo)
        #expect(!draft.confirmInsertion(id: UUID()) && draft.pendingInsertion?.id == pending.id)

        draft.cancelPendingInsertion()
        #expect(!draft.confirmInsertion(id: pending.id) && draft.pendingInsertion == nil)
        #expect(!draft.isBusy && draft.canUseInWorld)
        #expect(try draft.composition() == parent && draft.portableSnapshot == captured && draft.revision == revision)
        #expect(!draft.hasChanges && !draft.canUndo && !draft.canRedo)

        try draft.insert(inputs)
        let accepted = try #require(draft.pendingInsertion)
        #expect(draft.confirmInsertion(id: accepted.id))
        let inserted = try draft.composition()
        let insertedSnapshot = try #require(draft.portableSnapshot)
        guard case .tiles(let map) = inserted.models[inserted.rootID] else {
            Issue.record("Confirmed insertion did not retain the tile map")
            return
        }
        #expect(map.layers == [[66, 67, 65, Sculpture.empty]])
        #expect(inserted.models["existing"] == parent.models["existing"])
        #expect(insertedSnapshot == accepted.result.snapshot)
        #expect(draft.pendingInsertion == nil && draft.canUseInWorld && draft.hasChanges && draft.canUndo)
        #expect(!draft.confirmInsertion(id: accepted.id))
        draft.undo()
        #expect(try draft.composition() == parent && draft.portableSnapshot == captured)
        #expect(!draft.hasChanges && !draft.canUndo && draft.canRedo)
        draft.redo()
        #expect(try draft.composition() == inserted && draft.portableSnapshot == insertedSnapshot)
        #expect(draft.hasChanges && draft.canUndo && !draft.canRedo)
    }

    @Test func editedParentInvalidatesReplacementConfirmationWithoutPublishingTheCandidate() throws {
        let parent = try occupiedComposition()
        let captured = try identifiedSnapshot(.composition(parent), prefix: "stale-parent")
        let draft = SculptureCompositionDraft(composition: parent, portableSnapshot: captured)
        try draft.insert([.init(scene: .voxels(leaf("Incoming", glyph: 35)))])
        let pending = try #require(draft.pendingInsertion)
        draft.setTitle("Newer parent")
        let newer = try draft.composition()
        #expect(!draft.confirmInsertion(id: pending.id) && draft.pendingInsertion == nil)
        #expect(try draft.composition() == newer && draft.portableSnapshot == captured)
        #expect(draft.hasChanges && draft.canUndo && !draft.canRedo)
        draft.undo()
        #expect(try draft.composition() == parent && draft.portableSnapshot == captured)
        #expect(!draft.hasChanges && !draft.canUndo)
    }

    @Test func changedStartAndSavedSnapshotInvalidateReplacementConfirmationWithoutHistory() throws {
        let parent = try occupiedComposition()
        let original = try identifiedSnapshot(.composition(parent), prefix: "original-save")
        let saved = try identifiedSnapshot(.composition(parent), prefix: "completed-save")
        let draft = SculptureCompositionDraft(composition: parent, portableSnapshot: original)
        let revision = draft.revision
        let input = SculptureInsertionInput(scene: .voxels(try leaf("Incoming", glyph: 35)))
        try draft.insert([input])
        let first = try #require(draft.pendingInsertion)
        draft.selectCell(.init(x: 2, y: 0, z: 0))
        #expect(!draft.confirmInsertion(id: first.id) && draft.pendingInsertion == nil)
        #expect(try draft.composition() == parent && draft.portableSnapshot == original)
        try draft.insert([input])
        let second = try #require(draft.pendingInsertion)
        draft.retainPortableSnapshot(saved)
        #expect(!draft.confirmInsertion(id: second.id) && draft.pendingInsertion == nil)
        #expect(try draft.composition() == parent && draft.portableSnapshot == saved)
        #expect(draft.selectedCell == .init(x: 2, y: 0, z: 0))
        #expect(draft.revision == revision && !draft.hasChanges && !draft.canUndo && !draft.canRedo)
    }

    @Test func filePreparationStagesOccupiedTargetsBeforeAnyMutation() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("incoming-castle.3md")
        try SculptureCodec.encode(leaf("Incoming castle", glyph: 35)).write(to: file)
        let parent = try occupiedComposition()
        let captured = try identifiedSnapshot(.composition(parent), prefix: "async-parent")
        let draft = SculptureCompositionDraft(composition: parent, portableSnapshot: captured)
        draft.importModels(from: [file])
        #expect(draft.isPreparing && !draft.canUseInWorld)
        await wait { draft.isPreparing }
        let pending = try #require(draft.pendingInsertion)
        #expect(pending.targets.first?.incomingTitle == "Incoming castle")
        #expect(draft.error == nil && !draft.canUseInWorld)
        #expect(try draft.composition() == parent && draft.portableSnapshot == captured)
        #expect(!draft.hasChanges && !draft.canUndo && !draft.canRedo)
        #expect(draft.confirmInsertion(id: pending.id))
        #expect(draft.canUseInWorld && draft.hasChanges && draft.canUndo && !draft.canRedo)
        draft.undo()
        #expect(try draft.composition() == parent && draft.portableSnapshot == captured)
        #expect(!draft.hasChanges && !draft.canUndo)
    }

    @Test func compositionEditsDuringPreparationCancelTheCandidateAndRetainOnlyTheEditHistory() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("child.3md")
        try SculptureCodec.encode(leaf("Child", glyph: 35)).write(to: file)
        let parent = try occupiedComposition()
        let captured = try identifiedSnapshot(.composition(parent), prefix: "editing-parent")
        let draft = SculptureCompositionDraft(composition: parent, portableSnapshot: captured)
        draft.importModels(from: [file])
        draft.setTitle("Newer parent")
        let newer = try draft.composition()
        for _ in 0..<100 { await Task.yield() }
        #expect(!draft.isPreparing && draft.pendingInsertion == nil && draft.canUseInWorld)
        #expect(try draft.composition() == newer && draft.portableSnapshot == captured)
        #expect(draft.hasChanges && draft.canUndo && !draft.canRedo)
        draft.undo()
        #expect(try draft.composition() == parent && draft.portableSnapshot == captured)
        #expect(!draft.hasChanges && !draft.canUndo)
    }

    @Test func saveFinishingDuringCompositionPreparationRetainsItsSnapshotWithoutInsertion() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("child.3md")
        try SculptureCodec.encode(leaf("Child", glyph: 35)).write(to: file)
        let parent = try composition()
        let original = try identifiedSnapshot(.composition(parent), prefix: "before-save")
        let saved = try identifiedSnapshot(.composition(parent), prefix: "after-save")
        let draft = SculptureCompositionDraft(composition: parent, portableSnapshot: original)
        let revision = draft.revision
        draft.importModels(from: [file])
        draft.retainPortableSnapshot(saved)
        draft.markSaved(parent)
        for _ in 0..<100 { await Task.yield() }
        #expect(!draft.isPreparing && draft.pendingInsertion == nil)
        #expect(try draft.composition() == parent && draft.portableSnapshot == saved && draft.revision == revision)
        #expect(!draft.hasChanges && !draft.canUndo && !draft.canRedo)
    }

    @Test func worldInsertionRejectsASnapshotChangedByACompletedSaveDuringPreparation() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("child.3md")
        try SculptureCodec.encode(leaf("Child", glyph: 35)).write(to: file)
        let parent = try world()
        let original = try identifiedSnapshot(.world(parent), prefix: "before-world-save")
        let saved = try identifiedSnapshot(.world(parent), prefix: "after-world-save")
        let draft = SculptureWorldDraft(world: parent, portableSnapshot: original)
        let revision = draft.documentRevision
        draft.importModels(from: [file])
        draft.retainPortableSnapshot(saved)
        draft.markSaved(parent)
        await wait { draft.isOpeningModel }
        #expect(try draft.world() == parent && draft.portableSnapshot == saved && draft.documentRevision == revision)
        #expect(draft.error?.contains("changed while insertion") == true)
        #expect(!draft.hasChanges && !draft.canUndo && !draft.canRedo)
    }

    @Test func worldInsertionRejectsFocusChangesDuringPreparationWithoutLosingTheNewFocus() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("child.3md")
        try SculptureCodec.encode(leaf("Child", glyph: 35)).write(to: file)
        let parent = try world()
        let captured = try SculptureThreeMDCodec.capture(.world(parent))
        let draft = SculptureWorldDraft(world: parent, portableSnapshot: captured)
        draft.importModels(from: [file])
        draft.focusX = "9007199254740993"
        #expect(draft.applyFocus())
        await wait { draft.isOpeningModel }
        #expect(draft.focus.x == 9_007_199_254_740_993)
        #expect(try draft.world() == parent && draft.portableSnapshot == captured)
        #expect(draft.error?.contains("changed while insertion") == true)
        #expect(!draft.hasChanges && !draft.canUndo && !draft.canRedo)

        draft.importModels(from: [file])
        draft.focusY = "uncommitted coordinate"
        await wait { draft.isOpeningModel }
        #expect(draft.focusY == "uncommitted coordinate")
        #expect(try draft.world() == parent && !draft.canUndo && !draft.hasChanges)
    }

    @Test func fileRefusalsIdentifyTheFilenameWithoutExposingItsPrivateDirectory() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let invalid = folder.appendingPathComponent("bad-castle.3md")
        try Data("not a model".utf8).write(to: invalid)
        for file in [invalid, folder.appendingPathComponent("missing-castle.3md")] {
            do {
                _ = try SculptureInsertionFiles.read([file])
                Issue.record("An invalid selected file was accepted")
            } catch SculptureInsertionError.source(let filename, let reason) {
                #expect(filename == file.lastPathComponent && !reason.isEmpty)
                let message = SculptureInsertionError.source(name: filename, reason: reason).localizedDescription
                #expect(message.hasPrefix(file.lastPathComponent + ":"))
                #expect(!message.contains(folder.path))
            }
        }
    }

    @Test func tileFitRefusalNamesTheModelAndRequiredAndCurrentDimensions() throws {
        let parent = try composition()
        let draft = SculptureCompositionDraft(composition: parent)
        do {
            try draft.insert([.init(scene: .voxels(leaf("Wide castle", glyph: 35, width: 5)))])
            Issue.record("The oversized model was accepted")
        } catch SculptureInsertionError.modelDoesNotFit(let source, let required, let current) {
            #expect(source == "Wide castle" && required == "5 × 1 × 1" && current == "4 × 4 × 4")
            let message = SculptureInsertionError.modelDoesNotFit(source: source, required: required, current: current)
                .localizedDescription
            #expect(message.contains("Wide castle") && message.contains(required) && message.contains(current))
            #expect(!message.contains("insert-model"))
        }
        #expect(try draft.composition() == parent && draft.portableSnapshot == nil)
        #expect(draft.pendingInsertion == nil && !draft.hasChanges && !draft.canUndo && !draft.canRedo)
    }

    @Test func portableActionsResumeOnlyAfterPreparationAndReplacementDecisionFinish() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("incoming-castle.3md")
        try SculptureCodec.encode(leaf("Incoming castle", glyph: 35)).write(to: file)
        let parent = try occupiedComposition()
        let captured = try identifiedSnapshot(.composition(parent), prefix: "portable-actions")
        let draft = SculptureCompositionDraft(composition: parent, portableSnapshot: captured)
        var exports: [SculpturePortableFormat] = []
        @MainActor func actions() -> SculpturePortableActions? {
            SculptureEditor.portableActions(
                for: draft,
                exportReadable: { exports.append(.readable) },
                exportBinary: { exports.append(.binary) }
            )
        }
        let initial = try #require(actions())
        initial.exportReadable()
        initial.exportBinary()
        #expect(exports == [.readable, .binary])

        draft.importModels(from: [file])
        #expect(draft.isPreparing && actions() == nil)
        await wait { draft.isPreparing }
        _ = try #require(draft.pendingInsertion)
        #expect(actions() == nil && exports == [.readable, .binary])
        #expect(try draft.composition() == parent && draft.portableSnapshot == captured)
        draft.cancelPendingInsertion()
        let afterCancel = try #require(actions())
        afterCancel.exportBinary()
        #expect(exports == [.readable, .binary, .binary])
        #expect(try draft.composition() == parent && !draft.hasChanges && !draft.canUndo)

        try draft.insert([.init(scene: .voxels(leaf("Incoming castle", glyph: 35)))])
        let pending = try #require(draft.pendingInsertion)
        #expect(actions() == nil)
        #expect(draft.confirmInsertion(id: pending.id))
        let afterConfirm = try #require(actions())
        afterConfirm.exportReadable()
        #expect(exports == [.readable, .binary, .binary, .readable])
        #expect(draft.hasChanges && draft.canUndo)
    }

    @Test func selectedWorldChildrenNameTheirSourceAndRefuseTheWholeNativeBatch() async throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let valid = folder.appendingPathComponent("a-valid-child.3md")
        try SculptureCodec.encode(leaf("Valid child", glyph: 35)).write(to: valid)
        let child = try world()
        let portable = try SculptureThreeMDCodec.capture(.world(child))
        let sources = [
            ("b-sparse-world.3md", try SculptureWorldCodec.encode(child)),
            ("c-sparse-world.3mdb", try SculptureThreeMDCodec.encode(portable, format: .binary(compression: .none))),
        ]
        let parent = try composition()
        let parentSnapshot = try identifiedSnapshot(.composition(parent), prefix: "world-refusal-map")
        let compositionDraft = SculptureCompositionDraft(composition: parent, portableSnapshot: parentSnapshot)
        let worldSnapshot = try identifiedSnapshot(.world(child), prefix: "world-refusal-world")
        let worldDraft = SculptureWorldDraft(world: child, portableSnapshot: worldSnapshot)
        for (filename, bytes) in sources {
            let source = folder.appendingPathComponent(filename)
            try bytes.write(to: source)
            #expect(try SculptureOpenedScene.decode(bytes).scene == .world(child))
            do {
                _ = try SculptureInsertionFiles.read([valid, source])
                Issue.record("A sparse world was accepted as a child model")
            } catch SculptureInsertionError.source(let refusedFilename, let reason) {
                #expect(refusedFilename == filename)
                #expect(reason == SculptureInsertionError.unsupportedChild.localizedDescription)
                #expect(!reason.contains(folder.path))
            }
            compositionDraft.importModels(from: [valid, source])
            await wait { compositionDraft.isPreparing }
            #expect(compositionDraft.error?.hasPrefix(filename + ":") == true)
            #expect(try compositionDraft.composition() == parent && compositionDraft.portableSnapshot == parentSnapshot)
            #expect(
                compositionDraft.pendingInsertion == nil && !compositionDraft.hasChanges && !compositionDraft.canUndo
            )

            worldDraft.importModels(from: [valid, source])
            await wait { worldDraft.isOpeningModel }
            #expect(worldDraft.error?.hasPrefix(filename + ":") == true)
            #expect(try worldDraft.world() == child && worldDraft.portableSnapshot == worldSnapshot)
            #expect(!worldDraft.hasChanges && !worldDraft.canUndo && !worldDraft.canRedo)
        }
    }

    private func leaf(_ title: String, glyph: UInt8, width: Int = 1) throws -> Sculpture {
        try Sculpture(title: title, width: width, height: 1, layers: [Array(repeating: glyph, count: width)])
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

    private func nestedComposition() throws -> SculptureComposition {
        let map = try SculptureTileMap(
            width: 2,
            height: 1,
            layers: [[67, 67]],
            tileSize: .init(width: 1, height: 1, depth: 1),
            bindings: [.init(glyph: 67, modelID: "leaf")]
        )
        return try SculptureComposition(
            title: "Nested child",
            rootID: "root",
            models: [
                "root": .tiles(map), "leaf": .sculpture(leaf("Shared child", glyph: 64)),
                "unused": .sculpture(leaf("Unused", glyph: 42)),
            ]
        )
    }

    private func world() throws -> SculptureWorld {
        try SculptureWorld(title: "Parent world", library: composition(), instances: [])
    }

    private func temporaryDirectory() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("RookInsertion-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return folder
    }

    private func wait(_ isRunning: () -> Bool) async {
        for _ in 0..<100_000 where isRunning() { await Task.yield() }
        #expect(!isRunning())
    }

    private func identifiedSnapshot(_ scene: SculptureScene, prefix: String) throws -> SculptureThreeMDSnapshot {
        let captured = try SculptureThreeMDCodec.capture(scene)
        let graph = try DocumentCompositionCodec.decode(Data(captured.revision.canonicalContent.utf8))
        let entries = graph.entries.map { entry in
            let source = entry.document
            let planes = source.planes.enumerated().map { index, plane in
                var attributes = plane.attributes
                attributes["3md-id"] = "\(prefix)-plane-\(entry.id)-\(index)"
                return Plane(
                    z: plane.z,
                    label: plane.label,
                    x: plane.x,
                    y: plane.y,
                    attributes: attributes,
                    body: plane.body
                )
            }
            let document = Document(
                version: source.version,
                axis: source.axis,
                title: source.title,
                metadata: source.metadata,
                preamble: source.preamble,
                planes: planes
            )
            let references = entry.references.enumerated().map { index, reference in
                var attributes = reference.attributes
                attributes["3md-id"] = "\(prefix)-ref-\(entry.id)-\(index)"
                attributes["opaque"] = "kept-opaque-reference"
                return DocumentReference(targetID: reference.targetID, attributes: attributes)
            }
            return DocumentEntry(id: entry.id, document: document, references: references)
        }
        let custom = try DocumentComposition(rootID: graph.rootID, entries: entries)
        return try SculptureThreeMDCodec.decode(DocumentCompositionCodec.encode(custom))
    }
}
