import Foundation
import RookSculpture
import Testing

@testable import RookApp

@Suite("Reference save session lifecycle", .serialized)
@MainActor
struct SculptureReferenceSaveSessionTests {
    @Test func compositionSuccessfulSaveRetainsExactDraftSelectionAndGraphHistory() async throws {
        let original = try composition()
        let draft = SculptureCompositionDraft(composition: original)
        draft.select(65)
        draft.brush = .erase
        draft.paint(.init(x: 1, y: 0, z: 0))
        let saved = try draft.composition()
        let cell = draft.selectedCell
        let revision = draft.revision
        let session = try SculptureReferenceSaveSession(draft: .composition(draft))
        let job = SculptureGraphSaveJob()
        job.start(session.document)
        try await settle(job)
        let prepared = try #require(job.result)
        let url = try write(prepared)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(try SculptureCompositionCodec.decode(Data(contentsOf: url)) == saved)
        let restored = session.finish(written: true)
        guard case .composition(let retained) = restored else { Issue.record("Wrong restored document kind"); return }
        #expect(retained === draft)
        #expect(retained.selectedCell == cell && retained.selectedGlyph == 65 && retained.brush == .erase)
        #expect(retained.revision == revision && !retained.hasChanges && retained.canUndo)
        retained.undo()
        #expect(try retained.composition() == original && retained.hasChanges)
        retained.redo()
        #expect(try retained.composition() == saved && !retained.hasChanges)
    }

