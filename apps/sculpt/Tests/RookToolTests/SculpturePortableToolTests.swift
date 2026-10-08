import Foundation
import RookSculpture
import Testing
import ThreeMD

@testable import RookTool

private struct PortableToolFixture {
    let folder: URL
    let graph: SculptureComposition
    let world: SculptureWorld
    let leaf: Sculpture

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("RookPortableTool-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        leaf = try Sculpture(title: "Shared leaf", width: 1, height: 1, layers: [[35]])
        let map = try SculptureTileMap(
            width: 2,
            height: 1,
            layers: [[65, 65]],
            tileSize: .init(width: 1, height: 1, depth: 1),
            bindings: [.init(glyph: 65, modelID: "leaf")]
        )
        graph = try SculptureComposition(
            title: "Reusable graph",
            rootID: "root",
            models: ["root": .tiles(map), "leaf": .sculpture(leaf)]
        )
        world = try SculptureWorld(
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

    func file(_ name: String) -> URL { folder.appendingPathComponent(name) }
    func clean() { try? FileManager.default.removeItem(at: folder) }
    func run(_ arguments: [String]) throws -> Data {
        try SculpturePortableTool.run(arguments: arguments, workingDirectory: folder)
    }
    func write(_ data: Data, _ name: String) throws { try data.write(to: file(name)) }
    func request(_ commands: [SculptureCommand], expected: String = "expected.3md") throws -> Data {
        let batch = try SculptureCommandBatch(commands: commands)
        let batchJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(batch))
        return try JSONSerialization.data(
            withJSONObject: ["version": 1, "modelID": "leaf", "expectedScene": expected, "batch": batchJSON],
            options: .sortedKeys
        )
    }
}

@Suite("Portable scene development commands", .serialized)
struct SculpturePortableToolTests {
    @Test func exportAcceptsEveryLegacySceneAndPublishesBothPortableFormatsWithoutChangingInput() throws {
        let fixture = try PortableToolFixture()
        defer { fixture.clean() }
        let sources: [(String, Data, SculptureScene)] = [
            ("voxel", try SculptureDocumentCodec.encode(fixture.leaf, format: .compact), .voxels(fixture.leaf)),
            ("graph", try SculptureCompositionCodec.encode(fixture.graph), .composition(fixture.graph)),
            ("world", try SculptureWorldCodec.encode(fixture.world), .world(fixture.world)),
        ]
        for (name, data, scene) in sources {
            try fixture.write(data, "\(name).input")
            for suffix in ["3md", "3mdb"] {
                let output = "\(name).\(suffix)"
                let receipt = try fixture.run(["export", "\(name).input", output])
                let json = try #require(JSONSerialization.jsonObject(with: receipt) as? [String: Any])
                #expect(json["action"] as? String == "export")
                #expect(try SculptureThreeMDCodec.decode(Data(contentsOf: fixture.file(output))).scene == scene)
            }
            #expect(try Data(contentsOf: fixture.file("\(name).input")) == data)
        }
    }

    @Test func inspectReportsStructuredDiagnosticsAndPortableSceneFacts() throws {
        let fixture = try PortableToolFixture()
        defer { fixture.clean() }
        let snapshot = try SculptureThreeMDCodec.capture(.world(fixture.world))
        try fixture.write(SculptureThreeMDCodec.encode(snapshot, format: .binary(compression: .none)), "scene.bin")
        let receipt = try fixture.run(["inspect", "scene.bin"])
        let json = try #require(JSONSerialization.jsonObject(with: receipt) as? [String: Any])
        #expect(json["kind"] as? String == "world" && json["portableInput"] as? Bool == true)
        #expect(json["placementCount"] as? Int == 2)
        #expect(json["modelIDs"] as? [String] == ["leaf", "root"])
        #expect(json["revisionUTF8Bytes"] as? Int == snapshot.revision.canonicalContent.utf8.count)
        let diagnostics = try #require(json["diagnostics"] as? [String: Any])
        #expect(diagnostics["isTruncated"] as? Bool == false)
    }

    @Test func applyUsesExactExpectedRevisionPreservesReferencesAndIsDeterministic() throws {
        let fixture = try PortableToolFixture()
        defer { fixture.clean() }
        let captured = try SculptureThreeMDCodec.capture(.world(fixture.world))
        let source = try SculptureThreeMDCodec.encode(captured)
        try fixture.write(source, "source.3md")
        try fixture.write(source, "expected.3md")
        try fixture.write(fixture.request([.paint(x: 0, y: 0, z: 0, glyph: "@")]), "request.json")
        _ = try fixture.run(["apply", "source.3md", "request.json", "first.3mdb"])
        _ = try fixture.run(["apply", "source.3md", "request.json", "second.3mdb"])
        let first = try Data(contentsOf: fixture.file("first.3mdb"))
        #expect(first == (try Data(contentsOf: fixture.file("second.3mdb"))))
        let edited = try SculptureThreeMDCodec.decode(first)
        guard case .world(let world) = edited.scene else { Issue.record("Expected world"); return }
        #expect(world.instances == fixture.world.instances && world.library.rootID == fixture.graph.rootID)
        #expect(try world.library.expanded().layers == [[64, 64]])
        let oldGraph = try DocumentCompositionCodec.decode(source)
        let newGraph = try DocumentCompositionCodec.decode(Data(edited.revision.canonicalContent.utf8))
        #expect(newGraph.entries.map(\.references) == oldGraph.entries.map(\.references))
        #expect(
            newGraph.entry(id: "leaf")?.document.planes[0].stableID
                == oldGraph.entry(id: "leaf")?.document.planes[0].stableID
        )
        #expect(try Data(contentsOf: fixture.file("source.3md")) == source)
    }

