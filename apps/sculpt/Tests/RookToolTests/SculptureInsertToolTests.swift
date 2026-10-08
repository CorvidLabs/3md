import Foundation
import RookSculpture
import Testing
import ThreeMD

@testable import RookTool

private struct InsertFixture {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("RookInsertTool-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("models"),
            withIntermediateDirectories: false
        )
    }

    func file(_ name: String) -> URL { folder.appendingPathComponent(name) }
    func clean() { try? FileManager.default.removeItem(at: folder) }
    func write(_ data: Data, _ name: String) throws { try data.write(to: file(name)) }
    func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: file(name).path) }
    func portable(_ arguments: [String]) throws -> Data {
        try SculpturePortableTool.run(arguments: ["insert"] + arguments, workingDirectory: folder)
    }
    func reference(_ arguments: [String]) throws -> Data {
        try SculptureReferenceModelTool.run(arguments: ["insert"] + arguments, workingDirectory: folder)
    }

    func request(_ json: String, name: String = "request.json") throws { try write(Data(json.utf8), name) }

    func receipt(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func message(_ operation: () throws -> Data) -> String {
        do {
            _ = try operation()
            return ""
        } catch { return error.localizedDescription }
    }

    static func leaf(_ title: String, glyph: UInt8 = 35, width: Int = 1) throws -> Sculpture {
        try Sculpture(title: title, width: width, height: 1, layers: [Array(repeating: glyph, count: width)])
    }

    static func composition(_ layer: [UInt8] = [46, 46, 46, 46], tile: Int = 4) throws -> SculptureComposition {
        let bindings = layer.contains(65) ? [try SculptureModelBinding(glyph: 65, modelID: "existing")] : []
        let map = try SculptureTileMap(
            width: layer.count,
            height: 1,
            layers: [layer],
            tileSize: .init(width: tile, height: tile, depth: tile),
            bindings: bindings
        )
        var models: [String: SculptureCompositionModel] = ["root": .tiles(map)]
        if !bindings.isEmpty { models["existing"] = .sculpture(try leaf("Existing castle", glyph: 42)) }
        return try SculptureComposition(title: "Parent map", rootID: "root", models: models)
    }

    /// Portable copies of a scene, so the portable command has identities to preserve.
    func writePortable(_ scene: SculptureScene, as name: String) throws -> SculptureThreeMDSnapshot {
        let snapshot = try SculptureThreeMDCodec.capture(scene)
        try write(SculptureThreeMDCodec.encode(snapshot, format: .text), name)
        return snapshot
    }
}

private let defaultRequest =
    "{\"version\":1,\"files\":[\"models/one.3md\",\"models/two.3mdb\"],\"cell\":{\"x\":0,\"y\":0,\"z\":0},\"expectedScene\":\"expected.3md\"}"

@Suite("Explicit-file insertion commands", .serialized)
struct SculptureInsertToolTests {
    @Test func portableInsertPlacesFilesInRequestOrderAndWritesAReopenableDeterministicOutput() throws {
        let fixture = try InsertFixture()
        defer { fixture.clean() }
        let parent = try InsertFixture.composition()
        let snapshot = try fixture.writePortable(.composition(parent), as: "source.3md")
        try fixture.write(Data(contentsOf: fixture.file("source.3md")), "expected.3md")
        let one = try InsertFixture.leaf("One", glyph: 35)
        let nested = try SculptureComposition(
            title: "Two nested",
            rootID: "root",
            models: [
                "root": .tiles(
                    try SculptureTileMap(
                        width: 1,
                        height: 1,
                        layers: [[65]],
                        tileSize: .init(width: 1, height: 1, depth: 1),
                        bindings: [try .init(glyph: 65, modelID: "cell")]
                    )
                ),
                "cell": .sculpture(try InsertFixture.leaf("Cell", glyph: 64)),
            ]
        )
        try SculptureCodec.encode(one).write(to: fixture.file("models/one.3md"))
        try SculptureThreeMDCodec.encode(
            SculptureThreeMDCodec.capture(.composition(nested)),
            format: .binary(compression: .none)
        ).write(to: fixture.file("models/two.3mdb"))
        try fixture.request(defaultRequest)

        let receipt = try fixture.receipt(fixture.portable(["source.3md", "request.json", "out.3mdb"]))
        let again = try fixture.portable(["source.3md", "request.json", "out2.3mdb"])
        #expect(try Data(contentsOf: fixture.file("out.3mdb")) == Data(contentsOf: fixture.file("out2.3mdb")))
        #expect(receipt["action"] as? String == "insert" && receipt["kind"] as? String == "composition")
        #expect(receipt["title"] as? String == "Parent map" && receipt["storage"] as? String == "portable")
        #expect(receipt["output"] as? String == fixture.file("out.3mdb").standardizedFileURL.path)
        let placed = try #require(receipt["placed"] as? [[String: Any]])
        #expect(placed.map { $0["file"] as? String } == ["models/one.3md", "models/two.3mdb"])
        #expect(placed.map { $0["title"] as? String } == ["One", "Two nested"])
        #expect(placed.map { ($0["cell"] as? [String: Int])?["x"] } == [0, 1])
        #expect(placed.allSatisfy { ($0["modelID"] as? String)?.hasPrefix("insert-model-") == true })
        #expect((receipt["replacedGlyphs"] as? [String])?.isEmpty == true)
        #expect(receipt["bytes"] as? Int == (try Data(contentsOf: fixture.file("out.3mdb"))).count)
        #expect(receipt["diagnostics"] is [String: Any])

        let reopened = try SculptureThreeMDCodec.decode(Data(contentsOf: fixture.file("out.3mdb")))
        guard case .composition(let inserted) = reopened.scene, case .tiles(let map) = inserted.models["root"] else {
            Issue.record("Expected a composition with a tile map"); return
        }
        #expect(map.layers == [[65, 66, 46, 46]] && map.bindings.count == 2)
        #expect(inserted.models.count == 1 + 1 + 2)
        #expect(receipt["revisionUTF8Bytes"] as? Int == reopened.revision.canonicalContent.utf8.count)
        #expect(reopened.revision != snapshot.revision)
        #expect(!again.isEmpty)
        #expect(try SculptureThreeMDCodec.decode(Data(contentsOf: fixture.file("source.3md"))) == snapshot)
    }

