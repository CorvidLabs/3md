import Foundation
import RookSculpture
import Testing
import ThreeMD

@testable import RookApp

@Suite("Portable native scene interchange", .serialized)
@MainActor
struct SculpturePortableInterchangeTests {
    @Test func copyPreparationKeepsTheNativeWorkspaceAndReferenceBaseline() async throws {
        let scene = try composition()
        let draft = SculptureCompositionDraft(composition: scene)
        draft.setTitle("Unsaved title")
        let current = try draft.composition()
        let session = try SculptureReferenceSaveSession(draft: .composition(draft))
        let generation = UUID()
        let job = SculpturePortableSaveJob()
        job.start(.composition(current), format: .binary, documentGeneration: generation)
        await wait(job)
        let prepared = try #require(job.result)
        #expect(prepared.documentGeneration == generation)
        #expect(try SculptureThreeMDCodec.decode(prepared.data).scene == .composition(current))
        draft.retainPortableSnapshot(prepared.snapshot)
        #expect(draft.hasChanges && draft.canUndo)
        _ = session.finish(written: false)
        #expect(draft.hasChanges && draft.canUndo)
        draft.undo()
        #expect(try draft.composition() == scene && !draft.hasChanges)
    }

    @Test func voxelCopyLeavesTheSavedBaselineUndoAndNativeSaveMessageAlone() async throws {
        let leaf = try Sculpture(title: "Native voxel", width: 1, height: 1, layers: [[35]])
        let workspace = SculptureWorkspace()
        workspace.replace(with: leaf, opened: true)
        workspace.execute(.paint(x: 0, y: 0, z: 0, glyph: "@"))
        let current = workspace.sculpture
        let message = workspace.message
        let generation = workspace.documentGeneration
        let job = SculpturePortableSaveJob()
        job.start(.voxels(current), format: .binary, documentGeneration: generation)
        await wait(job)
        let prepared = try #require(job.result)
        #expect(prepared.scene == .voxels(current))
        #expect(workspace.isDirty && workspace.canUndo && workspace.message == message)
        #expect(workspace.documentGeneration == generation)
        workspace.undo()
        #expect(workspace.sculpture == leaf && !workspace.isDirty)
        workspace.redo()
        #expect(workspace.sculpture == current && workspace.isDirty)
    }

    @Test func regularFileOpenReopensAnAdoptedGenericBinaryAsReadablePortableText() throws {
        let leaf = try Sculpture(title: "Legacy source", width: 1, height: 1, layers: [[35]])
        let document = try Parser().parse(String(decoding: SculptureCodec.encode(leaf), as: UTF8.self))
        let binary = try DocumentStorageCodec.encode(document, format: .binary(compression: .none))
        let opened = try SculptureOpenedScene.decode(binary)
        let captured = try #require(opened.snapshot)
        let text = try SculpturePortableFormat.readable.encode(captured)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("RookPortableOpen-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("copy.3md")
        try text.write(to: file)
        #expect(try SculptureOpenedScene.read(file).snapshot == captured)
        #expect(throws: (any Error).self) { try SculptureOpenedScene.read(folder) }
        #expect(throws: (any Error).self) {
            try SculptureOpenedScene.read(folder.appendingPathComponent("missing.3md"))
        }
        #expect(!document.metadata.keys.contains("sculpt-storage"))
    }

    @Test func cancellationAndSupersessionDoNotPublishStaleCopies() async throws {
        let scene = SculptureScene.composition(try composition())
        let job = SculpturePortableSaveJob()
        job.start(scene, format: .readable, documentGeneration: UUID())
        job.cancel()
        for _ in 0..<100 { await Task.yield() }
        #expect(job.result == nil && job.error == nil && !job.isRunning)
        let generation = UUID()
        job.start(scene, format: .binary, documentGeneration: generation)
        job.start(scene, format: .readable, documentGeneration: generation)
        await wait(job)
        let prepared = try #require(job.result)
        #expect(prepared.format == .readable && prepared.documentGeneration == generation)
        #expect(try SculptureOpenedScene.decode(prepared.data).snapshot == prepared.snapshot)
    }

