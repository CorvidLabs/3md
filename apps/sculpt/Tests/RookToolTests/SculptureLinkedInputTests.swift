import Foundation
import RookSculpture
import Testing
import ThreeMD

@testable import RookTool

/// A folder holding a linked root, the voxel file it links, a binary copy of the root and native parents.
private struct LinkedInputFixture {
    let folder: URL
    let leaf: Sculpture
    let parent: SculptureComposition

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("RookLinkedInput-\(UUID())")
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("models"),
            withIntermediateDirectories: true
        )
        leaf = try Sculpture(title: "Leaf", width: 1, height: 1, layers: [[35]])
        let map = try SculptureTileMap(
            width: 2,
            height: 1,
            layers: [[65, 46]],
            tileSize: .init(width: 1, height: 1, depth: 1),
            bindings: [try .init(glyph: 65, modelID: "leaf")]
        )
        parent = try SculptureComposition(
            title: "Native parent",
            rootID: "root",
            models: ["root": .tiles(map), "leaf": .sculpture(leaf)]
        )
        // The linked file exists, so only the refusal to follow links keeps these commands from reading it.
        try write(SculptureCodec.encode(leaf), "models/leaf.3md")
        let root = try SculptureLinkedComposition(
            title: "Linked room",
            width: 1,
            height: 1,
            tileSize: .init(width: 1, height: 1, depth: 1),
            layers: [[76]],
            files: [76: "models/leaf.3md"]
        )
        let linked = try SculptureLinkedCodec.encode(root)
        try write(linked, "scene.3md")
        try write(
            DocumentStorageCodec.encode(DocumentStorageCodec.decode(linked), format: .binary(compression: .none)),
            "binary-scene.3mdb"
        )
        try write(SculptureCompositionCodec.encode(parent), "parent.3md")
        let batch = try JSONEncoder().encode(
            SculptureCommandBatch(commands: [.paint(x: 0, y: 0, z: 0, glyph: "@")])
        )
        try write(batch, "batch.json")
    }

    func file(_ name: String) -> URL { folder.appendingPathComponent(name) }
    func path(_ name: String) -> String { file(name).standardizedFileURL.path }
    func clean() { try? FileManager.default.removeItem(at: folder) }
    func write(_ data: Data, _ name: String) throws { try data.write(to: file(name)) }
    func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: file(name).path) }

    /// Every file in the folder with its bytes, to show that refusals change nothing and publish nothing.
    func contents() throws -> [String: Data] {
        var contents: [String: Data] = [:]
        for name in try FileManager.default.subpathsOfDirectory(atPath: folder.path) {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: file(name).path, isDirectory: &isDirectory) else { continue }
            if !isDirectory.boolValue { contents[name] = try Data(contentsOf: file(name)) }
        }
        return contents
    }

    func command(_ arguments: [String]) throws -> Data {
        try SculptureCommandTool.run(arguments: arguments, workingDirectory: folder)
    }

    func portable(_ arguments: [String]) throws -> Data {
        try SculpturePortableTool.run(arguments: arguments, workingDirectory: folder)
    }

    func reference(_ arguments: [String]) throws -> Data {
        try SculptureReferenceModelTool.run(arguments: arguments, workingDirectory: folder)
    }

    func request(_ fields: [String: Any], _ name: String) throws {
        try write(JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]), name)
    }

    func message(_ operation: () throws -> Data) -> String {
        do {
            _ = try operation()
            return ""
        } catch { return error.localizedDescription }
    }
}