    @Test func portableInsertPlacesWorldModelsAtExactInt64FocusStrings() throws {
        let fixture = try InsertFixture()
        defer { fixture.clean() }
        let world = try SculptureWorld(title: "Parent world", library: InsertFixture.composition(), instances: [])
        _ = try fixture.writePortable(.world(world), as: "source.3md")
        try fixture.write(Data(contentsOf: fixture.file("source.3md")), "expected.3md")
        try SculptureCodec.encode(InsertFixture.leaf("First", width: 3)).write(to: fixture.file("models/first.3md"))
        try SculptureCodec.encode(InsertFixture.leaf("Second", glyph: 64)).write(to: fixture.file("models/second.3md"))
        try fixture.request(
            "{\"version\":1,\"files\":[\"models/first.3md\",\"models/second.3md\"],\"focus\":{\"x\":\"9007199254740993\",\"y\":\"-9223372036854775808\",\"z\":\"9223372036854775000\"},\"expectedScene\":\"expected.3md\"}"
        )
        let receipt = try fixture.receipt(fixture.portable(["source.3md", "request.json", "out.3md"]))
        #expect(receipt["kind"] as? String == "world")
        let placed = try #require(receipt["placed"] as? [[String: Any]])
        let origins = placed.compactMap { $0["origin"] as? [String: String] }
        #expect(origins.map { $0["x"] } == ["9007199254740993", "9007199254740997"])
        #expect(origins.allSatisfy { $0["y"] == "-9223372036854775808" && $0["z"] == "9223372036854775000" })
        #expect(placed.map { $0["instanceID"] as? String } == ["insert-instance-1", "insert-instance-2"])
        let reopened = try SculptureThreeMDCodec.decode(Data(contentsOf: fixture.file("out.3md")))
        guard case .world(let inserted) = reopened.scene else { Issue.record("Expected a world"); return }
        #expect(inserted.instances.map(\.origin.x) == [9_007_199_254_740_993, 9_007_199_254_740_997])
        #expect(inserted.instances.allSatisfy { $0.origin.y == .min && $0.origin.z == 9_223_372_036_854_775_000 })
        #expect(inserted.library.models.count == world.library.models.count + 2)
    }

    @Test func occupiedTargetsNeedExplicitPermissionAndReportWhatTheyReplace() throws {
        let fixture = try InsertFixture()
        defer { fixture.clean() }
        _ = try fixture.writePortable(.composition(InsertFixture.composition([65, 46, 46, 46])), as: "source.3md")
        try fixture.write(Data(contentsOf: fixture.file("source.3md")), "expected.3md")
        try SculptureCodec.encode(InsertFixture.leaf("Replacement")).write(to: fixture.file("models/one.3md"))
        let refusing =
            "{\"version\":1,\"files\":[\"models/one.3md\"],\"cell\":{\"x\":0,\"y\":0,\"z\":0},\"expectedScene\":\"expected.3md\"}"
        try fixture.request(refusing)
        let refusal = fixture.message { try fixture.portable(["source.3md", "request.json", "refused.3md"]) }
        #expect(refusal.contains("replaceOccupied") && refusal.contains("column 1, row 1, layer 1"))
        #expect(refusal.contains("holds A"))
        #expect(!fixture.exists("refused.3md"))
        try fixture.request(refusing.replacingOccurrences(of: "\"cell\"", with: "\"replaceOccupied\":false,\"cell\""))
        #expect(
            fixture.message { try fixture.portable(["source.3md", "request.json", "refused.3md"]) }.contains(
                "replaceOccupied"
            )
        )
        #expect(!fixture.exists("refused.3md"))

