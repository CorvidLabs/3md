import Foundation
import RookSculpture
import Testing

struct SculptureWorldTests {
    @Test func distantInstancesRemainSparseAndShareOneLibraryModel() throws {
        let library = try sampleLibrary()
        let world = try SculptureWorld(
            title: "Distant places",
            library: library,
            instances: [
                instance("west", x: -1_000_000_000_000_000, y: 24, z: 9),
                instance("east", x: 1_000_000_000_000_000, y: -24, z: -9, turns: 3),
            ]
        )
        #expect(world.library == library)
        #expect(world.instances.count == 2 && world.library.models.count == 2)
        #expect(world.instances[0].modelID == world.instances[1].modelID)
        let data = try SculptureWorldCodec.encode(world)
        #expect(data.count < 100_000)
        #expect(SculptureWorldCodec.isWorld(data))
        #expect(!SculptureCompositionCodec.isComposition(data))
        #expect(try SculptureWorldCodec.decode(data) == world)
        #expect(try SculptureWorldCodec.encode(SculptureWorldCodec.decode(data)) == data)
    }

    @Test func exactInt64ExtremesAndAdjacentAnchorsSurviveJSONRoundTrip() throws {
        let maximum = Int64.max - 256
        let anchors = [
            SculptureWorldPoint(x: maximum, y: Int64.min, z: -1_000_000_000_000_001),
            SculptureWorldPoint(x: maximum - 1, y: Int64.min + 1, z: -1_000_000_000_000_000),
            SculptureWorldPoint(x: 9_007_199_254_740_993, y: -9_007_199_254_740_993, z: 0),
        ]
        let instances = try anchors.enumerated().map { index, origin in
            try SculptureWorldInstance(id: "anchor-\(index)", modelID: "leaf", origin: origin, quarterTurns: index)
        }
        let world = try SculptureWorld(title: "Exact anchors", library: sampleLibrary(), instances: instances)
        let reopened = try SculptureWorldCodec.decode(SculptureWorldCodec.encode(world))
        #expect(reopened.instances.map(\.origin) == anchors)
        #expect(reopened.instances[0].origin.x - reopened.instances[1].origin.x == 1)
        #expect(reopened.instances[1].origin.y - reopened.instances[0].origin.y == 1)
        let set = Set(anchors)
        #expect(set.count == 3)
        #expect(
            try JSONDecoder().decode(SculptureWorldPoint.self, from: JSONEncoder().encode(anchors[0])) == anchors[0]
        )
    }

    @Test func originHeadroomIDsAndRotationsAreValidatedBeforeWorldConstruction() throws {
        let maximum = Int64.max - 256
        let accepted = try instance("edge", x: maximum, y: maximum, z: maximum)
        #expect(accepted.origin.x == maximum)
        for origin in [
            SculptureWorldPoint(x: maximum + 1, y: 0, z: 0),
            SculptureWorldPoint(x: 0, y: Int64.max, z: 0),
            SculptureWorldPoint(x: 0, y: 0, z: Int64.max),
        ] {
            #expect(throws: SculptureWorldError.invalidOrigin) {
                try SculptureWorldInstance(id: "edge", modelID: "leaf", origin: origin)
            }
        }
        #expect(throws: SculptureWorldError.invalidID("../outside")) {
            try SculptureWorldInstance(id: "../outside", modelID: "leaf", origin: .init(x: 0, y: 0, z: 0))
        }
        #expect(throws: SculptureWorldError.invalidID("/tmp/model")) {
            try SculptureWorldInstance(id: "safe", modelID: "/tmp/model", origin: .init(x: 0, y: 0, z: 0))
        }
        #expect(throws: SculptureWorldError.invalidRotation) { try instance("turn", turns: -1) }
        #expect(throws: SculptureWorldError.invalidRotation) { try instance("turn", turns: 4) }
    }

    @Test func worldsRejectMissingModelsDuplicateInstancesAndInvalidTitles() throws {
        let library = try sampleLibrary()
        let repeated = try instance("same")
        #expect(throws: SculptureWorldError.duplicateInstance("same")) {
            try SculptureWorld(title: "Duplicates", library: library, instances: [repeated, repeated])
        }
        let missing = try SculptureWorldInstance(id: "missing", modelID: "absent", origin: .init(x: 0, y: 0, z: 0))
        #expect(throws: SculptureWorldError.unknownModel("absent")) {
            try SculptureWorld(title: "Missing", library: library, instances: [missing])
        }
        #expect(throws: SculptureWorldError.invalidTitle) {
            try SculptureWorld(title: "", library: library, instances: [])
        }
        let empty = try SculptureWorld(title: "Empty", library: library, instances: [])
        #expect(try SculptureWorldCodec.decode(SculptureWorldCodec.encode(empty)) == empty)
    }

    @Test func finitePlacementCapacityDoesNotImposeASpatialExtent() throws {
        let library = try sampleLibrary()
        var instances = try (0..<SculptureWorld.maximumInstances).map { index in
            try instance("item-\(index)", x: Int64(index) * 1_000_000_000_000, z: -Int64(index))
        }
        let world = try SculptureWorld(title: "Exact capacity", library: library, instances: instances)
        #expect(world.instances.count == 65_536)
        let data = try SculptureWorldCodec.encode(world)
        #expect(data.count < SculptureWorldCodec.maximumBytes)
        #expect(try SculptureWorldCodec.decode(data).instances == instances)
        instances.append(try instance("overflow", x: Int64.min))
        #expect(throws: SculptureWorldError.tooManyInstances) {
            try SculptureWorld(title: "Over capacity", library: library, instances: instances)
        }
    }

    @Test func codecRejectsUnknownDuplicateMetadataAndUnsupportedPlaneOrFences() throws {
        let source = String(decoding: try SculptureWorldCodec.encode(sampleWorld()), as: UTF8.self)
        for malformed in [
            source.replacingOccurrences(
                of: "scene-schema: ascii-world-1",
                with: "scene-schema: ascii-world-1\nunknown: ignored"
            ),
            source.replacingOccurrences(of: "axis: space", with: "axis: space\naxis: space"),
            source.replacingOccurrences(of: "3md: 1.0", with: "3md: 2.0"),
            source.replacingOccurrences(of: "@plane z=0", with: "@plane z=1"),
            source.replacingOccurrences(of: "@plane z=0", with: "@plane z=0 z=0"),
            source.replacingOccurrences(of: "@plane z=0", with: "@plane z=0 x=0"),
            source.replacingOccurrences(of: "label=\"World\"", with: "label=\"Other\""),
            source.replacingOccurrences(of: "```json", with: "```unknown"),
        ] {
            #expect(throws: SculptureWorldError.self) { try SculptureWorldCodec.decode(Data(malformed.utf8)) }
        }
        #expect(throws: SculptureWorldError.unsupportedPlane) {
            try SculptureWorldCodec.decode(Data((source + "@plane z=1 label=\"World\"\n```json\n{}\n```\n").utf8))
        }
        let withBOM = Data([0xEF, 0xBB, 0xBF]) + Data(source.utf8)
        #expect(SculptureWorldCodec.isWorld(withBOM))
        #expect(try SculptureWorldCodec.decode(withBOM) == sampleWorld())
        #expect(!SculptureWorldCodec.isWorld(try SculptureCompositionCodec.encode(sampleLibrary())))
    }

    @Test func codecRejectsUnknownDuplicateJSONKeysAndInexactCoordinateTypes() throws {
        let library = try quotedLibrary()
        let record = "{\"id\":\"a\",\"modelID\":\"leaf\",\"x\":0,\"y\":0,\"z\":0,\"quarterTurns\":0}"
        for envelope in [
            "{\"version\":1,\"library\":\(library),\"instances\":[],\"unknown\":true}",
            "{\"version\":1,\"version\":1,\"library\":\(library),\"instances\":[]}",
            "{\"version\":2,\"library\":\(library),\"instances\":[]}",
            "{\"version\":1,\"library\":\(library),\"instances\":[\(record.replacingOccurrences(of: "\"x\":0", with: "\"x\":0,\"x\":1"))]}",
            "{\"version\":1,\"library\":\(library),\"instances\":[\(record.replacingOccurrences(of: "\"x\":0", with: "\"x\":0,\"path\":\"external\""))]}",
            "{\"version\":1,\"library\":\(library),\"instances\":[\(record.replacingOccurrences(of: "\"x\":0", with: "\"x\":9223372036854775808"))]}",
            "{\"version\":1,\"library\":\(library),\"instances\":[\(record.replacingOccurrences(of: "\"x\":0", with: "\"x\":0.25"))]}",
        ] {
            #expect(throws: SculptureWorldError.invalidEnvelope) { try SculptureWorldCodec.decode(document(envelope)) }
        }
        #expect(throws: SculptureWorldError.duplicateInstance("a")) {
            try SculptureWorldCodec.decode(
                document("{\"version\":1,\"library\":\(library),\"instances\":[\(record),\(record)]}")
            )
        }
        #expect(throws: SculptureWorldError.invalidLibrary) {
            try SculptureWorldCodec.decode(
                document("{\"version\":1,\"library\":\"not a composition\",\"instances\":[]}")
            )
        }
    }

    @Test func decoderBoundsBytesPhysicalLinesAndJSONNestingBeforeAllocatingModels() throws {
        #expect(throws: SculptureWorldError.oversizedFile) {
            try SculptureWorldCodec.decode(Data(repeating: 32, count: SculptureWorldCodec.maximumBytes + 1))
        }
        #expect(throws: SculptureWorldError.unsupportedSchema) {
            try SculptureWorldCodec.decode(Data(repeating: 10, count: 100_001))
        }
        #expect(throws: SculptureWorldError.invalidEnvelope) {
            try SculptureWorldCodec.decode(document("{\"version\":1,\"library\":\"\",\"instances\":[[[[[[]]]]]]}"))
        }
        #expect(throws: SculptureWorldError.unsupportedSchema) {
            try SculptureWorldCodec.decode(Data([255, 254, 253]))
        }
    }

    @Test func cancellationReturnsNoWorldOrSerializedOutput() async throws {
        let world = try sampleWorld()
        let data = try SculptureWorldCodec.encode(world)
        for operation in 0..<3 {
            let gate = WorldCancellationGate()
            let task = Task {
                await gate.wait()
                switch operation {
                case 0: _ = try SculptureWorldCodec.encode(world)
                case 1: _ = try SculptureWorldCodec.decode(data)
                default: _ = try SculptureWorld(title: world.title, library: world.library, instances: world.instances)
                }
            }
            task.cancel()
            await gate.release()
            await #expect(throws: CancellationError.self) { try await task.value }
        }
    }

    private func sampleLibrary() throws -> SculptureComposition {
        let leaf = try Sculpture(title: "Corner", width: 2, height: 2, layers: [[35, 64, 111, 46]])
        let root = try SculptureTileMap(
            width: 1,
            height: 1,
            layers: [[65]],
            tileSize: .init(width: 2, height: 2, depth: 1),
            bindings: [.init(glyph: 65, modelID: "leaf")]
        )
        return try SculptureComposition(
            title: "Shared library",
            rootID: "root",
            models: ["root": .tiles(root), "leaf": .sculpture(leaf)]
        )
    }

    private func sampleWorld() throws -> SculptureWorld {
        try SculptureWorld(
            title: "World",
            library: sampleLibrary(),
            instances: [instance("a"), instance("b", x: 512, turns: 1)]
        )
    }

    private func instance(_ id: String, x: Int64 = 0, y: Int64 = 0, z: Int64 = 0, turns: Int = 0) throws
        -> SculptureWorldInstance
    {
        try SculptureWorldInstance(id: id, modelID: "leaf", origin: .init(x: x, y: y, z: z), quarterTurns: turns)
    }

    private func quotedLibrary() throws -> String {
        let source = String(decoding: try SculptureCompositionCodec.encode(sampleLibrary()), as: UTF8.self)
        return String(decoding: try JSONEncoder().encode(source), as: UTF8.self)
    }

    private func document(_ envelope: String) -> Data {
        Data(
            "---\n3md: 1.0\naxis: space\ntitle: World\nscene-schema: ascii-world-1\n---\n\n@plane z=0 label=\"World\"\n```json\n\(envelope)\n```\n"
                .utf8
        )
    }
}

private actor WorldCancellationGate {
    private var released = false
    private var waiter: CheckedContinuation<Void, Never>?
    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func release() { released = true; waiter?.resume(); waiter = nil }
}
