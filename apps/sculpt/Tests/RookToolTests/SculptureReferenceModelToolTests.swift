import Foundation
import RookSculpture
import Testing

@testable import RookTool

private struct ReferenceFixture: Sendable {
    let folder: URL
    let input: URL
    let request: URL
    let expectedModel: URL
    let leaf: Sculpture
    let library: SculptureComposition
    let world: SculptureWorld

    init(worldInput: Bool = false) throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("RookReferenceTest-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let requests = folder.appendingPathComponent("requests", isDirectory: true)
        try FileManager.default.createDirectory(at: requests, withIntermediateDirectories: false)
        input = folder.appendingPathComponent("source with spaces.3md")
        request = requests.appendingPathComponent("request.json")
        expectedModel = requests.appendingPathComponent("expected.3mdb")
        leaf = try Sculpture(title: "Tree", width: 2, height: 2, layers: [Array("#...".utf8)])
        let tileSize = try SculptureTileSize(width: 2, height: 2, depth: 1)
        let nested = try SculptureTileMap(
            width: 1,
            height: 1,
            layers: [Array("T".utf8)],
            tileSize: tileSize,
            bindings: [try SculptureModelBinding(glyph: 84, modelID: "tree", quarterTurns: 1)]
        )
        let root = try SculptureTileMap(
            width: 2,
            height: 1,
            layers: [Array("TN".utf8)],
            tileSize: tileSize,
            bindings: [
                try SculptureModelBinding(glyph: 84, modelID: "tree"),
                try SculptureModelBinding(glyph: 78, modelID: "nested"),
            ]
        )
        library = try SculptureComposition(
            title: "Shared grove",
            rootID: "root",
            models: ["root": .tiles(root), "nested": .tiles(nested), "tree": .sculpture(leaf)]
        )
        world = try SculptureWorld(
            title: "Exact grove",
            library: library,
            instances: [
                try SculptureWorldInstance(
                    id: "first",
                    modelID: "tree",
                    origin: SculptureWorldPoint(x: 9_007_199_254_740_995, y: -99, z: Int64.min),
                    quarterTurns: 3
                ),
                try SculptureWorldInstance(id: "second", modelID: "tree", origin: .init(x: 8, y: 9, z: 10)),
                try SculptureWorldInstance(id: "grove", modelID: "root", origin: .init(x: -8, y: 0, z: 8)),
            ]
        )
        let data = try worldInput ? SculptureWorldCodec.encode(world) : SculptureCompositionCodec.encode(library)
        try data.write(to: input)
        try SculptureDocumentCodec.encode(leaf, format: .compact).write(to: expectedModel)
    }

    func writeRequest(_ fields: [String: Any]) throws {
        try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]).write(to: request)
    }

    func editRequest(_ commands: [SculptureCommand], modelID: String = "tree") throws {
        let batch = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(SculptureCommandBatch(commands: commands))
        )
        try writeRequest([
            "version": 1, "action": "editModel", "modelID": modelID,
            "expectedModel": expectedModel.lastPathComponent, "batch": batch,
        ])
    }

    func apply(_ name: String = "edited.3md", source: URL? = nil) throws -> Data {
        try SculptureReferenceModelTool.run(
            arguments: ["apply", (source ?? input).path, request.path, folder.appendingPathComponent(name).path],
            workingDirectory: folder
        )
    }

    func inspect(_ modelID: String? = nil) throws -> [String: Any] {
        let arguments = ["inspect", input.lastPathComponent] + (modelID.map { [$0] } ?? [])
        let data = try SculptureReferenceModelTool.run(arguments: arguments, workingDirectory: folder)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func clean() { try? FileManager.default.removeItem(at: folder) }
}

@Test func referenceCLIInspectsSharedIDsAndProvidesACompleteExpectedModelSnapshot() throws {
    let fixture = try ReferenceFixture()
    defer { fixture.clean() }
    let original = try Data(contentsOf: fixture.input)
    let listing = try fixture.inspect()
    #expect(listing["mode"] as? String == "composition")
    #expect(listing["rootID"] as? String == "root")
    #expect(listing["modelSource"] == nil)
    let models = try #require(listing["models"] as? [[String: Any]])
    #expect(models.compactMap { $0["id"] as? String } == ["nested", "root", "tree"])
    #expect(models.compactMap { $0["kind"] as? String } == ["tiles", "tiles", "voxel"])
    let selected = try fixture.inspect("tree")
    #expect(selected["selectedModelID"] as? String == "tree")
    let source = try #require(selected["modelSource"] as? String)
    #expect(try SculptureCodec.decode(Data(source.utf8)) == fixture.leaf)
    #expect(try Data(contentsOf: fixture.input) == original)
}

