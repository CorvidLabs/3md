import Foundation
import Testing
import ThreeMD

@testable import RookSculpture

struct SculptureLinkedCodecTests {
    @Test func ledgerIsSingleLineSortedJSONThatRoundTripsQuotesBackslashesAndNFCPaths() throws {
        let files = [
            "\"": "models/quote.3md",
            "\\": "models/backslash.3md",
            "A": "modèles/tête.3md",
            "a": "模型/椅子.3md",
            "~": "../shared/leaf.3md",
        ]
        let value = try SculptureLinkedCodec.ledgerValue(for: files)
        #expect(!value.contains("\n") && !value.contains("\r"))
        #expect(value.contains("models/quote.3md") && !value.contains("\\/"))
        #expect(value.contains("\"\\\"\":\"models/quote.3md\""))
        #expect(value.contains("\"\\\\\":\"models/backslash.3md\""))
        #expect(try SculptureLinkedCodec.ledgerValue(for: files) == value)
        // The defined key order is Foundation's sorted-keys order, independent of the user's locale.
        let encoder = try JSONSerialization.data(
            withJSONObject: files,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        #expect(value == String(decoding: encoder, as: UTF8.self))
        let probe = Document(version: "1.0", axis: .space, metadata: ["3md-files": value], planes: [])
        let references = try DocumentFileComposition.ledger(in: probe)
        #expect(Dictionary(uniqueKeysWithValues: references.map { ($0.glyph, $0.source) }) == files)
        #expect(references.map(\.glyph) == ["\"", "A", "\\", "a", "~"])
        // The ledger survives the canonical readable writer and parser unchanged.
        let text = try LinkedFixture.document(metadata: ["3md-files": value], planes: [])
        #expect(try DocumentStorageCodec.decode(text).metadata["3md-files"] == value)
    }

    @Test func ledgerRefusesSpacesPeriodsMultiCharacterKeysAndEmptyPaths() throws {
        for files in [[" ": "a.3md"], [".": "a.3md"], ["ab": "a.3md"], ["é": "a.3md"], ["#": ""]] {
            #expect(throws: SculptureLinkedError.self) { try SculptureLinkedCodec.ledgerValue(for: files) }
        }
        #expect(try SculptureLinkedCodec.ledgerValue(for: [:]) == "{}")
    }

    @Test func linkedRootRoundTripsExactlyWithTurnsAndFenceLikeRows() throws {
        let tile = try SculptureTileSize(width: 2, height: 3, depth: 4)
        let backtick = UInt8(ascii: "`")
        let composition = try SculptureLinkedComposition(
            title: "Linked \"hall\" \\ study",
            width: 3,
            height: 2,
            tileSize: tile,
            layers: [[backtick, backtick, backtick, 35, 46, 64], [46, 46, 46, 46, 46, 46]],
            files: [backtick: "fence.3md", 35: "models/hash.3md", 64: "../at.3md", 33: "unplaced.3md"],
            quarterTurns: [35: 1, 64: 3]
        )
        let data = try SculptureLinkedCodec.encode(composition)
        #expect(try SculptureLinkedCodec.decode(data) == composition)
        #expect(try SculptureLinkedCodec.encode(SculptureLinkedCodec.decode(data)) == data)
        #expect(SculptureLinkedCodec.isLinked(data))
        let document = try DocumentStorageCodec.decode(data)
        #expect(
            Set(document.metadata.keys) == [
                "scene-schema", "width", "height", "tile-width", "tile-height", "tile-depth", "3md-files",
                "sculpt-turns",
            ]
        )
        #expect(document.metadata["scene-schema"] == "ascii-linked-composition-1")
        let turns = try #require(document.metadata["sculpt-turns"])
        #expect(!turns.contains("\n") && turns.contains("\"#\":1") && turns.contains("\"@\":3"))
        #expect(try SculptureLinkedCodec.quarterTurns(turns) == [35: 1, 64: 3])
        #expect(document.planes.first?.body.hasPrefix("```json\n") == true)
        #expect(document.planes.last?.body.hasPrefix("```ascii\n") == true)
        // The canonical writer sorts the ledger before the schema, which is why detection reads all frontmatter.
        let text = String(decoding: data, as: UTF8.self)
        let ledgerIndex = try #require(text.range(of: "3md-files")).lowerBound
        let schemaIndex = try #require(text.range(of: "scene-schema")).lowerBound
        #expect(ledgerIndex < schemaIndex)
        let unrotated = try LinkedFixture.linked(files: ["#": "leaf.3md"])
        let plain = try DocumentStorageCodec.decode(SculptureLinkedCodec.encode(unrotated))
        #expect(plain.metadata["sculpt-turns"] == nil)
        #expect(plain.metadata["3md-files"] == "{\"#\":\"leaf.3md\"}")
    }

