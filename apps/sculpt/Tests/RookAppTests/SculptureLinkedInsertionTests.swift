import Foundation
import RookSculpture
import Testing

@testable import RookApp

@Suite("Linked roots in insertion and bundles", .serialized)
@MainActor
struct SculptureLinkedInsertionTests {
    // MARK: - Embedded insertion

    @Test func insertingALinkedRootIsRefusedNamingTheFileAndChangesNothing() async throws {
        let project = try LinkedAppProject()
        defer { project.remove() }
        let root = try project.writeStandard()

        do {
            _ = try SculptureInsertionFiles.read([root])
            Issue.record("A linked root was embedded")
        } catch let error as SculptureInsertionError {
            #expect(error.localizedDescription.hasPrefix("main.3md: "))
            #expect(error.localizedDescription.contains("project folder"))
        }

        let parent = try SculptureComposition(
            title: "Parent map",
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
        let draft = SculptureCompositionDraft(composition: parent)
        draft.importModels(from: [root])
        for _ in 0..<2_000_000 where draft.isPreparing { await Task.yield() }
        let message = try #require(draft.error)
        #expect(message.hasPrefix("main.3md: ") && message.contains("project folder"))
        #expect(try draft.composition() == parent && !draft.hasChanges && !draft.canUndo)

        let world = SculptureWorldDraft(world: try SculptureWorld(title: "World", library: parent, instances: []))
        world.importModels(from: [root])
        for _ in 0..<2_000_000 where world.isOpeningModel { await Task.yield() }
        #expect(world.error?.hasPrefix("main.3md: ") == true && world.instances.isEmpty && !world.hasChanges)
    }

    @Test func aModelFolderThatHoldsALinkedRootIsRefusedNamingThatFile() throws {
        let project = try LinkedAppProject()
        defer { project.remove() }
        try project.write("models/oak.3md", LinkedAppProject.voxel("Oak", glyph: 35))
        try project.write("models/room.3md", LinkedAppProject.linked("Room", files: ["A": "oak.3md"]))
        do {
            _ = try SculptureInsertionFiles.readFolder(project.url("models"))
            Issue.record("A folder with a linked root was embedded")
        } catch let error as SculptureInsertionError {
            #expect(error.localizedDescription.hasPrefix("room.3md: "))
        }
    }

    // MARK: - Bundles

    @Test func readableAndBinaryBundlesOpenThroughPlainOpenWithoutAFolder() async throws {
        let project = try LinkedAppProject()
        defer { project.remove() }
        let root = try project.writeStandard()
        let session = try await LinkedAppProject.session(root: root, folder: project.folder)
        let resolution = try #require(session.resolution)

        // The bundles live outside the project and are opened after the project is gone.
        let elsewhere = FileManager.default.temporaryDirectory.appendingPathComponent("RookBundle-\(UUID())")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: elsewhere) }
        var urls: [URL] = []
        for format in SculptureLinkedBundleFormat.allCases {
            let url = elsewhere.appendingPathComponent("bundle-\(format.rawValue).3md")
            try SculptureLinkedBundle.encode(resolution, format: format).write(to: url)
            urls.append(url)
        }
        project.remove()

        for url in urls {
            let opened = try SculptureOpenedScene.read(url)
            #expect(opened.scene == resolution.scene && opened.snapshot != nil)
            guard case .composition(let composition) = opened.scene else {
                Issue.record("A bundle did not open as a composition")
                continue
            }
            // Ordinary Open shows it in the editable composition editor, with no linked session.
            let draft = SculptureCompositionDraft(composition: composition, portableSnapshot: opened.snapshot)
            #expect(!draft.isViewOnly && draft.canInsert && draft.placementCount == 3)
            #expect(draft.library.allSatisfy { $0.path == nil })
        }
    }
}