@Test func referenceCLIInspectsWorldTransformsWithoutLosingLargeIntegerPrecision() throws {
    let fixture = try ReferenceFixture(worldInput: true)
    defer { fixture.clean() }
    let listing = try fixture.inspect()
    #expect(listing["mode"] as? String == "sparse-world")
    let instances = try #require(listing["instances"] as? [[String: Any]])
    #expect(instances[0]["x"] as? String == "9007199254740995")
    #expect(instances[0]["y"] as? String == "-99")
    #expect(instances[0]["z"] as? String == String(Int64.min))
    #expect(instances[0]["quarterTurns"] as? Int == 3)
    #expect(instances.compactMap { $0["id"] as? String } == ["first", "second", "grove"])
}

@Test func referenceCLIUpdatesSharedCompositionLeafAndKeepsNestedBindings() throws {
    let fixture = try ReferenceFixture()
    defer { fixture.clean() }
    let original = try Data(contentsOf: fixture.input)
    try fixture.editRequest([.paint(x: 1, y: 1, z: 0, glyph: "@"), .rename(title: "Edited tree")])
    let requestBytes = try Data(contentsOf: fixture.request)
    let report = try #require(JSONSerialization.jsonObject(with: fixture.apply()) as? [String: Any])
    #expect(report["operation"] as? String == "reference.apply")
    #expect(report["action"] as? String == "editModel")
    #expect(report["appliedCommandCount"] as? Int == 2)
    let result = try SculptureCompositionCodec.decode(
        Data(contentsOf: fixture.folder.appendingPathComponent("edited.3md"))
    )
    #expect(result.title == fixture.library.title)
    #expect(result.rootID == fixture.library.rootID)
    #expect(result.models.keys.sorted() == fixture.library.models.keys.sorted())
    #expect(result.models["root"] == fixture.library.models["root"])
    #expect(result.models["nested"] == fixture.library.models["nested"])
    #expect(try result.expanded().occupiedCount == 4)
    #expect(try result.expanded(modelID: "tree").title == "Edited tree")
    #expect(try Data(contentsOf: fixture.input) == original)
    #expect(try Data(contentsOf: fixture.request) == requestBytes)
}

@Test func referenceCLIUpdatesWorldLeafWithoutChangingInstancesOrFlatteningTheLibrary() throws {
    let fixture = try ReferenceFixture(worldInput: true)
    defer { fixture.clean() }
    try fixture.editRequest([.paint(x: 1, y: 0, z: 0, glyph: "o")])
    _ = try fixture.apply()
    let result = try SculptureWorldCodec.decode(Data(contentsOf: fixture.folder.appendingPathComponent("edited.3md")))
    #expect(result.title == fixture.world.title)
    #expect(result.instances == fixture.world.instances)
    #expect(result.library.models.count == 3)
    #expect(result.library.models["root"] == fixture.library.models["root"])
    #expect(result.library.models["nested"] == fixture.library.models["nested"])
    #expect(try result.library.expanded(modelID: "tree").occupiedCount == 2)
    #expect(try result.library.expanded().occupiedCount == 4)
}

@Test func referenceCLIMakesOneWorldLeafUniqueThenEditsOnlyItsCopy() throws {
    let fixture = try ReferenceFixture(worldInput: true)
    defer { fixture.clean() }
    let snapshot = fixture.request.deletingLastPathComponent().appendingPathComponent("world snapshot.3md")
    try Data(contentsOf: fixture.input).write(to: snapshot)
    try fixture.writeRequest([
        "version": 1, "action": "makeUnique", "instanceID": "first",
        "newModelID": "tree-unique", "expectedSource": snapshot.lastPathComponent,
    ])
    _ = try fixture.apply("unique.3md")
    let uniqueURL = fixture.folder.appendingPathComponent("unique.3md")
    let unique = try SculptureWorldCodec.decode(Data(contentsOf: uniqueURL))
    #expect(unique.instances[0].modelID == "tree-unique")
    #expect(unique.instances[0].origin == fixture.world.instances[0].origin)
    #expect(unique.instances[0].quarterTurns == 3)
    #expect(Array(unique.instances.dropFirst()) == Array(fixture.world.instances.dropFirst()))
    #expect(unique.library.models["tree-unique"] == fixture.library.models["tree"])
    #expect(unique.library.models["tree"] == fixture.library.models["tree"])
    try fixture.editRequest([.paint(x: 1, y: 1, z: 0, glyph: "@")], modelID: "tree-unique")
    _ = try fixture.apply("unique-edited.3md", source: uniqueURL)
    let edited = try SculptureWorldCodec.decode(
        Data(contentsOf: fixture.folder.appendingPathComponent("unique-edited.3md"))
    )
    #expect(edited.instances == unique.instances)
    #expect(edited.library.models["tree"] == fixture.library.models["tree"])
    #expect(try edited.library.expanded(modelID: "tree-unique").occupiedCount == 2)
    #expect(try edited.library.expanded().occupiedCount == 2)
}