    @Test func everyPlacedByteMustBeLinkedAndLinkCharactersExcludeSpacesAndPeriods() throws {
        let tile = try SculptureTileSize(width: 1, height: 1, depth: 1)
        #expect(throws: SculptureLinkedError.self) {
            try SculptureLinkedComposition(
                title: "Unlinked",
                width: 2,
                height: 1,
                tileSize: tile,
                layers: [[35, 64]],
                files: [35: "leaf.3md"]
            )
        }
        for glyph: UInt8 in [32, 46, 127, 200] {
            #expect(throws: SculptureLinkedError.self) {
                try SculptureLinkedComposition(
                    title: "Bad glyph",
                    width: 1,
                    height: 1,
                    tileSize: tile,
                    layers: [[46]],
                    files: [glyph: "leaf.3md"]
                )
            }
        }
        for turns in [[UInt8(35): 0], [35: 4], [64: 1]] {
            #expect(throws: SculptureLinkedError.self) {
                try SculptureLinkedComposition(
                    title: "Bad turns",
                    width: 1,
                    height: 1,
                    tileSize: tile,
                    layers: [[35]],
                    files: [35: "leaf.3md"],
                    quarterTurns: turns
                )
            }
        }
        let empty = try SculptureLinkedComposition(
            title: "Empty",
            width: 1,
            height: 1,
            tileSize: tile,
            layers: [[46]],
            files: [:]
        )
        #expect(try SculptureLinkedCodec.decode(SculptureLinkedCodec.encode(empty)) == empty)
    }

    @Test func decodingRequiresExactMetadataATitleAndNoPreamble() throws {
        let valid = try DocumentStorageCodec.decode(LinkedFixture.linkedData(files: ["#": "leaf.3md"]))
        var extra = valid.metadata
        extra["root-id"] = "root"
        var missing = valid.metadata
        missing.removeValue(forKey: "tile-depth")
        var dotted = valid.metadata
        dotted["3md-files"] = "{\".\":\"leaf.3md\",\"#\":\"leaf.3md\"}"
        var duplicate = valid.metadata
        duplicate["3md-files"] = "{\"#\":\"a.3md\",\"#\":\"b.3md\"}"
        var badTurns = valid.metadata
        badTurns["sculpt-turns"] = "{\"#\":2,\"#\":3}"
        var unplacedTurns = valid.metadata
        unplacedTurns["sculpt-turns"] = "{\"@\":2}"
        var hugeLedger = valid.metadata
        hugeLedger["3md-files"] = "{\"#\":" + String(repeating: " ", count: 131_072) + "\"leaf.3md\"}"
        let cases: [Data] = [
            try LinkedFixture.document(metadata: extra, planes: valid.planes),
            try LinkedFixture.document(metadata: missing, planes: valid.planes),
            try LinkedFixture.document(metadata: dotted, planes: valid.planes),
            try LinkedFixture.document(metadata: duplicate, planes: valid.planes),
            try LinkedFixture.document(metadata: badTurns, planes: valid.planes),
            try LinkedFixture.document(metadata: unplacedTurns, planes: valid.planes),
            try LinkedFixture.document(metadata: hugeLedger, planes: valid.planes),
            try LinkedFixture.document(title: nil, metadata: valid.metadata, planes: valid.planes),
            try LinkedFixture.document(metadata: valid.metadata, planes: valid.planes, preamble: "Notes"),
        ]
        for data in cases {
            #expect(SculptureLinkedCodec.isLinked(data))
            #expect(throws: SculptureLinkedError.self) { try SculptureLinkedCodec.decode(data) }
        }
        // A linked root is a version 1.0 space document. The parser reads a missing axis as layer.
        let text = String(decoding: try LinkedFixture.linkedData(files: ["#": "leaf.3md"]), as: UTF8.self)
        let version = "\n3md: \"1.0\"\n"
        let axis = "\naxis: \"space\"\n"
        #expect(text.contains(version) && text.contains(axis))
        let metadataCases = [
            ("axis time", text.replacingOccurrences(of: axis, with: "\naxis: \"time\"\n")),
            ("no axis", text.replacingOccurrences(of: axis, with: "\n")),
            ("version 2.0", text.replacingOccurrences(of: version, with: "\n3md: \"2.0\"\n")),
        ]
        for (name, changed) in metadataCases {
            let data = Data(changed.utf8)
            #expect(changed != text, "\(name) changed nothing")
            #expect(SculptureLinkedCodec.isLinked(data), "\(name) is still recognized")
            #expect(throws: SculptureLinkedError.self, "\(name) must be refused") {
                try SculptureLinkedCodec.decode(data)
            }
            #expect(throws: SculptureLinkedError.self, "\(name) must be refused as a project file") {
                try SculptureLinkedResolver.classify(path: "root.3md", data: data, limits: .standard)
            }
        }
        #expect(try DocumentStorageCodec.decode(Data(metadataCases[1].1.utf8)).axis == .layer)
        #expect(try DocumentStorageCodec.decode(Data(metadataCases[2].1.utf8)).version == "2.0")

        let attributed = valid.planes.map {
            Plane(z: $0.z, label: $0.label, attributes: ["note": "x"], body: $0.body)
        }
        #expect(throws: SculptureCompositionError.unsupportedPlane) {
            try SculptureLinkedCodec.decode(LinkedFixture.document(metadata: valid.metadata, planes: attributed))
        }
    }

    @Test func sceneReaderAsksForAProjectFolderAfterExistingKindsAndRefusesBinaryRootsByName() throws {
        let readable = try LinkedFixture.linkedData(files: ["#": "leaf.3md"])
        #expect(throws: SculptureLinkedError.needsProjectFolder) { try SculptureSceneReader.decode(readable) }
        let document = try DocumentStorageCodec.decode(readable)
        var compressions: [DocumentCompression] = [.none]
        #if canImport(Compression)
        compressions.append(.lzfse)
        #endif
        for compression in compressions {
            let binary = try DocumentStorageCodec.encode(document, format: .binary(compression: compression))
            #expect(!SculptureLinkedCodec.isLinked(binary))
            #expect(throws: SculptureLinkedError.binaryLinkedRoot) { try SculptureSceneReader.decode(binary) }
            #expect(throws: SculptureLinkedError.binaryLinkedRoot) { try SculptureLinkedCodec.decode(binary) }
        }
        #expect(
            SculptureLinkedError.needsProjectFolder.localizedDescription
                == "This linked composition reads its models from files in a project folder. Open it and choose that folder."
        )
        // Plain insertion of a linked root is refused naming the selected file.
        #expect(
            throws: SculptureInsertionError.source(
                name: "room.3md",
                reason: SculptureLinkedError.needsProjectFolder.localizedDescription
            )
        ) {
            try SculptureInsertionPlan.decode(readable, source: "room.3md")
        }
    }

    @Test func detectionScansTheWholeFrontmatterBeyondTheExistingPrefixWindow() throws {
        let long = String(repeating: "f", count: 200) + "/" + String(repeating: "g", count: 100) + "/leaf-"
        var files: [Character: String] = [:]
        for (offset, glyph) in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789".enumerated() {
            files[glyph] = long + "\(offset).3md"
        }
        let data = try LinkedFixture.linkedData(files: files)
        let text = String(decoding: data, as: UTF8.self)
        let schemaOffset = text.utf8.distance(
            from: text.startIndex,
            to: text.range(of: "scene-schema")?.lowerBound ?? text.startIndex
        )
        #expect(schemaOffset > 16_384)
        #expect(!SculptureCompositionCodec.isComposition(data) && !SculptureWorldCodec.isWorld(data))
        #expect(!SculptureThreeMDCodec.isPortable(data))
        #expect(SculptureLinkedCodec.isLinked(data))
        #expect(throws: SculptureLinkedError.needsProjectFolder) { try SculptureSceneReader.decode(data) }
        let outside = Data("---\n3md: \"1.0\"\naxis: \"space\"\n---\nscene-schema: ascii-linked-composition-1\n".utf8)
        #expect(!SculptureLinkedCodec.isLinked(outside))

        // The scan is bounded: a schema line that ends inside the window is found, one that starts past it is not.
        let header = "---\n3md: 1.0\naxis: space\n"
        let schemaLine = "scene-schema: ascii-linked-composition-1\n"
        let window = SculptureLinkedCodec.maximumDetectionBytes
        let filler = window - header.utf8.count - schemaLine.utf8.count - "pad: \n".utf8.count
        let inside = header + "pad: " + String(repeating: "x", count: filler) + "\n" + schemaLine
        #expect(inside.utf8.count == window)
        #expect(SculptureLinkedCodec.isLinked(Data((inside + "---\n").utf8)))
        let beyond = header + "pad: " + String(repeating: "x", count: window) + "\n" + schemaLine + "---\n"
        let beyondSchema = try #require(beyond.range(of: "scene-schema")).lowerBound
        #expect(beyond.utf8.distance(from: beyond.startIndex, to: beyondSchema) > window)
        #expect(!SculptureLinkedCodec.isLinked(Data(beyond.utf8)))
        #expect(
            !SculptureLinkedCodec.isLinked(Data("Notes\n---\nscene-schema: ascii-linked-composition-1\n---\n".utf8))
        )
    }

    @Test func linkedErrorMessagesNameProjectPathsAndLimits() {
        let messages: [(SculptureLinkedError, String)] = [
            (
                .limit(kind: .pathBytes, maximum: 1_024, path: "root.3md"),
                "Linked composition limit reached at root.3md: at most 1,024 bytes in a project path."
            ),
            (
                .limit(kind: .definitionBytes, maximum: 16 * 1_048_576, path: "a/leaf.3md"),
                "Linked composition limit reached at a/leaf.3md: at most 16 MiB of linked files."
            ),
            (
                .limit(kind: .ledgerBytes, maximum: 131_072, path: "root.3md"),
                "Linked composition limit reached at root.3md: at most 128 KiB in one 3md-files ledger."
            ),
            (
                .missingFile(path: "models/gone.3md", linkedFrom: "scenes/root.3md"),
                "scenes/root.3md links models/gone.3md, which is not in the project folder."
            ),
            (
                .invalidPath(link: "../../x.3md", linkedFrom: "root.3md"),
                "root.3md links \"../../x.3md\", which is not a valid path inside the project folder."
            ),
            (
                .unsupportedChild(path: "w.3md", kind: .world),
                "w.3md is a sparse world. Link readable ascii-sculpture-1 voxel files, uncompressed binary voxel "
                    + "files or other linked compositions."
            ),
            (.file(path: "a.3md", reason: "could not be read."), "a.3md: could not be read."),
        ]
        for (error, message) in messages {
            #expect(error.localizedDescription == message)
            #expect(SculptureDiagnosticMessage.describe(error) == message)
        }
        #expect(SculptureLinkedLimit.allCases.allSatisfy { !$0.describe(1).isEmpty })
        #expect(SculptureLinkedFileKind.allCases.allSatisfy { !$0.description.isEmpty })
    }

    @Test func existingKindsKeepTheirDetectionAndMessages() throws {
        let voxel = try LinkedFixture.voxel(width: 2)
        let composition = try SculptureComposition(
            title: "Native",
            rootID: "root",
            models: [
                "root": .tiles(
                    try SculptureTileMap(
                        width: 1,
                        height: 1,
                        layers: [[65]],
                        tileSize: .init(width: 2, height: 1, depth: 1),
                        bindings: [.init(glyph: 65, modelID: "leaf")]
                    )
                ),
                "leaf": .sculpture(voxel),
            ]
        )
        let world = try SculptureWorld(title: "World", library: composition, instances: [])
        #expect(try SculptureSceneReader.decode(SculptureCodec.encode(voxel)).scene == .voxels(voxel))
        #expect(try SculptureSceneReader.decode(SculptureBinaryCodec.encode(voxel)).scene == .voxels(voxel))
        #expect(
            try SculptureSceneReader.decode(SculptureCompositionCodec.encode(composition)).scene
                == .composition(composition)
        )
        #expect(try SculptureSceneReader.decode(SculptureWorldCodec.encode(world)).scene == .world(world))
        let portable = try SculptureThreeMDCodec.capture(.composition(composition))
        #expect(
            try SculptureSceneReader.decode(SculptureThreeMDCodec.encode(portable)).scene == .composition(composition)
        )
        #expect(throws: SculptureError.unsupportedSchema) {
            try SculptureSceneReader.decode(Data("---\n3md: 1.0\naxis: space\n---\nHello\n".utf8))
        }
        let unmarked = try DocumentStorageCodec.encode(
            Document(version: "1.0", axis: .space, metadata: ["scene-schema": "other"], planes: []),
            format: .binary(compression: .none)
        )
        #expect(throws: SculptureError.unsupportedSchema) { try SculptureSceneReader.decode(unmarked) }
    }
}