@Suite("Linked composition inputs to explicit-file commands", .serialized)
struct SculptureLinkedInputTests {
    @Test func everyCommandThatReadsAScenePathRefusesALinkedRootNamingItAndItsProjectFolder() throws {
        let fixture = try LinkedInputFixture()
        defer { fixture.clean() }
        let batch = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.file("batch.json")))
        try fixture.request(
            ["version": 1, "modelID": "leaf", "expectedScene": "scene.3md", "batch": batch],
            "portable-apply.json"
        )
        try fixture.request(
            ["version": 1, "action": "editModel", "modelID": "leaf", "expectedModel": "scene.3md", "batch": batch],
            "reference-apply.json"
        )
        try fixture.request(
            ["version": 1, "files": ["scene.3md"], "cell": ["x": 1, "y": 0, "z": 0], "expectedScene": "parent.3md"],
            "portable-insert.json"
        )
        try fixture.request(
            ["version": 1, "files": ["scene.3md"], "cell": ["x": 1, "y": 0, "z": 0]],
            "reference-insert.json"
        )
        try fixture.request(
            [
                "version": 1, "title": "Imports a linked root", "width": 1, "height": 1,
                "tileWidth": 1, "tileHeight": 1, "tileDepth": 1, "layers": [["S"]],
                "bindings": [["glyph": "S", "model": "scene", "quarterTurns": 0]],
                "models": [["id": "scene", "path": "scene.3md"]],
            ],
            "manifest.json"
        )
        let before = try fixture.contents()
        let absolute = SculptureLinkedInputError.needsProjectFolder(fixture.path("scene.3md"))
        let relative = SculptureLinkedInputError.needsProjectFolder("scene.3md")
        let refusals: [(String, SculptureLinkedInputError, () throws -> Data)] = [
            ("sculpture inspect", absolute, { try fixture.command(["inspect", "scene.3md"]) }),
            ("sculpture apply", absolute, { try fixture.command(["apply", "scene.3md", "batch.json", "out.3md"]) }),
            ("sculpture expand", absolute, { try fixture.command(["expand", "scene.3md", "out.3md"]) }),
            ("sculpture model", absolute, { try fixture.command(["model", "scene.3md", "leaf", "out.3md"]) }),
            ("portable inspect", absolute, { try fixture.portable(["inspect", "scene.3md"]) }),
            ("portable export", absolute, { try fixture.portable(["export", "scene.3md", "out.3md"]) }),
            (
                "portable apply input", absolute,
                { try fixture.portable(["apply", "scene.3md", "portable-apply.json", "out.3md"]) }
            ),
            (
                "portable apply expectedScene", absolute,
                { try fixture.portable(["apply", "parent.3md", "portable-apply.json", "out.3md"]) }
            ),
            (
                "portable insert input", relative,
                { try fixture.portable(["insert", "scene.3md", "portable-insert.json", "out.3md"]) }
            ),
            (
                "portable insert child", relative,
                { try fixture.portable(["insert", "parent.3md", "portable-insert.json", "out.3md"]) }
            ),
            ("reference inspect", absolute, { try fixture.reference(["inspect", "scene.3md"]) }),
            (
                "reference apply input", absolute,
                { try fixture.reference(["apply", "scene.3md", "reference-apply.json", "out.3md"]) }
            ),
            (
                "reference apply expectedModel", absolute,
                { try fixture.reference(["apply", "parent.3md", "reference-apply.json", "out.3md"]) }
            ),
            (
                "reference insert input", relative,
                { try fixture.reference(["insert", "scene.3md", "reference-insert.json", "out.3md"]) }
            ),
            (
                "reference insert child", relative,
                { try fixture.reference(["insert", "parent.3md", "reference-insert.json", "out.3md"]) }
            ),
        ]
        for (name, expected, operation) in refusals {
            #expect(throws: expected, "\(name)") { _ = try operation() }
            #expect(!fixture.exists("out.3md"), "\(name)")
        }
        let composed = fixture.message { try fixture.command(["compose", "manifest.json", "out.3md"]) }
        #expect(composed.hasPrefix("Invalid composition manifest \(fixture.path("manifest.json")): "))
        #expect(composed.hasSuffix(absolute.localizedDescription))
        #expect(!fixture.exists("out.3md"))
        #expect(try fixture.contents() == before)
        let description = try #require(absolute.errorDescription)
        #expect(description.hasPrefix("\(fixture.path("scene.3md")) is a linked composition"))
        #expect(description.contains("needs its project folder"))
        #expect(description.contains("Open it in Sculpt.3md and choose that folder."))
        #expect(description.contains("does not read linked files"))
    }

    @Test func aBinaryLinkedRootIsRefusedByNameWithTheSharedExplanation() throws {
        let fixture = try LinkedInputFixture()
        defer { fixture.clean() }
        try fixture.request(
            ["version": 1, "files": ["models/leaf.3md"], "cell": ["x": 1, "y": 0, "z": 0]],
            "reference-insert.json"
        )
        let before = try fixture.contents()
        let absolute = SculptureLinkedInputError.binaryLinkedRoot(fixture.path("binary-scene.3mdb"))
        let relative = SculptureLinkedInputError.binaryLinkedRoot("binary-scene.3mdb")
        let refusals: [(String, SculptureLinkedInputError, () throws -> Data)] = [
            ("sculpture inspect", absolute, { try fixture.command(["inspect", "binary-scene.3mdb"]) }),
            ("portable inspect", absolute, { try fixture.portable(["inspect", "binary-scene.3mdb"]) }),
            ("portable export", absolute, { try fixture.portable(["export", "binary-scene.3mdb", "out.3md"]) }),
            (
                "portable insert input", relative,
                { try fixture.portable(["insert", "binary-scene.3mdb", "reference-insert.json", "out.3md"]) }
            ),
            ("reference inspect", absolute, { try fixture.reference(["inspect", "binary-scene.3mdb"]) }),
            (
                "reference insert input", relative,
                { try fixture.reference(["insert", "binary-scene.3mdb", "reference-insert.json", "out.3md"]) }
            ),
        ]
        for (name, expected, operation) in refusals {
            #expect(throws: expected, "\(name)") { _ = try operation() }
        }
        #expect(
            absolute.localizedDescription
                == "\(fixture.path("binary-scene.3mdb")): "
                + SculptureLinkedError.binaryLinkedRoot.localizedDescription
        )
        #expect(try fixture.contents() == before)
    }

    @Test func otherInputsKeepTheirExistingRefusals() throws {
        let fixture = try LinkedInputFixture()
        defer { fixture.clean() }
        try fixture.write(Data("plain text, not a scene\n".utf8), "plain.3md")
        let inspected = fixture.message { try fixture.command(["inspect", "plain.3md"]) }
        #expect(inspected.hasPrefix("Invalid sculpture \(fixture.path("plain.3md")): "))
        let reference = fixture.message { try fixture.reference(["inspect", "models/leaf.3md"]) }
        let leafPath = fixture.path("models/leaf.3md")
        #expect(reference == "Choose a self-contained composition or sparse world document: \(leafPath).")
        let snapshot = try SculptureThreeMDCodec.capture(.composition(fixture.parent))
        try fixture.write(SculptureThreeMDCodec.encode(snapshot, format: .binary(compression: .none)), "portable.3mdb")
        try fixture.request(
            ["version": 1, "files": ["models/leaf.3md"], "cell": ["x": 1, "y": 0, "z": 0]],
            "reference-insert.json"
        )
        let portableParent = fixture.message {
            try fixture.reference(["insert", "portable.3mdb", "reference-insert.json", "out.3md"])
        }
        #expect(portableParent.hasPrefix("portable.3mdb is a portable ThreeMD file."))
        #expect(!fixture.exists("out.3md"))
    }

    @Test func portableInspectionReadsSelfContainedBundlesAsCompositionsWithoutTheProjectFolder() async throws {
        let leaf = try Sculpture(title: "Leaf", width: 1, height: 1, layers: [[35]])
        let unit = try SculptureTileSize(width: 1, height: 1, depth: 1)
        let annex = try SculptureLinkedComposition(
            title: "Annex",
            width: 1,
            height: 1,
            tileSize: unit,
            layers: [[76]],
            files: [76: "../models/leaf.3md"]
        )
        let root = try SculptureLinkedComposition(
            title: "Linked room",
            width: 2,
            height: 1,
            tileSize: unit,
            layers: [[65, 66]],
            files: [65: "models/leaf.3md", 66: "rooms/annex.3md"],
            quarterTurns: [65: 1]
        )
        let project: [String: Data] = [
            "main.3md": try SculptureLinkedCodec.encode(root),
            "rooms/annex.3md": try SculptureLinkedCodec.encode(annex),
            "models/leaf.3md": SculptureCodec.encode(leaf),
        ]
        let resolution = try await SculptureLinkedResolver.resolve(rootPath: "main.3md") { path, _ in
            guard let data = project[path] else { throw CocoaError(.fileReadNoSuchFile) }
            return data
        }
        #expect(resolution.resolvedPaths == ["main.3md", "models/leaf.3md", "rooms/annex.3md"])

        // Only the bundle is on disk: none of the project files it was resolved from.
        let fixture = try LinkedInputFixture()
        defer { fixture.clean() }
        let bundles: [(SculptureLinkedBundleFormat, String)] = [(.readable, "bundle.3md"), (.binary, "bundle.3mdb")]
        for (format, name) in bundles {
            let bundle = try SculptureLinkedBundle.encode(resolution, format: format)
            try fixture.write(bundle, name)
            let inspection = try #require(
                JSONSerialization.jsonObject(with: fixture.portable(["inspect", name])) as? [String: Any]
            )
            #expect(inspection["kind"] as? String == "composition", "\(name)")
            #expect(inspection["title"] as? String == "Linked room", "\(name)")
            #expect(inspection["portableInput"] as? Bool == true, "\(name)")
            #expect(inspection["placementCount"] as? Int == 0, "\(name)")
            #expect(inspection["modelIDs"] as? [String] == resolution.composition.models.keys.sorted(), "\(name)")
            let snapshot = try SculptureLinkedBundle.decode(bundle)
            #expect(snapshot.scene == resolution.scene, "\(name)")
            let revisionBytes = snapshot.revision.canonicalContent.utf8.count
            #expect(inspection["revisionUTF8Bytes"] as? Int == revisionBytes, "\(name)")
            let output = "exported-\(format.rawValue).3md"
            _ = try fixture.portable(["export", name, output])
            #expect(try SculptureThreeMDCodec.decode(Data(contentsOf: fixture.file(output))).scene == resolution.scene)
            #expect(try Data(contentsOf: fixture.file(name)) == bundle)
        }
    }
}