@Test func referenceCLIRejectsStaleModelsEvenWhenDimensionsAndOccupiedCountsMatch() throws {
    let fixture = try ReferenceFixture()
    defer { fixture.clean() }
    let stale = try Sculpture(title: fixture.leaf.title, width: 2, height: 2, layers: [Array("...#".utf8)])
    #expect(SculptureCommandEngine.inspect(stale) == SculptureCommandEngine.inspect(fixture.leaf))
    try SculptureCodec.encode(stale).write(to: fixture.expectedModel)
    try fixture.editRequest([.paint(x: 0, y: 1, z: 0, glyph: "@")])
    #expect(throws: SculptureModelEditingError.expectedModelChanged("tree")) { try fixture.apply() }
    #expect(!FileManager.default.fileExists(atPath: fixture.folder.appendingPathComponent("edited.3md").path))
}

@Test func referenceCLIRequiresCompleteMatchingSourceBytesForUniqueWorldInstances() throws {
    let fixture = try ReferenceFixture(worldInput: true)
    defer { fixture.clean() }
    let snapshot = fixture.request.deletingLastPathComponent().appendingPathComponent("snapshot.3md")
    var bytes = try Data(contentsOf: fixture.input)
    bytes.append(10)
    #expect(try SculptureWorldCodec.decode(bytes) == fixture.world)
    try bytes.write(to: snapshot)
    try fixture.writeRequest([
        "version": 1, "action": "makeUnique", "instanceID": "first",
        "newModelID": "tree-unique", "expectedSource": snapshot.lastPathComponent,
    ])
    do {
        _ = try fixture.apply()
        Issue.record("A formatting change must fail the full source byte precondition.")
    } catch {
        #expect(error.localizedDescription.contains("expectedSource bytes differ"))
    }
    #expect(!FileManager.default.fileExists(atPath: fixture.folder.appendingPathComponent("edited.3md").path))
}

@Test func referenceCLIRejectsUnknownInstancesExistingModelIDsAndNestedUniqueness() throws {
    let fixture = try ReferenceFixture(worldInput: true)
    defer { fixture.clean() }
    let snapshot = fixture.request.deletingLastPathComponent().appendingPathComponent("snapshot.3md")
    let original = try Data(contentsOf: fixture.input)
    try original.write(to: snapshot)
    for (instanceID, newModelID) in [
        ("missing", "unique-tree"), ("first", "tree"), ("first", "nested"), ("grove", "unique-grove"),
    ] {
        try fixture.writeRequest([
            "version": 1, "action": "makeUnique", "instanceID": instanceID,
            "newModelID": newModelID, "expectedSource": snapshot.lastPathComponent,
        ])
        #expect(throws: (any Error).self) { try fixture.apply() }
        #expect(!FileManager.default.fileExists(atPath: fixture.folder.appendingPathComponent("edited.3md").path))
    }
    #expect(try Data(contentsOf: fixture.input) == original)
    #expect(try Data(contentsOf: snapshot) == original)
}

@Test func referenceCLIFailedCommandsLeaveTheSourceAndOutputUntouched() throws {
    let fixture = try ReferenceFixture()
    defer { fixture.clean() }
    let original = try Data(contentsOf: fixture.input)
    try fixture.editRequest([.paint(x: 1, y: 1, z: 0, glyph: "@"), .erase(x: 2, y: 0, z: 0)])
    #expect(throws: (any Error).self) { try fixture.apply() }
    #expect(try Data(contentsOf: fixture.input) == original)
    #expect(!FileManager.default.fileExists(atPath: fixture.folder.appendingPathComponent("edited.3md").path))
    #expect(
        !(try FileManager.default.contentsOfDirectory(atPath: fixture.folder.path)).contains {
            $0.hasPrefix(".rook-reference-")
        }
    )
}