    @Test func staleSceneAndFailedCommandBatchNeverCreateOutput() throws {
        let fixture = try PortableToolFixture()
        defer { fixture.clean() }
        let source = try SculptureCompositionCodec.encode(fixture.graph)
        try fixture.write(source, "source.3md")
        let changed = try SculptureComposition(
            title: "Newer graph",
            rootID: fixture.graph.rootID,
            models: fixture.graph.models
        )
        try fixture.write(SculptureCompositionCodec.encode(changed), "expected.3md")
        try fixture.write(fixture.request([.paint(x: 0, y: 0, z: 0, glyph: "@")]), "request.json")
        do {
            _ = try fixture.run(["apply", "source.3md", "request.json", "stale.3md"])
            Issue.record("Expected stale revision")
        } catch { #expect(error.localizedDescription.contains("staleRevision at expectedRevision")) }
        #expect(!FileManager.default.fileExists(atPath: fixture.file("stale.3md").path))
        try fixture.write(source, "expected.3md")
        try fixture.write(
            fixture.request([.paint(x: 0, y: 0, z: 0, glyph: "@"), .erase(x: 9, y: 0, z: 0)]),
            "request.json"
        )
        #expect(throws: (any Error).self) { try fixture.run(["apply", "source.3md", "request.json", "partial.3md"]) }
        #expect(!FileManager.default.fileExists(atPath: fixture.file("partial.3md").path))
        #expect(try Data(contentsOf: fixture.file("source.3md")) == source)
    }

    @Test func requestsRejectUnknownDuplicateEquivalentAndOversizedFields() throws {
        let fixture = try PortableToolFixture()
        defer { fixture.clean() }
        let source = try SculptureCompositionCodec.encode(fixture.graph)
        try fixture.write(source, "source.3md")
        try fixture.write(source, "expected.3md")
        let base =
            "\"version\":1,\"modelID\":\"leaf\",\"expectedScene\":\"expected.3md\",\"batch\":{\"version\":1,\"commands\":[{\"action\":\"rename\",\"title\":\"Changed\"}]}"
        let malformed = [
            "{\(base),\"unknown\":true}",
            "{\(base),\"modelID\":\"leaf\"}",
            "{\(base),\"m\\u006fdelID\":\"leaf\"}",
            "{\(base),\"é\":1,\"e\\u0301\":2}",
            String(repeating: " ", count: SculpturePortableTool.maximumRequestBytes + 1),
        ]
        for (index, request) in malformed.enumerated() {
            try fixture.write(Data(request.utf8), "request.json")
            #expect(throws: (any Error).self) {
                try fixture.run(["apply", "source.3md", "request.json", "reject-\(index).3md"])
            }
            #expect(!FileManager.default.fileExists(atPath: fixture.file("reject-\(index).3md").path))
        }
    }

    @Test func exportsNeverOverwriteExistingFilesOrSymbolicLinksAndRejectUnknownExtensions() throws {
        let fixture = try PortableToolFixture()
        defer { fixture.clean() }
        try fixture.write(SculptureCompositionCodec.encode(fixture.graph), "source.3md")
        let sentinel = Data("Keep existing file".utf8)
        try fixture.write(sentinel, "existing.3mdb")
        try FileManager.default.createSymbolicLink(
            atPath: fixture.file("link.3md").path,
            withDestinationPath: fixture.file("existing.3mdb").path
        )
        for output in ["existing.3mdb", "link.3md", "unknown.bin"] {
            #expect(throws: (any Error).self) { try fixture.run(["export", "source.3md", output]) }
        }
        #expect(try Data(contentsOf: fixture.file("existing.3mdb")) == sentinel)
        #expect(!FileManager.default.fileExists(atPath: fixture.file("unknown.bin").path))
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: fixture.folder.path).filter {
                $0.hasPrefix(".rook-reference-")
            }.isEmpty
        )
    }

    @Test func cancellationBeforePublicationLeavesNoFile() async throws {
        let fixture = try PortableToolFixture()
        defer { fixture.clean() }
        try fixture.write(SculptureCompositionCodec.encode(fixture.graph), "source.3md")
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return try fixture.run(["export", "source.3md", "cancelled.3mdb"])
        }
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") } catch {
            #expect(error is CancellationError)
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.file("cancelled.3mdb").path))
    }
}