        try fixture.request(refusing.replacingOccurrences(of: "\"cell\"", with: "\"replaceOccupied\":true,\"cell\""))
        let receipt = try fixture.receipt(fixture.portable(["source.3md", "request.json", "replaced.3md"]))
        #expect(receipt["replacedGlyphs"] as? [String] == ["A"])
        let reopened = try SculptureThreeMDCodec.decode(Data(contentsOf: fixture.file("replaced.3md")))
        guard case .composition(let inserted) = reopened.scene, case .tiles(let map) = inserted.models["root"] else {
            Issue.record("Expected a composition"); return
        }
        #expect(map.layers[0][0] != 65 && inserted.models["existing"] != nil)
    }

    @Test func worldAndGenericMarkdownChildrenAreRefusedByNameWithoutWritingAnything() throws {
        let fixture = try InsertFixture()
        defer { fixture.clean() }
        _ = try fixture.writePortable(.composition(InsertFixture.composition()), as: "source.3md")
        try fixture.write(Data(contentsOf: fixture.file("source.3md")), "expected.3md")
        let world = try SculptureWorld(title: "Child world", library: InsertFixture.composition(), instances: [])
        try SculptureWorldCodec.encode(world).write(to: fixture.file("models/world.3md"))
        try Data("---\ntitle: Notes\n---\nHello\n".utf8).write(to: fixture.file("models/notes.3md"))
        try SculptureCodec.encode(InsertFixture.leaf("Fine")).write(to: fixture.file("models/fine.3md"))
        for (name, reason) in [("world.3md", "sparse world"), ("notes.3md", "")] {
            try fixture.request(
                "{\"version\":1,\"files\":[\"models/fine.3md\",\"models/\(name)\"],\"cell\":{\"x\":0,\"y\":0,\"z\":0},\"expectedScene\":\"expected.3md\"}"
            )
            let message = fixture.message { try fixture.portable(["source.3md", "request.json", "out-\(name)"]) }
            #expect(message.hasPrefix("models/\(name):"), "Refusals name the file: \(message)")
            if !reason.isEmpty { #expect(message.contains(reason)) }
            #expect(!fixture.exists("out-\(name)"))
        }
        try fixture.writeNative(.composition(InsertFixture.composition()), as: "native.3md")
        try fixture.request("{\"version\":1,\"files\":[\"models/world.3md\"],\"cell\":{\"x\":0,\"y\":0,\"z\":0}}")
        let reference = fixture.message { try fixture.reference(["native.3md", "request.json", "native-out.3md"]) }
        #expect(reference.hasPrefix("models/world.3md:") && !fixture.exists("native-out.3md"))
    }

    @Test func staleRevisionsExistingOutputsAndBadExtensionsRefuseWithoutWriting() throws {
        let fixture = try InsertFixture()
        defer { fixture.clean() }
        _ = try fixture.writePortable(.composition(InsertFixture.composition()), as: "source.3md")
        let changed = try SculptureComposition(
            title: "Newer map",
            rootID: "root",
            models: InsertFixture.composition().models
        )
        _ = try fixture.writePortable(.composition(changed), as: "expected.3md")
        try SculptureCodec.encode(InsertFixture.leaf("One")).write(to: fixture.file("models/one.3md"))
        try SculptureCodec.encode(InsertFixture.leaf("Two")).write(to: fixture.file("models/two.3mdb"))
        try fixture.request(defaultRequest)
        let stale = fixture.message { try fixture.portable(["source.3md", "request.json", "stale.3md"]) }
        #expect(stale.contains("staleRevision at expectedRevision"))
        #expect(!fixture.exists("stale.3md"))

        try fixture.write(Data(contentsOf: fixture.file("source.3md")), "expected.3md")
        let sentinel = Data("Keep existing file".utf8)
        try fixture.write(sentinel, "existing.3md")
        try FileManager.default.createSymbolicLink(
            atPath: fixture.file("link.3md").path,
            withDestinationPath: fixture.file("existing.3md").path
        )
        for output in ["existing.3md", "link.3md"] {
            #expect(
                fixture.message { try fixture.portable(["source.3md", "request.json", output]) }.contains(
                    "Refusing existing output"
                )
            )
        }
        #expect(try Data(contentsOf: fixture.file("existing.3md")) == sentinel)
        #expect(
            fixture.message { try fixture.portable(["source.3md", "request.json", "bad.txt"]) }.contains(
                ".3md or .3mdb"
            )
        )
        #expect(!fixture.exists("bad.txt"))
        #expect(fixture.message { try fixture.portable(["source.3md", "request.json"]) }.contains("Usage"))
        #expect(
            fixture.message {
                try fixture.reference(["source.3md", "request.json", "reference.3mdb"])
            }.contains(".3md")
        )
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: fixture.folder.path).filter {
                $0.hasPrefix(".rook-reference-")
            }.isEmpty
        )
    }

    @Test func requestsAreStrictBoundedAndNameTheirMistakes() throws {
        let fixture = try InsertFixture()
        defer { fixture.clean() }
        _ = try fixture.writePortable(.composition(InsertFixture.composition()), as: "source.3md")
        try fixture.write(Data(contentsOf: fixture.file("source.3md")), "expected.3md")
        let files = "\"files\":[\"models/one.3md\"]"
        let cell = "\"cell\":{\"x\":0,\"y\":0,\"z\":0}"
        let expected = "\"expectedScene\":\"expected.3md\""
        try SculptureCodec.encode(InsertFixture.leaf("One")).write(to: fixture.file("models/one.3md"))
        let cases: [(String, String)] = [
            ("{\"version\":2,\(files),\(cell),\(expected)}", "version 1"),
            ("{\"version\":1,\(files),\(cell),\(expected),\"unknown\":true}", "unknown"),
            ("{\"version\":1,\(files),\(cell),\(cell),\(expected)}", "duplicate"),
            ("{\"version\":1,\(files),\(expected)}", "exactly one of"),
            (
                "{\"version\":1,\(files),\(cell),\"focus\":{\"x\":\"0\",\"y\":\"0\",\"z\":\"0\"},\(expected)}",
                "exactly one of"
            ),
            ("{\"version\":1,\"files\":[],\(cell),\(expected)}", "at least one file"),
            ("{\"version\":1,\"files\":[\"\"],\(cell),\(expected)}", "nonempty"),
            ("{\"version\":1,\(files),\"cell\":{\"x\":0,\"y\":0},\(expected)}", "integer x, y and z"),
            (
                "{\"version\":1,\(files),\"cell\":{\"x\":0,\"y\":0,\"z\":0.5},\(expected)}",
                "Number 0.5 is not representable"
            ),
            (
                "{\"version\":1,\(files),\"focus\":{\"x\":\"0\",\"y\":\"0\",\"z\":\"0\"},\(expected)}",
                "Use \\\"cell\\\""
            ),
            ("{\"version\":1,\(files),\(cell),\(expected),\"replaceOccupied\":1}", "replaceOccupied"),
            ("{\"version\":1,\(files),\(cell)}", "requires expectedScene"),
        ]
        for (index, (request, fragment)) in cases.enumerated() {
            try fixture.request(request)
            let message = fixture.message {
                try fixture.portable(["source.3md", "request.json", "rejected-\(index).3md"])
            }
            #expect(!message.isEmpty, "Request \(index) was accepted")
            #expect(
                message.localizedCaseInsensitiveContains(fragment.replacingOccurrences(of: "\\\"", with: "\"")),
                "Request \(index) said: \(message)"
            )
            #expect(!fixture.exists("rejected-\(index).3md"))
        }
        let world = try SculptureWorld(title: "Parent world", library: InsertFixture.composition(), instances: [])
        _ = try fixture.writePortable(.world(world), as: "world.3md")
        try fixture.write(Data(contentsOf: fixture.file("world.3md")), "expected.3md")
        for coordinate in ["+5", "05", "-0", "1.5", "9223372036854775808", ""] {
            try fixture.request(
                "{\"version\":1,\(files),\"focus\":{\"x\":\"\(coordinate)\",\"y\":\"0\",\"z\":\"0\"},\(expected)}"
            )
            let message = fixture.message {
                try fixture.portable(["world.3md", "request.json", "bad-\(coordinate).3md"])
            }
            #expect(message.contains("Int64"), "Coordinate '\(coordinate)' said: \(message)")
        }
        try fixture.request("{\"version\":1,\(files),\(cell),\(expected)}")
        #expect(
            fixture.message { try fixture.portable(["world.3md", "request.json", "kind.3md"]) }.contains("\"focus\"")
        )
        try fixture.write(
            Data(String(repeating: " ", count: SculptureInsertTool.maximumRequestBytes + 1).utf8),
            "request.json"
        )
        let oversizedRequest = fixture.message { try fixture.portable(["source.3md", "request.json", "huge.3md"]) }
        #expect(oversizedRequest.contains("at most \(SculptureInsertTool.maximumRequestBytes) bytes"))
        #expect(!fixture.exists("huge.3md"))
    }

    @Test func earlyChecksRefuseByCountCellAndSizeBeforeReadingFiles() throws {
        let fixture = try InsertFixture()
        defer { fixture.clean() }
        _ = try fixture.writePortable(.composition(InsertFixture.composition([46])), as: "source.3md")
        try fixture.write(Data(contentsOf: fixture.file("source.3md")), "expected.3md")
        // None of these files exist, so only an early check can produce the cell-count refusal.
        try fixture.request(
            "{\"version\":1,\"files\":[\"models/a.3md\",\"models/b.3md\"],\"cell\":{\"x\":0,\"y\":0,\"z\":0},\"expectedScene\":\"expected.3md\"}"
        )
        let cells = fixture.message { try fixture.portable(["source.3md", "request.json", "cells.3md"]) }
        #expect(cells.contains("2 models") && cells.contains("1 remain"))

        _ = try fixture.writePortable(.composition(InsertFixture.composition()), as: "source.3md")
        try fixture.write(Data(contentsOf: fixture.file("source.3md")), "expected.3md")
        let tooMany = (0..<65).map { "\"models/m\($0).3md\"" }.joined(separator: ",")
        try fixture.request(
            "{\"version\":1,\"files\":[\(tooMany)],\"cell\":{\"x\":0,\"y\":0,\"z\":0},\"expectedScene\":\"expected.3md\"}"
        )
        let count = fixture.message { try fixture.portable(["source.3md", "request.json", "count.3md"]) }
        #expect(count.contains("65") && count.contains("64"))

        try SculptureCodec.encode(InsertFixture.leaf("Wide", width: 9)).write(to: fixture.file("models/wide.3md"))
        try Data("not read".utf8).write(to: fixture.file("models/z-unread.3md"))
        try fixture.request(
            "{\"version\":1,\"files\":[\"models/wide.3md\",\"models/z-unread.3md\"],\"cell\":{\"x\":0,\"y\":0,\"z\":0},\"expectedScene\":\"expected.3md\"}"
        )
        let fit = fixture.message { try fixture.portable(["source.3md", "request.json", "fit.3md"]) }
        #expect(fit.hasPrefix("models/wide.3md needs 9 × 1 × 1 cells"))
        #expect(fit.contains("4 × 4 × 4"))

        try Data().write(to: fixture.file("models/huge.3mdb"))
        let handle = try FileHandle(forWritingTo: fixture.file("models/huge.3mdb"))
        try handle.truncate(atOffset: UInt64(SculptureInsertionPlan.maximumBytes + 1))
        try handle.close()
        try fixture.request(
            "{\"version\":1,\"files\":[\"models/huge.3mdb\"],\"cell\":{\"x\":0,\"y\":0,\"z\":0},\"expectedScene\":\"expected.3md\"}"
        )
        let bytes = fixture.message { try fixture.portable(["source.3md", "request.json", "bytes.3md"]) }
        #expect(bytes.contains("models/huge.3mdb") && bytes.contains("20 MiB"))
        for name in ["cells.3md", "count.3md", "fit.3md", "bytes.3md"] { #expect(!fixture.exists(name)) }
    }

    @Test func symbolicLinkChildrenAreRefusedByName() throws {
        let fixture = try InsertFixture()
        defer { fixture.clean() }
        _ = try fixture.writePortable(.composition(InsertFixture.composition()), as: "source.3md")
        try fixture.write(Data(contentsOf: fixture.file("source.3md")), "expected.3md")
        try SculptureCodec.encode(InsertFixture.leaf("Real")).write(to: fixture.file("models/real.3md"))
        try FileManager.default.createSymbolicLink(
            atPath: fixture.file("models/link.3md").path,
            withDestinationPath: fixture.file("models/real.3md").path
        )
        try fixture.request(
            "{\"version\":1,\"files\":[\"models/link.3md\"],\"cell\":{\"x\":0,\"y\":0,\"z\":0},\"expectedScene\":\"expected.3md\"}"
        )
        let message = fixture.message { try fixture.portable(["source.3md", "request.json", "link-out.3md"]) }
        #expect(message.hasPrefix("models/link.3md:") && message.contains("symbolic link"))
        #expect(!fixture.exists("link-out.3md"))
    }

    @Test func referenceInsertWritesANativeReadableCompositionAndWorldAndRefusesStaleStyleFields() throws {
        let fixture = try InsertFixture()
        defer { fixture.clean() }
        try fixture.writeNative(.composition(InsertFixture.composition([65, 46, 46, 46])), as: "map.3md")
        try SculptureCodec.encode(InsertFixture.leaf("One")).write(to: fixture.file("models/one.3md"))
        let portableChild = try SculptureThreeMDCodec.capture(.voxels(InsertFixture.leaf("Portable", glyph: 64)))
        try SculptureThreeMDCodec.encode(portableChild, format: .binary(compression: .none))
            .write(to: fixture.file("models/portable.3mdb"))
        try fixture.request(
            "{\"version\":1,\"files\":[\"models/one.3md\",\"models/portable.3mdb\"],\"cell\":{\"x\":1,\"y\":0,\"z\":0}}"
        )
        let receipt = try fixture.receipt(fixture.reference(["map.3md", "request.json", "map-out.3md"]))
        #expect(receipt["action"] as? String == "insert" && receipt["storage"] as? String == "native")
        #expect(receipt["revisionUTF8Bytes"] == nil && receipt["diagnostics"] == nil)
        let placed = try #require(receipt["placed"] as? [[String: Any]])
        #expect(placed.map { $0["title"] as? String } == ["One", "Portable"])
        let output = try Data(contentsOf: fixture.file("map-out.3md"))
        #expect(SculptureCompositionCodec.isComposition(output) && !SculptureThreeMDCodec.isPortable(output))
        guard case .tiles(let map) = try SculptureCompositionCodec.decode(output).models["root"] else {
            Issue.record("Expected a tile map"); return
        }
        #expect(map.layers == [[65, 66, 67, 46]])
        #expect(try Data(contentsOf: fixture.file("map-out.3md")) == output)

        try fixture.writeNative(
            .world(SculptureWorld(title: "World", library: InsertFixture.composition(), instances: [])),
            as: "world.3md"
        )
        try fixture.request(
            "{\"version\":1,\"files\":[\"models/one.3md\"],\"focus\":{\"x\":\"-5\",\"y\":\"7\",\"z\":\"9\"}}"
        )
        let worldReceipt = try fixture.receipt(fixture.reference(["world.3md", "request.json", "world-out.3md"]))
        #expect(worldReceipt["kind"] as? String == "world")
        let world = try SculptureWorldCodec.decode(Data(contentsOf: fixture.file("world-out.3md")))
        #expect(world.instances.map(\.origin) == [.init(x: -5, y: 7, z: 9)])

        try fixture.request(
            "{\"version\":1,\"files\":[\"models/one.3md\"],\"focus\":{\"x\":\"0\",\"y\":\"0\",\"z\":\"0\"},\"expectedScene\":\"map.3md\"}"
        )
        #expect(
            fixture.message { try fixture.reference(["world.3md", "request.json", "again.3md"]) }.contains(
                "expectedScene"
            )
        )
        _ = try fixture.writePortable(.composition(InsertFixture.composition()), as: "portable-parent.3md")
        let portableInput = fixture.message {
            try fixture.reference(["portable-parent.3md", "request.json", "again.3md"])
        }
        #expect(portableInput.hasPrefix("portable-parent.3md is a portable ThreeMD file."))
        #expect(portableInput.contains("sculpture portable insert") && !fixture.exists("again.3md"))
    }

    @Test func nativeBudgetRefusesAnInsertionThatWouldNotReopen() throws {
        let fixture = try InsertFixture()
        defer { fixture.clean() }
        func tall() throws -> Sculpture {
            try Sculpture(
                title: "Tall",
                width: 1,
                height: 256,
                layers: [[UInt8]](repeating: [UInt8](repeating: Sculpture.empty, count: 256), count: 256)
            )
        }
        let map = try SculptureTileMap(
            width: 2,
            height: 1,
            layers: [[65, 46]],
            tileSize: .init(width: 1, height: 256, depth: 256),
            bindings: [try .init(glyph: 65, modelID: "first")]
        )
        let parent = try SculptureComposition(
            title: "Tall parent",
            rootID: "root",
            models: ["root": .tiles(map), "first": .sculpture(tall())]
        )
        try fixture.writeNative(.composition(parent), as: "parent.3md")
        try SculptureCodec.encode(tall()).write(to: fixture.file("models/second.3md"))
        try fixture.request("{\"version\":1,\"files\":[\"models/second.3md\"],\"cell\":{\"x\":1,\"y\":0,\"z\":0}}")
        let message = fixture.message { try fixture.reference(["parent.3md", "request.json", "tall-out.3md"]) }
        #expect(message.contains("too large to reopen"))
        #expect(!fixture.exists("tall-out.3md"))
        #expect(try SculptureCompositionCodec.decode(Data(contentsOf: fixture.file("parent.3md"))) == parent)
    }

    @Test func portableInsertIntoANativeInputKeepsChildMetadataAndNeverBlamesAnOpenSceneThatHasNone() throws {
        let fixture = try InsertFixture()
        defer { fixture.clean() }
        try fixture.writeNative(.composition(InsertFixture.composition()), as: "native.3md")
        try fixture.write(Data(contentsOf: fixture.file("native.3md")), "expected.3md")
        let annotated = try SculptureThreeMDCodec.capture(.voxels(InsertFixture.leaf("Annotated", glyph: 64)))
        try SculptureThreeMDCodec.encode(annotated).write(to: fixture.file("models/annotated.3md"))
        try SculptureCodec.encode(InsertFixture.leaf("Plain")).write(to: fixture.file("models/plain.3md"))
        try fixture.request(
            "{\"version\":1,\"files\":[\"models/annotated.3md\",\"models/plain.3md\"],\"cell\":{\"x\":0,\"y\":0,\"z\":0},\"expectedScene\":\"expected.3md\"}"
        )
        let receipt = try fixture.receipt(fixture.portable(["native.3md", "request.json", "out.3md"]))
        #expect(receipt["storage"] as? String == "portable" && receipt["revisionUTF8Bytes"] is Int)
        let reopened = try SculptureThreeMDCodec.decode(Data(contentsOf: fixture.file("out.3md")))
        guard case .composition(let inserted) = reopened.scene else { Issue.record("Expected a composition"); return }
        #expect(inserted.models.count == 3)
        // The annotated child's own plane identities survive in the output beside the plain child.
        let child = try DocumentStorageCodec.decode(Data(contentsOf: fixture.file("models/annotated.3md")))
        let childIDs = Set(child.planes.compactMap(\.stableID))
        let graph = try DocumentCompositionCodec.decode(Data(reopened.revision.canonicalContent.utf8))
        let outputIDs = Set(graph.entries.flatMap { $0.document.planes.compactMap(\.stableID) })
        #expect(!childIDs.isEmpty && childIDs.isSubset(of: outputIDs))

        // A native input with only plain children yields a fresh portable capture, not a false refusal.
        try fixture.request(
            "{\"version\":1,\"files\":[\"models/plain.3md\"],\"cell\":{\"x\":0,\"y\":0,\"z\":0},\"expectedScene\":\"expected.3md\"}"
        )
        let plain = try fixture.receipt(fixture.portable(["native.3md", "request.json", "plain-out.3mdb"]))
        #expect(plain["kind"] as? String == "composition" && fixture.exists("plain-out.3mdb"))
        #expect(plain["portableDataNotCarried"] == nil)
    }

    @Test func aNativeInputTooLargeForAPortableCopyIsRefusedNamingItAndPointingToReferenceInsert() throws {
        let fixture = try InsertFixture()
        defer { fixture.clean() }
        let dimension = Sculpture.maximumDimension
        let root = try SculptureTileMap(
            width: dimension,
            height: dimension,
            layers: Array(repeating: Array(repeating: Sculpture.empty, count: dimension * dimension), count: dimension),
            tileSize: .init(width: 1, height: 1, depth: 1),
            bindings: []
        )
        let huge = try SculptureComposition(title: "Huge native", rootID: "root", models: ["root": .tiles(root)])
        try fixture.writeNative(.composition(huge), as: "huge.3md")
        try fixture.write(Data(contentsOf: fixture.file("huge.3md")), "expected.3md")
        try SculptureCodec.encode(InsertFixture.leaf("Tiny")).write(to: fixture.file("models/tiny.3md"))
        try fixture.request(
            "{\"version\":1,\"files\":[\"models/tiny.3md\"],\"cell\":{\"x\":0,\"y\":0,\"z\":0},\"expectedScene\":\"expected.3md\"}"
        )
        let message = fixture.message { try fixture.portable(["huge.3md", "request.json", "huge-out.3md"]) }
        #expect(message.hasPrefix("huge.3md:") && message.contains("sculpture reference insert"))
        #expect(!message.contains("definitionBytesExceeded") && !fixture.exists("huge-out.3md"))
        // The native command inserts into the same input without any portable copy.
        try fixture.request("{\"version\":1,\"files\":[\"models/tiny.3md\"],\"cell\":{\"x\":0,\"y\":0,\"z\":0}}")
        let receipt = try fixture.receipt(fixture.reference(["huge.3md", "request.json", "huge-native.3md"]))
        #expect(receipt["storage"] as? String == "native" && fixture.exists("huge-native.3md"))
    }

    @Test func inputAndExpectedSceneFailuresNameTheirFile() throws {
        let fixture = try InsertFixture()
        defer { fixture.clean() }
        try Data("not a scene".utf8).write(to: fixture.file("broken.3md"))
        _ = try fixture.writePortable(.composition(InsertFixture.composition()), as: "source.3md")
        try SculptureCodec.encode(InsertFixture.leaf("One")).write(to: fixture.file("models/one.3md"))
        try fixture.request(
            "{\"version\":1,\"files\":[\"models/one.3md\"],\"cell\":{\"x\":0,\"y\":0,\"z\":0},\"expectedScene\":\"broken.3md\"}"
        )
        let expected = fixture.message { try fixture.portable(["source.3md", "request.json", "out.3md"]) }
        #expect(expected.hasPrefix("broken.3md:") && expected.count > "broken.3md: ".count)
        let input = fixture.message { try fixture.portable(["broken.3md", "request.json", "out.3md"]) }
        #expect(input.hasPrefix("broken.3md:") && input.count > "broken.3md: ".count)
        try fixture.request("{\"version\":1,\"files\":[\"models/one.3md\"],\"cell\":{\"x\":0,\"y\":0,\"z\":0}}")
        let reference = fixture.message { try fixture.reference(["broken.3md", "request.json", "native-out.3md"]) }
        #expect(reference.contains("broken.3md"))
        #expect(!fixture.exists("out.3md") && !fixture.exists("native-out.3md"))
    }

    @Test func graphLimitsHitAfterReadingNameEveryListedFile() throws {
        let fixture = try InsertFixture()
        defer { fixture.clean() }
        // A 16-model dependency chain placed under the parent's root makes a 17-node path, past the limit of 16.
        var models: [String: SculptureCompositionModel] = [:]
        for index in 0..<16 {
            let id = String(format: "m%02d", index)
            models[id] =
                index == 15
                ? .sculpture(try InsertFixture.leaf("Chain end"))
                : .tiles(
                    try SculptureTileMap(
                        width: 1,
                        height: 1,
                        layers: [[65]],
                        tileSize: .init(width: 1, height: 1, depth: 1),
                        bindings: [try .init(glyph: 65, modelID: String(format: "m%02d", index + 1))]
                    )
                )
        }
        let chain = try SculptureComposition(title: "Chain", rootID: "m00", models: models)
        try SculptureCompositionCodec.encode(chain).write(to: fixture.file("models/chain.3md"))
        try SculptureCodec.encode(InsertFixture.leaf("Fine")).write(to: fixture.file("models/fine.3md"))
        try fixture.writeNative(.composition(InsertFixture.composition()), as: "map.3md")
        try fixture.request(
            "{\"version\":1,\"files\":[\"models/fine.3md\",\"models/chain.3md\"],\"cell\":{\"x\":0,\"y\":0,\"z\":0}}"
        )
        let message = fixture.message { try fixture.reference(["map.3md", "request.json", "chain-out.3md"]) }
        #expect(message.hasPrefix("Refusing to insert models/fine.3md, models/chain.3md:"))
        #expect(message.contains("exceeds 16") && !fixture.exists("chain-out.3md"))
    }

    @Test func theResolvedVolumeBudgetRefusesByNameBeforeAnyHugeFileIsDecoded() throws {
        let fixture = try InsertFixture()
        defer { fixture.clean() }
        func volumeModel() throws -> SculptureCompositionModel {
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
        var models: [String: SculptureCompositionModel] = [:]
        for id in ["root", "a", "b", "c"] { models[id] = try volumeModel() }
        let library = try SculptureComposition(title: "Full volume", rootID: "root", models: models)
        let world = try SculptureWorld(title: "Full world", library: library, instances: [])
        try fixture.writeNative(.world(world), as: "world.3md")
        let compact = try SculptureBinaryCodec.encode(InsertFixture.leaf("Tiny"))
        var claimed = compact
        for offset in stride(from: 12, to: 18, by: 2) { claimed[offset] = 0; claimed[offset + 1] = 1 }
        // Only a header and a title: decoding would fail, so a volume refusal proves nothing was decoded.
        try Data(claimed.prefix(60 + 4)).write(to: fixture.file("models/huge.3mdb"))
        try SculptureCodec.encode(InsertFixture.leaf("Leaf")).write(to: fixture.file("models/leaf.3md"))
        try fixture.request(
            "{\"version\":1,\"files\":[\"models/huge.3mdb\",\"models/leaf.3md\"],\"focus\":{\"x\":\"0\",\"y\":\"0\",\"z\":\"0\"}}"
        )
        let header = fixture.message { try fixture.reference(["world.3md", "request.json", "world-out.3md"]) }
        #expect(header.hasPrefix("models/huge.3mdb would push the combined model volumes"))
        #expect(header.contains("64 MiB"))
        try fixture.request(
            "{\"version\":1,\"files\":[\"models/leaf.3md\"],\"focus\":{\"x\":\"0\",\"y\":\"0\",\"z\":\"0\"}}"
        )
        let decoded = fixture.message { try fixture.reference(["world.3md", "request.json", "world-out.3md"]) }
        #expect(decoded.hasPrefix("models/leaf.3md would push the combined model volumes"))
        #expect(!fixture.exists("world-out.3md"))
    }

    @Test func referenceReceiptNamesChildrenWhosePortableDataWasNotCarried() throws {
        let fixture = try InsertFixture()
        defer { fixture.clean() }
        try fixture.writeNative(.composition(InsertFixture.composition()), as: "map.3md")
        let annotated = try SculptureThreeMDCodec.capture(.voxels(InsertFixture.leaf("Annotated", glyph: 64)))
        try SculptureThreeMDCodec.encode(annotated).write(to: fixture.file("models/annotated.3md"))
        try SculptureCodec.encode(InsertFixture.leaf("Plain")).write(to: fixture.file("models/plain.3md"))
        try fixture.request(
            "{\"version\":1,\"files\":[\"models/annotated.3md\",\"models/plain.3md\"],\"cell\":{\"x\":0,\"y\":0,\"z\":0}}"
        )
        let receipt = try fixture.receipt(fixture.reference(["map.3md", "request.json", "out.3md"]))
        #expect(receipt["portableDataNotCarried"] as? [String] == ["models/annotated.3md"])
    }

    @Test func cancellationBeforePublicationLeavesNoFile() async throws {
        let fixture = try InsertFixture()
        defer { fixture.clean() }
        _ = try fixture.writePortable(.composition(InsertFixture.composition()), as: "source.3md")
        try fixture.write(Data(contentsOf: fixture.file("source.3md")), "expected.3md")
        try SculptureCodec.encode(InsertFixture.leaf("One")).write(to: fixture.file("models/one.3md"))
        try fixture.request(
            "{\"version\":1,\"files\":[\"models/one.3md\"],\"cell\":{\"x\":0,\"y\":0,\"z\":0},\"expectedScene\":\"expected.3md\"}"
        )
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return try fixture.portable(["source.3md", "request.json", "cancelled.3md"])
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch { #expect(error is CancellationError) }
        #expect(!fixture.exists("cancelled.3md"))
    }
}

extension InsertFixture {
    func writeNative(_ scene: SculptureScene, as name: String) throws {
        switch scene {
        case .composition(let value): try write(SculptureCompositionCodec.encode(value), name)
        case .world(let value): try write(SculptureWorldCodec.encode(value), name)
        case .voxels(let value): try write(SculptureCodec.encode(value), name)
        }
    }
}