@Test func referenceCLIRefusesTileEditingFlatteningAndAmbiguousRequestFields() throws {
    let fixture = try ReferenceFixture()
    defer { fixture.clean() }
    #expect(throws: SculptureModelEditingError.voxelModelRequired("root")) { try fixture.inspect("root") }
    try fixture.editRequest([.erase(x: 0, y: 0, z: 0)], modelID: "root")
    #expect(throws: SculptureModelEditingError.voxelModelRequired("root")) { try fixture.apply() }
    try fixture.editRequest([.erase(x: 0, y: 0, z: 0)])
    var request = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.request)) as? [String: Any])
    request["expectedHash"] = "short-token"
    try fixture.writeRequest(request)
    #expect(throws: (any Error).self) { try fixture.apply() }
    #expect(throws: (any Error).self) { try fixture.apply("must-not-flatten.3mdb") }
    let scalar = fixture.folder.appendingPathComponent("plain.3md")
    try SculptureCodec.encode(fixture.leaf).write(to: scalar)
    #expect(throws: (any Error).self) { try fixture.apply(source: scalar) }
    #expect(!FileManager.default.fileExists(atPath: fixture.folder.appendingPathComponent("edited.3md").path))
    #expect(
        !FileManager.default.fileExists(atPath: fixture.folder.appendingPathComponent("must-not-flatten.3mdb").path)
    )
}

@Test func referenceCLIRefusesExistingOutputsIncludingSourceDirectoriesAndDanglingLinks() throws {
    let fixture = try ReferenceFixture()
    defer { fixture.clean() }
    try fixture.editRequest([.paint(x: 1, y: 1, z: 0, glyph: "@")])
    let original = try Data(contentsOf: fixture.input)
    #expect(throws: (any Error).self) { try fixture.apply(fixture.input.lastPathComponent) }
    #expect(try Data(contentsOf: fixture.input) == original)
    let existing = fixture.folder.appendingPathComponent("existing.3md")
    let preserved = Data("preserve this output".utf8)
    try preserved.write(to: existing)
    #expect(throws: (any Error).self) { try fixture.apply(existing.lastPathComponent) }
    #expect(try Data(contentsOf: existing) == preserved)
    let directory = fixture.folder.appendingPathComponent("directory.3md")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    #expect(throws: (any Error).self) { try fixture.apply(directory.lastPathComponent) }
    let link = fixture.folder.appendingPathComponent("dangling.3md")
    let destination = fixture.folder.appendingPathComponent("absent.3md")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: destination)
    #expect(throws: (any Error).self) { try fixture.apply(link.lastPathComponent) }
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == destination.path)
    #expect(!FileManager.default.fileExists(atPath: destination.path))
    #expect(
        !(try FileManager.default.contentsOfDirectory(atPath: fixture.folder.path)).contains {
            $0.hasPrefix(".rook-reference-")
        }
    )
}

@Test func referenceCLIBoundsRequestFilesAndRefusesNonRegularInputs() throws {
    let fixture = try ReferenceFixture()
    defer { fixture.clean() }
    try fixture.editRequest([.erase(x: 0, y: 0, z: 0)])
    var bytes = try Data(contentsOf: fixture.request)
    bytes.append(Data(repeating: 32, count: SculptureReferenceModelTool.maximumRequestBytes - bytes.count))
    try bytes.write(to: fixture.request)
    _ = try fixture.apply("exact-limit.3md")
    bytes.append(32)
    try bytes.write(to: fixture.request)
    #expect(throws: (any Error).self) { try fixture.apply() }
    #expect(!FileManager.default.fileExists(atPath: fixture.folder.appendingPathComponent("edited.3md").path))
    #expect(throws: (any Error).self) {
        try SculptureReferenceModelTool.run(
            arguments: ["inspect", fixture.folder.path],
            workingDirectory: fixture.folder
        )
    }
    let oversized = fixture.folder.appendingPathComponent("oversized.3md")
    try Data(repeating: 32, count: SculptureCompositionCodec.maximumBytes + 1).write(to: oversized)
    #expect(throws: (any Error).self) {
        try SculptureReferenceModelTool.run(arguments: ["inspect", oversized.path], workingDirectory: fixture.folder)
    }
}

@Test func referenceCLICancellationDoesNotPublishAFile() async throws {
    let fixture = try ReferenceFixture()
    defer { fixture.clean() }
    try fixture.editRequest([.erase(x: 0, y: 0, z: 0)])
    let operation = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try fixture.apply()
    }
    await #expect(throws: CancellationError.self) { try await operation.value }
    #expect(!FileManager.default.fileExists(atPath: fixture.folder.appendingPathComponent("edited.3md").path))
}
