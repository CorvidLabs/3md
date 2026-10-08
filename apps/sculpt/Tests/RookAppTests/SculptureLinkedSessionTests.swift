import Foundation
import RookSculpture
import Testing
import ThreeMD

@testable import RookApp

@Suite("Linked sessions", .serialized)
@MainActor
struct SculptureLinkedSessionTests {
    // MARK: - Open

    @Test func plainOpenOfALinkedRootAsksForItsProjectFolder() throws {
        let project = try LinkedAppProject()
        defer { project.remove() }
        let root = try project.writeStandard()
        do {
            _ = try SculptureOpenedScene.read(root)
            Issue.record("A linked root opened without its project folder")
        } catch {
            #expect(SculptureLinkedSession.requiresProjectFolder(error))
            #expect(SculptureLinkedSession.openFailure(error, file: "main.3md") == .requestProjectFolder)
            let message = SculptureLinkedSession.message(for: error, file: root.lastPathComponent)
            #expect(message.hasPrefix("main.3md: ") && message.contains("project folder"))
        }
        let voxel = try project.write("plain.3md", LinkedAppProject.voxel("Plain", glyph: 35))
        #expect(throws: Never.self) { try SculptureOpenedScene.read(voxel) }
        #expect(!SculptureLinkedSession.requiresProjectFolder(SculptureLinkedError.outsideProject))
        #expect(
            SculptureLinkedSession.openFailure(SculptureError.oversizedFile, file: "big.3md")
                == .report(SculpturePortableDiagnostic.message(SculptureError.oversizedFile))
        )
    }

    @Test func aBinaryLinkedRootIsRefusedByNameWithoutAskingForAFolder() throws {
        let project = try LinkedAppProject()
        defer { project.remove() }
        let readable = try LinkedAppProject.linked("Main hall", files: ["A": "oak.3md"])
        let binary = try DocumentStorageCodec.encode(
            DocumentStorageCodec.decode(readable),
            format: .binary(compression: .none)
        )
        let root = try project.write("binary-root.3mdb", binary)
        do {
            _ = try SculptureOpenedScene.read(root)
            Issue.record("A binary linked root opened")
        } catch {
            #expect(!SculptureLinkedSession.requiresProjectFolder(error))
            #expect((error as? SculptureLinkedError) == .binaryLinkedRoot)
            guard case .report(let message) = SculptureLinkedSession.openFailure(error, file: root.lastPathComponent)
            else {
                Issue.record("A binary linked root asked for a folder")
                return
            }
            #expect(message.hasPrefix("binary-root.3mdb: ") && message.contains("readable 3md text"))
        }
    }

    @Test func openingWithItsFolderResolvesNestedChildrenIntoAViewOnlyComposition() async throws {
        let project = try LinkedAppProject()
        defer { project.remove() }
        let root = try project.writeStandard()
        let before = try project.contents()

        let session = try await LinkedAppProject.session(root: root, folder: project.folder)
        #expect(session.rootPath == "scenes/main.3md" && session.repair == nil && session.error == nil)
        let draft = try #require(session.draft)
        #expect(draft.isViewOnly && !draft.hasChanges && !draft.canUndo && !draft.canRedo)
        #expect(draft.title == "Main hall" && draft.placementCount == 3)
        let resolution = try #require(session.resolution)
        #expect(
            resolution.resolvedPaths == [
                "models/rocks/stone.3md", "models/trees/oak.3md", "scenes/main.3md", "scenes/rooms/annex.3md",
            ]
        )
        #expect(Set(resolution.digests.keys) == Set(resolution.resolvedPaths))
        #expect(draft.library.map(\.title).prefix(2) == ["Oak", "Stone"])
        #expect(
            draft.library.map(\.path) == ["models/trees/oak.3md", "models/rocks/stone.3md", "scenes/rooms/annex.3md"]
        )
        #expect(session.notice?.contains("4 linked files") == true)
        #expect(try project.contents() == before, "Opening a linked composition writes nothing.")
    }

    @Test func cancellingTheFolderRequestOrTheResolutionOpensNothing() async throws {
        let project = try LinkedAppProject()
        defer { project.remove() }
        let root = try project.writeStandard()
        guard case .cancelled = await SculptureLinkedSession.open(root: root, folder: nil) else {
            Issue.record("A cancelled folder request opened something")
            return
        }
        let opening = Task { await SculptureLinkedSession.open(root: root, folder: project.folder) }
        opening.cancel()
        guard case .cancelled = await opening.value else {
            Issue.record("A cancelled resolution still opened a session")
            return
        }
    }

    @Test func aRootOutsideTheChosenFolderIsRefusedByNameAndOpensNothing() async throws {
        let project = try LinkedAppProject()
        defer { project.remove() }
        try project.writeStandard()
        let outside = project.container.appendingPathComponent("elsewhere/outside.3md")
        try FileManager.default.createDirectory(
            at: outside.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try LinkedAppProject.linked("Outside", files: ["A": "project/models/trees/oak.3md"]).write(to: outside)
        guard case .refused(let message) = await SculptureLinkedSession.open(root: outside, folder: project.folder)
        else {
            Issue.record("A root outside the folder was not refused")
            return
        }
        #expect(message.hasPrefix("outside.3md: ") && message.contains("not inside the chosen project folder"))
        #expect(!message.contains(project.container.path))
        // The folder itself is not a root inside the folder.
        #expect(throws: SculptureLinkedError.outsideProject) {
            try SculptureProjectFolder(project.folder).projectPath(of: project.folder)
        }
    }

    // MARK: - Reload

    @Test func reloadPicksUpChangedFilesWithoutMarkingTheSessionChanged() async throws {
        let project = try LinkedAppProject()
        defer { project.remove() }
        let root = try project.writeStandard()
        let session = try await LinkedAppProject.session(root: root, folder: project.folder)
        let draft = try #require(session.draft)
        draft.selectCell(SculptureCell(x: 2, y: 0, z: 0))
        let revision = draft.revision
        let digest = session.resolution?.digests["models/trees/oak.3md"]

        try project.write("models/trees/oak.3md", LinkedAppProject.voxel("Grown oak", glyph: 42))
        await session.reload().value
        #expect(session.draft === draft, "Reload updates the shown composition in place.")
        #expect(draft.library.first?.title == "Grown oak" && draft.revision != revision)
        #expect(session.resolution?.digests["models/trees/oak.3md"] != digest)
        #expect(!draft.hasChanges && !draft.canUndo && !draft.canRedo)
        #expect(draft.selectedCell == SculptureCell(x: 2, y: 0, z: 0), "Reload keeps a selection that still exists.")
        #expect(session.error == nil && !session.isResolving)
    }

    @Test func aFailedReloadKeepsThePreviousSceneNamesTheFileAndNeverMarksTheSessionChanged() async throws {
        let project = try LinkedAppProject()
        defer { project.remove() }
        let root = try project.writeStandard()
        let session = try await LinkedAppProject.session(root: root, folder: project.folder)
        let draft = try #require(session.draft)
        let shown = try draft.composition()
        let resolution = session.resolution

        try FileManager.default.removeItem(at: project.url("models/rocks/stone.3md"))
        await session.reload().value
        let message = try #require(session.error)
        #expect(message.contains("models/rocks/stone.3md") && message.contains("scenes/main.3md"))
        #expect(!message.contains(project.container.path))
        #expect(try draft.composition() == shown && session.resolution == resolution)
        #expect(!draft.hasChanges && !draft.canUndo && session.repair == nil)

        // A newer reload makes an older one stale, and a cancelled reload publishes nothing. The status keeps
        // naming the failure rather than falling back to the notice of the last successful resolution.
        try project.write("models/rocks/stone.3md", LinkedAppProject.voxel("Boulder", glyph: 64))
        let notice = session.notice
        let stale = session.reload()
        session.cancel()
        await stale.value
        #expect(!session.isResolving && session.error == message && session.notice == notice)
        #expect(try draft.composition() == shown, "A cancelled reload must not publish its result.")
        let older = session.reload()
        let newer = session.reload()
        await older.value
        await newer.value
        #expect(draft.library.map(\.title).contains("Boulder") && session.error == nil && !draft.hasChanges)
    }

    // MARK: - Repair

    @Test func theRepairViewListsEachFailingLinkWithItsFileAndReasonAndWritesNothing() async throws {
        let project = try LinkedAppProject()
        defer { project.remove() }
        try project.write("models/rocks/stone.3md", LinkedAppProject.voxel("Stone", glyph: 64))
        let compact = try SculptureDocumentCodec.encode(
            Sculpture(title: "Packed", width: 1, height: 1, layers: [[35]]),
            format: .compact
        )
        try project.write("models/packed.3mdb", compact)
        let root = try project.write(
            "scenes/main.3md",
            LinkedAppProject.linked(
                "Main hall",
                files: ["A": "../models/trees/oak.3md", "B": "../models/rocks/stone.3md", "C": "../models/packed.3mdb"]
            )
        )
        let before = try project.contents()

        let session = try await LinkedAppProject.session(root: root, folder: project.folder)
        #expect(session.draft == nil && session.resolution == nil)
        let repair = try #require(session.repair)
        #expect(repair.title == "Main hall" && repair.rootPath == "scenes/main.3md")
        #expect(repair.checkedLinks == 3 && repair.uncheckedLinks == 0)
        #expect(repair.failures.map(\.link) == ["A", "C"])
        #expect(repair.failures.map(\.file) == ["models/trees/oak.3md", "models/packed.3mdb"])
        #expect(repair.failures[0].reason.contains("not in the project folder"))
        #expect(repair.failures[0].reason.contains("scenes/main.3md"))
        #expect(repair.failures[1].reason.contains("compact 3mdb"))
        #expect(repair.failures.allSatisfy { !$0.reason.contains(project.container.path) })
        #expect(try project.contents() == before, "The repair view writes nothing.")

        // Fixing the files and choosing Reload opens the composition.
        try project.write("models/trees/oak.3md", LinkedAppProject.voxel("Oak", glyph: 35))
        try project.write("models/packed.3mdb", LinkedAppProject.voxel("Unpacked", glyph: 35))
        await session.reload().value
        #expect(session.repair == nil && session.draft?.placementCount == 3 && session.draft?.hasChanges == false)
    }

    @Test func theRepairViewOffersChooseFolderAndReloadWheneverNoResolutionRuns() async throws {
        let project = try LinkedAppProject()
        defer { project.remove() }
        let root = try project.write(
            "scenes/main.3md",
            LinkedAppProject.linked("Main hall", files: ["A": "../models/oak.3md"])
        )
        let session = try await LinkedAppProject.session(root: root, folder: project.folder)
        #expect(session.repair != nil && session.draft == nil)
        let idle = SculptureLinkedRepairActions(canChooseFolder: true, canReload: true)
        #expect(SculptureLinkedRepairActions.actions(for: session) == idle)
        let reload = session.reload()
        #expect(
            SculptureLinkedRepairActions.actions(for: session)
                == SculptureLinkedRepairActions(canChooseFolder: false, canReload: false)
        )
        await reload.value
        #expect(SculptureLinkedRepairActions.actions(for: session) == idle && session.repair != nil)
    }

    @Test func aCycleIsListedAsAChainOfProjectPathsForTheLinkThatLeadsToIt() async throws {
        let project = try LinkedAppProject()
        defer { project.remove() }
        try project.write("rooms/a.3md", LinkedAppProject.linked("Room A", files: ["R": "../scenes/main.3md"]))
        let root = try project.write(
            "scenes/main.3md",
            LinkedAppProject.linked("Main hall", files: ["A": "../rooms/a.3md"])
        )
        let session = try await LinkedAppProject.session(root: root, folder: project.folder)
        let repair = try #require(session.repair)
        #expect(repair.failures.count == 1)
        let cycle = try #require(repair.failures.first)
        #expect(cycle.link == "A" && cycle.file == "scenes/main.3md")
        #expect(cycle.reason == "is part of a cycle: scenes/main.3md → rooms/a.3md → scenes/main.3md.")
    }

    @Test func aGlobalFailureIsListedEvenWhenEveryLinkResolvesOnItsOwn() async throws {
        let project = try LinkedAppProject()
        defer { project.remove() }
        // Each link resolves on its own, but together the root reaches one file more than the interim cap.
        let glyphs = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!$")
        #expect(glyphs.count == SculptureLinkedResolver.maximumFiles)
        var files: [Character: String] = [:]
        for (index, glyph) in glyphs.enumerated() {
            let path = String(format: "models/m%02d.3md", index)
            try project.write(path, LinkedAppProject.voxel("Model \(index)", glyph: 35))
            files[glyph] = "../" + path
        }
        let root = try project.write("scenes/main.3md", LinkedAppProject.linked("Crowded hall", files: files))
        let session = try await LinkedAppProject.session(root: root, folder: project.folder)
        let repair = try #require(session.repair)
        #expect(repair.checkedLinks == SculptureLinkedRepair.maximumProbes && repair.uncheckedLinks == 0)
        #expect(repair.failures.count == 1)
        let failure = try #require(repair.failures.first)
        #expect(failure.link == nil && failure.file.hasPrefix("models/m"))
        #expect(failure.reason == "reaches the linked composition limit of 64 linked files.")
    }

    @Test func anUnreadableRootOpensTheRepairViewNamingTheRoot() async throws {
        let project = try LinkedAppProject()
        defer { project.remove() }
        let root = try project.writeStandard()
        let session = try await LinkedAppProject.session(root: root, folder: project.folder)
        #expect(session.draft != nil)
        // The same root replaced by something that is not a linked composition fails at the next open.
        try project.write("scenes/main.3md", LinkedAppProject.voxel("Not linked", glyph: 35))
        let reopened = try await LinkedAppProject.session(root: root, folder: project.folder)
        let repair = try #require(reopened.repair)
        #expect(repair.title == "main.3md" && repair.failures.map(\.file) == ["scenes/main.3md"])
        #expect(repair.failures[0].reason.contains("not a linked composition"))
    }

    @Test func chooseFolderRegrantsOnlyAFolderThatContainsTheRoot() async throws {
        let project = try LinkedAppProject()
        defer { project.remove() }
        let root = try project.write(
            "scenes/main.3md",
            LinkedAppProject.linked("Main hall", files: ["A": "../models/oak.3md"])
        )
        let session = try await LinkedAppProject.session(root: root, folder: project.folder)
        let repair = try #require(session.repair)

        let unrelated = project.container.appendingPathComponent("unrelated")
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        session.chooseFolder(unrelated)
        #expect(session.error?.contains("not inside the chosen project folder") == true)
        #expect(session.folder == SculptureProjectFolder(project.folder) && session.repair == repair)
        #expect(!session.isResolving)
        // A reload that fails again replaces the refusal with its repair list.
        await session.reload().value
        #expect(session.error == nil && session.repair == repair)

        try project.write("models/oak.3md", LinkedAppProject.voxel("Oak", glyph: 35))
        session.chooseFolder(project.container)
        await LinkedAppProject.settle(session)
        #expect(session.rootPath == "project/scenes/main.3md" && session.error == nil)
        #expect(session.repair == nil && session.draft?.library.first?.path == "project/models/oak.3md")
    }

    // MARK: - View-only session

    @Test func aLinkedSessionIsViewOnlyAndEveryEditingActionIsUnavailable() async throws {
        let project = try LinkedAppProject()
        defer { project.remove() }
        let root = try project.writeStandard()
        let session = try await LinkedAppProject.session(root: root, folder: project.folder)
        let draft = try #require(session.draft)
        let shown = try draft.composition()

        // Painting, map edits, rotation and the title.
        #expect(draft.brush == .select)
        draft.brush = .erase
        draft.paint(SculptureCell(x: 0, y: 0, z: 0))
        draft.brush = .place
        draft.paint(SculptureCell(x: 1, y: 0, z: 0))
        #expect(draft.selectedCell == SculptureCell(x: 1, y: 0, z: 0), "Selecting a tile still works.")
        draft.resize(width: 4, height: 1, depth: 1)
        draft.setTileSize(width: 2, height: 2, depth: 2)
        draft.rotateSelected(1)
        draft.setTitle("Renamed")
        draft.addExample(try #require(SculptureExamples.compositionStarters.first))
        draft.replace(with: try SculptureCompositionExamples.courtyard())
        draft.undo()
        #expect(try draft.composition() == shown && !draft.hasChanges && !draft.canUndo)

        // Insertion, shared-model edits, editable voxels and world handoff.
        #expect(!draft.canInsert && SculptureInsertionActions.actions(for: draft) == nil)
        draft.requestInsertion(.files)
        #expect(draft.insertionRequest == nil)
        #expect(throws: (any Error).self) {
            try draft.insert([.init(scene: .voxels(Sculpture(title: "Leaf", width: 1, height: 1, layers: [[35]])))])
        }
        let explanation = SculptureCompositionDraft.viewOnlyExplanation
        draft.importModels(from: [project.url("models/trees/oak.3md")])
        #expect(!draft.isPreparing && draft.error == explanation)
        let modelID = try #require(draft.editableModels.first?.id)
        draft.report(SculptureError.oversizedFile)
        draft.beginSharedEdit(modelID: modelID)
        #expect(draft.sharedEdit == nil && draft.error == explanation)
        var opened = false
        draft.report(SculptureError.oversizedFile)
        draft.prepare { _, _ in opened = true }
        #expect(!draft.isPreparing && !opened && draft.error == explanation)
        #expect(!draft.canUseInWorld)
        var handedOff = false
        draft.report(SculptureError.oversizedFile)
        draft.prepareWorldHandoff { _ in handedOff = true }
        #expect(!draft.isPreparing && !handedOff && draft.error == explanation)
        #expect(try draft.composition() == shown && !draft.hasChanges)

        // The header label and the help of Save, Open editable voxels and Use in a world read this explanation.
        #expect(draft.viewOnlyNotice == explanation)
        #expect(SculptureCompositionDraft().viewOnlyNotice == nil, "An ordinary composition carries no explanation.")

        // Menus: no insertion, Undo, Redo, portable export or document action; Reload is offered.
        let sheet = SculptureSheetContext.linked(session)
        let idle = SculptureEditorActivity()
        #expect(SculptureEditorCommandAvailability.insertionActions(sheet: sheet, activity: idle) == nil)
        let history = try #require(SculptureEditorCommandAvailability.sheetHistory(sheet: sheet, activity: idle))
        #expect(!history.canUndo && !history.canRedo)
        let draftHistory = SculptureHistoryActions.actions(for: draft)
        #expect(!draftHistory.canUndo && !draftHistory.canRedo)
        #expect(!SculptureEditorCommandAvailability.documentActionsAvailable(sheet: sheet, activity: idle))
        #expect(SculptureEditor.portableActions(for: draft, exportReadable: {}, exportBinary: {}) == nil)
        let reload = try #require(SculptureEditorCommandAvailability.linkedActions(sheet: sheet, activity: idle))
        #expect(
            SculptureEditorCommandAvailability.linkedActions(
                sheet: sheet,
                activity: SculptureEditorActivity(isExporting: true)
            ) == nil
        )
        #expect(
            SculptureEditorCommandAvailability.linkedActions(sheet: .composition(draft), activity: idle) == nil
        )
        reload.reload()
        #expect(session.isResolving && SculptureLinkedActions.actions(for: session) == nil)
        await LinkedAppProject.settle(session)
        #expect(SculptureLinkedActions.actions(for: session) != nil && !draft.hasChanges)

        // A preview only assembles the map.
        draft.prepare()
        for _ in 0..<2_000_000 where draft.isPreparing { await Task.yield() }
        #expect(try draft.preview != nil && draft.composition() == shown && !draft.hasChanges)
    }

    @Test func aRepairSessionOffersReloadButNoEditingCommands() async throws {
        let project = try LinkedAppProject()
        defer { project.remove() }
        let root = try project.write(
            "scenes/main.3md",
            LinkedAppProject.linked("Main hall", files: ["A": "missing.3md"])
        )
        let session = try await LinkedAppProject.session(root: root, folder: project.folder)
        #expect(session.repair != nil)
        let sheet = SculptureSheetContext.linked(session)
        let idle = SculptureEditorActivity()
        #expect(SculptureEditorCommandAvailability.insertionActions(sheet: sheet, activity: idle) == nil)
        #expect(SculptureEditorCommandAvailability.sheetHistory(sheet: sheet, activity: idle)?.canUndo == false)
        #expect(SculptureEditorCommandAvailability.linkedActions(sheet: sheet, activity: idle) != nil)
    }
}