    @Test func worldSuccessfulSaveRetainsLibraryHistoryFocusCameraAndSelectedInstance() async throws {
        let original = try world()
        let draft = SculptureWorldDraft(world: original)
        draft.selectInstance("second")
        draft.jumpToSelected()
        draft.setRenderDistance(1024)
        draft.setDetailDistance(512)
        draft.beginSharedEdit(modelID: "leaf")
        let edit = try #require(draft.sharedEdit)
        edit.workspace.execute(.paint(x: 0, y: 0, z: 0, glyph: "@"))
        #expect(await draft.applySharedEdit())
        let saved = try draft.world()
        let camera = draft.camera
        let focus = draft.focus
        let scene = draft.sceneRevision
        let session = try SculptureReferenceSaveSession(draft: .world(draft))
        let job = SculptureGraphSaveJob()
        job.start(session.document)
        try await settle(job)
        let url = try write(#require(job.result))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(try SculptureWorldCodec.decode(Data(contentsOf: url)) == saved)
        guard case .world(let retained) = session.finish(written: true) else {
            Issue.record("Wrong restored document kind"); return
        }
        #expect(retained === draft && retained.selectedInstanceID == "second")
        #expect(retained.camera == camera && retained.focus == focus && retained.sceneRevision == scene)
        #expect(retained.renderDistance == 1024 && retained.detailDistance == 512)
        #expect(!retained.hasChanges && retained.canUndo)
        retained.undo()
        #expect(try retained.world() == original && retained.hasChanges)
        retained.redo()
        #expect(try retained.world() == saved && !retained.hasChanges)
    }

    @Test func panelCancellationAndWriteFailureKeepSameDraftBaselineAndHistory() async throws {
        let original = try composition()
        let draft = SculptureCompositionDraft(composition: original)
        draft.setTitle("Unsaved title")
        let current = try draft.composition()
        let session = try SculptureReferenceSaveSession(draft: .composition(draft))
        let job = SculptureGraphSaveJob()
        job.start(session.document)
        try await settle(job)
        let prepared = try #require(job.result)
        let missingParent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = missingParent.appendingPathComponent("failed.3md")
        #expect(throws: (any Error).self) { try prepared.data.write(to: file, options: .atomic) }
        guard case .composition(let restored) = session.finish(written: false) else {
            Issue.record("Wrong restored document kind"); return
        }
        #expect(restored === draft && restored.hasChanges && restored.canUndo)
        #expect(try restored.composition() == current)
        restored.undo()
        #expect(try restored.composition() == original && !restored.hasChanges)
        restored.redo()
        let cancelled = try SculptureReferenceSaveSession(draft: .composition(restored))
        job.start(cancelled.document)
        job.cancel()
        _ = cancelled.finish(written: false)
        _ = cancelled.finish(written: true)
        #expect(restored.hasChanges && restored.canUndo)
        #expect(job.result == nil && !job.isRunning)
        restored.undo()
        #expect(try restored.composition() == original && !restored.hasChanges)
    }

    @Test func saveOnlyMarksCapturedSnapshotAndLeavesLaterEditsDirty() async throws {
        let draft = SculptureWorldDraft(world: try world())
        draft.setTitle("Captured title")
        let captured = try draft.world()
        let session = try SculptureReferenceSaveSession(draft: .world(draft))
        let job = SculptureGraphSaveJob()
        job.start(session.document)
        draft.setTitle("Newer title")
        try await settle(job)
        #expect(job.result?.document == .world(captured))
        let url = try write(#require(job.result))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(try SculptureWorldCodec.decode(Data(contentsOf: url)) == captured)
        _ = session.finish(written: true)
        #expect(draft.hasChanges && draft.title == "Newer title")
        draft.undo()
        #expect(try draft.world() == captured && !draft.hasChanges)
        draft.redo()
        #expect(draft.hasChanges && draft.title == "Newer title")
    }

    @Test func preparationFailureRetainsDraftAndCaptureFailureDoesNotDismissIt() async throws {
        let leaf = try Sculpture(
            title: "Large leaf",
            width: 128,
            height: 128,
            layers: Array(repeating: Array(repeating: 35, count: 128 * 128), count: 64)
        )
        var models: [String: SculptureCompositionModel] = [:]
        for index in 0..<21 { models["leaf-\(index)"] = .sculpture(leaf) }
        models["root"] = .tiles(
            try SculptureTileMap(
                width: 1,
                height: 1,
                layers: [[65]],
                tileSize: .init(width: 128, height: 128, depth: 64),
                bindings: [SculptureModelBinding(glyph: 65, modelID: "leaf-0")]
            )
        )
        let original = try SculptureComposition(title: "Oversized readable", rootID: "root", models: models)
        let draft = SculptureCompositionDraft(composition: original)
        draft.setTitle("New oversized title")
        let session = try SculptureReferenceSaveSession(draft: .composition(draft))
        let job = SculptureGraphSaveJob()
        job.start(session.document)
        try await settle(job)
        #expect(job.result == nil && job.error?.contains("20 MiB") == true)
        guard case .composition(let retained) = session.finish(written: false) else {
            Issue.record("Wrong restored document kind"); return
        }
        #expect(retained === draft && retained.hasChanges && retained.canUndo)
        retained.undo()
        #expect(try retained.composition() == original && !retained.hasChanges)
        retained.setTitle("")
        #expect(throws: SculptureCompositionError.invalidTitle) {
            try SculptureReferenceSaveSession(draft: .composition(retained))
        }
        #expect(retained.title.isEmpty && retained.hasChanges && retained.canUndo)
    }

    private func settle(_ job: SculptureGraphSaveJob) async throws {
        for _ in 0..<1_000 where job.isRunning { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!job.isRunning)
    }

    private func write(_ prepared: SculpturePreparedGraph) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("saved.3md")
        try prepared.data.write(to: url, options: .atomic)
        return url
    }

    private func composition() throws -> SculptureComposition {
        try SculptureComposition(
            title: "Shared source",
            rootID: "root",
            models: [
                "leaf": .sculpture(Sculpture(title: "Leaf", width: 1, height: 1, layers: [[35]])),
                "root": .tiles(
                    SculptureTileMap(
                        width: 2,
                        height: 1,
                        layers: [[65, 65]],
                        tileSize: .init(width: 1, height: 1, depth: 1),
                        bindings: [SculptureModelBinding(glyph: 65, modelID: "leaf")]
                    )
                ),
            ]
        )
    }

    private func world() throws -> SculptureWorld {
        try SculptureWorld(
            title: "Shared world",
            library: composition(),
            instances: [
                SculptureWorldInstance(id: "first", modelID: "leaf", origin: .init(x: 0, y: 0, z: 0)),
                SculptureWorldInstance(id: "second", modelID: "leaf", origin: .init(x: 100, y: 0, z: 0)),
            ]
        )
    }
}