    @Test func contentOpenRoutesAllPortableScenesAndKeepsLegacyDecoding() throws {
        let graph = try composition()
        let world = try world(graph)
        let leaf = try #require(
            {
                if case .sculpture(let value) = graph.models["leaf"] { return value }; return nil
            }()
        )
        for scene in [SculptureScene.voxels(leaf), .composition(graph), .world(world)] {
            let captured = try SculptureThreeMDCodec.capture(scene)
            for format in [SculpturePortableFormat.readable, .binary] {
                let opened = try SculptureOpenedScene.decode(format.encode(captured))
                #expect(opened.scene == scene && opened.snapshot == captured)
            }
        }
        let legacy = try SculptureOpenedScene.decode(SculptureCompositionCodec.encode(graph))
        #expect(legacy.scene == .composition(graph) && legacy.snapshot == nil)
        let malformed = Data("---\nprofile: 3md-composition-1\n---\nnot a composition".utf8)
        #expect(SculptureThreeMDCodec.isPortable(malformed))
        #expect(throws: (any Error).self) { try SculptureOpenedScene.decode(malformed) }
    }

    @Test func sharedApplyAndUndoRetainOriginalIdentitiesAndExactRevisions() async throws {
        let captured = try customSnapshot(.composition(composition()))
        guard case .composition(let scene) = captured.scene else { return }
        let draft = SculptureCompositionDraft(composition: scene, portableSnapshot: captured)
        draft.beginSharedEdit(modelID: "leaf")
        let session = try #require(draft.sharedEdit)
        session.workspace.execute(.paint(x: 0, y: 0, z: 0, glyph: "@"))
        #expect(await draft.applySharedEdit())
        let edited = try #require(draft.portableSnapshot)
        #expect(edited.revision != captured.revision && draft.editingNotice == nil)
        #expect(edited.revision.canonicalContent.contains("custom-leaf-0"))
        #expect(edited.revision.canonicalContent.contains("custom-ref-root-0"))
        draft.undo()
        #expect(draft.portableSnapshot == captured && !draft.hasChanges)
        draft.redo()
        #expect(draft.portableSnapshot == edited && draft.hasChanges)
    }

    @Test func worldApplyRetainsExactAnchorsAndSnapshotUndo() async throws {
        let captured = try customSnapshot(.world(world(composition())))
        guard case .world(let scene) = captured.scene else { return }
        let draft = SculptureWorldDraft(world: scene, portableSnapshot: captured)
        draft.beginSharedEdit(modelID: "leaf")
        let session = try #require(draft.sharedEdit)
        session.workspace.execute(.paint(x: 0, y: 0, z: 0, glyph: "@"))
        #expect(await draft.applySharedEdit())
        let edited = try #require(draft.portableSnapshot)
        #expect(try draft.world().instances == scene.instances)
        draft.undo()
        #expect(draft.portableSnapshot == captured && !draft.hasChanges)
        draft.redo()
        #expect(draft.portableSnapshot == edited && draft.hasChanges)
    }

    @Test func staleNativeParentDoesNotPublishAnyPortableSnapshot() async throws {
        let captured = try customSnapshot(.composition(composition()))
        guard case .composition(let scene) = captured.scene else { return }
        let draft = SculptureCompositionDraft(composition: scene, portableSnapshot: captured)
        draft.beginSharedEdit(modelID: "leaf")
        let session = try #require(draft.sharedEdit)
        session.workspace.execute(.paint(x: 0, y: 0, z: 0, glyph: "@"))
        draft.setTitle("Newer parent")
        let newer = try draft.composition()
        #expect(!(await draft.applySharedEdit()))
        #expect(draft.portableSnapshot == captured)
        #expect(try draft.composition() == newer)
        #expect(session.error != nil)
    }

    @Test func onlyCapacityFailuresUseTheLegacyNativeEditingFallback() throws {
        let large = try Sculpture(
            title: "Large leaf",
            width: 256,
            height: 256,
            layers: Array(repeating: Array(repeating: UInt8(35), count: 65_536), count: 256)
        )
        let map = try SculptureTileMap(
            width: 1,
            height: 1,
            layers: [[65]],
            tileSize: .init(width: 256, height: 256, depth: 256),
            bindings: [.init(glyph: 65, modelID: "large")]
        )
        let scene = try SculptureComposition(
            title: "Legacy capacity",
            rootID: "root",
            models: ["root": .tiles(map), "large": .sculpture(large)]
        )
        var replacement = large
        try replacement.rename("Renamed large leaf")
        let result = try SculpturePortableModelEditing.replace(
            scene: .composition(scene),
            preserving: nil,
            modelID: "large",
            expected: large,
            replacement: replacement
        )
        #expect(result.usedLegacyCapacityFallback && result.snapshot == nil)
        guard case .composition(let edited) = result.scene else { Issue.record("Expected composition"); return }
        #expect(edited.models["large"] == .sculpture(replacement))
        #expect(edited.models["root"] == scene.models["root"])
        #expect(throws: (any Error).self) {
            try SculpturePortableModelEditing.replace(
                scene: .composition(scene),
                preserving: nil,
                modelID: "large",
                expected: replacement,
                replacement: large
            )
        }
    }

    @Test func diagnosticPresentationKeepsCodesPathsAndRealSourceLines() {
        let failure = DocumentEditError(
            .init(code: .staleRevision, message: "Changed", sourceLine: 4, path: "expectedRevision")
        )
        #expect(SculpturePortableDiagnostic.message(failure) == "staleRevision at expectedRevision (line 4): Changed")
        #expect(
            SculpturePortableDiagnostic.message(DocumentStorageError.oversizedOutput).contains(
                "Save in its existing Sculpt format"
            )
        )
    }

    private func wait(_ job: SculpturePortableSaveJob) async {
        for _ in 0..<100_000 where job.isRunning { await Task.yield() }
        #expect(!job.isRunning)
    }

    private func composition() throws -> SculptureComposition {
        let leaf = try Sculpture(title: "Leaf", width: 1, height: 1, layers: [[35]])
        let map = try SculptureTileMap(
            width: 2,
            height: 1,
            layers: [[65, 65]],
            tileSize: .init(width: 1, height: 1, depth: 1),
            bindings: [.init(glyph: 65, modelID: "leaf")]
        )
        return try SculptureComposition(
            title: "Shared scene",
            rootID: "root",
            models: ["root": .tiles(map), "leaf": .sculpture(leaf)]
        )
    }

    private func world(_ graph: SculptureComposition) throws -> SculptureWorld {
        try SculptureWorld(
            title: "Exact world",
            library: graph,
            instances: [
                .init(
                    id: "first",
                    modelID: "leaf",
                    origin: .init(x: Int64.min, y: 9_007_199_254_740_993, z: Int64.max - 256)
                ),
                .init(id: "second", modelID: "leaf", origin: .init(x: 0, y: 0, z: 0)),
            ]
        )
    }

    private func customSnapshot(_ scene: SculptureScene) throws -> SculptureThreeMDSnapshot {
        let captured = try SculptureThreeMDCodec.capture(scene)
        let graph = try DocumentCompositionCodec.decode(Data(captured.revision.canonicalContent.utf8))
        let entries = graph.entries.map { entry in
            let source = entry.document
            let planes = source.planes.enumerated().map { index, plane in
                var attributes = plane.attributes
                attributes["3md-id"] = "custom-\(entry.id)-\(index)"
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
                attributes["3md-id"] = "custom-ref-\(entry.id)-\(index)"
                return DocumentReference(targetID: reference.targetID, attributes: attributes)
            }
            return DocumentEntry(id: entry.id, document: document, references: references)
        }
        let custom = try DocumentComposition(rootID: graph.rootID, entries: entries)
        return try SculptureThreeMDCodec.decode(DocumentCompositionCodec.encode(custom))
    }
}
