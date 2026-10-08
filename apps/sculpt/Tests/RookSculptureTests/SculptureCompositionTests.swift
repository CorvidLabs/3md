import Foundation
import RookSculpture
import Testing

struct SculptureCompositionTests {
    @Test func tileBlocksPreserveDepthPaddingAndAllFourRectangularRotations() throws {
        let leaf = try Sculpture(
            title: "Asymmetric",
            width: 2,
            height: 3,
            layers: [[35, 64, 42, 46, 43, 111], [46, 46, 46, 46, 46, 120]]
        )
        let bindings = try (0..<4).map {
            try SculptureModelBinding(glyph: UInt8(65 + $0), modelID: "leaf", quarterTurns: $0)
        }
        let root = try SculptureTileMap(
            width: 2,
            height: 1,
            layers: [[65, 66], [67, 68]],
            tileSize: .init(width: 3, height: 3, depth: 2),
            bindings: bindings
        )
        let composition = try SculptureComposition(
            title: "Four turns",
            rootID: "root",
            models: ["root": .tiles(root), "leaf": .sculpture(leaf)]
        )
        let output = try composition.expanded()
        #expect(output.width == 6 && output.height == 3 && output.depth == 4)
        #expect(output.title == "Four turns" && output.occupiedCount == 24)
        let first: [(x: Int, y: Int)] = [(0, 0), (2, 0), (1, 2), (0, 1)]
        let second: [(x: Int, y: Int)] = [(1, 0), (2, 1), (0, 2), (0, 0)]
        let deep: [(x: Int, y: Int)] = [(1, 2), (0, 1), (0, 0), (2, 0)]
        for turn in 0..<4 {
            let x = (turn % 2) * 3, z = (turn / 2) * 2
            #expect(output.glyph(at: .init(x: x + first[turn].x, y: first[turn].y, z: z)) == 35)
            #expect(output.glyph(at: .init(x: x + second[turn].x, y: second[turn].y, z: z)) == 64)
            #expect(output.glyph(at: .init(x: x + deep[turn].x, y: deep[turn].y, z: z + 1)) == 120)
        }
        #expect(output.glyph(at: .init(x: 2, y: 0, z: 0)) == Sculpture.empty)
        #expect(output.glyph(at: .init(x: 3, y: 2, z: 0)) == Sculpture.empty)
        #expect(try composition.expanded(modelID: "leaf") == leaf)
        #expect(try composition.expanded() == output)
    }

    @Test func nestedModelsResolveByGlobalIDAndPeriodsReserveEmptyBlocks() throws {
        let nested = try map(width: 2, rows: [[65, 66]], bindings: [binding(65, "stone"), binding(66, "metal")])
        let root = try SculptureTileMap(
            width: 3,
            height: 1,
            layers: [[78, 46, 78]],
            tileSize: .init(width: 3, height: 2, depth: 2),
            bindings: [binding(78, "nested", turns: 2)]
        )
        let composition = try SculptureComposition(
            title: "Nested blocks",
            rootID: "root",
            models: [
                "root": .tiles(root), "nested": .tiles(nested), "stone": .sculpture(unit()),
                "metal": .sculpture(unit(64)),
            ]
        )
        let output = try composition.expanded()
        #expect(output.width == 9 && output.height == 2 && output.depth == 2)
        #expect(output.occupiedCount == 4)
        #expect(output.layers[0] == [64, 35, 46, 46, 46, 46, 64, 35, 46] + Array(repeating: Sculpture.empty, count: 9))
        #expect(output.layers[1].allSatisfy { $0 == Sculpture.empty })
        let child = try composition.expanded(modelID: "nested")
        #expect(child.width == 2 && child.height == 1 && child.depth == 1)
        #expect(child.title == "nested" && child.layers == [[35, 64]])
        #expect(throws: SculptureCompositionError.unknownModel("absent")) {
            try composition.expanded(modelID: "absent")
        }
    }

    @Test func validationRejectsUnusedMissingReferencesAndCycles() throws {
        let empty = try map(width: 1, rows: [[46]], bindings: [])
        let missing = try map(width: 1, rows: [[46]], bindings: [binding(65, "missing")])
        #expect(throws: SculptureCompositionError.unknownModel("missing")) {
            try SculptureComposition(
                title: "Missing",
                rootID: "root",
                models: ["root": .tiles(empty), "unused": .tiles(missing)]
            )
        }
        let a = try map(width: 1, rows: [[46]], bindings: [binding(65, "b")])
        let b = try map(width: 1, rows: [[46]], bindings: [binding(66, "a")])
        #expect(throws: SculptureCompositionError.cyclicReference("a")) {
            try SculptureComposition(
                title: "Cycle",
                rootID: "root",
                models: ["root": .tiles(empty), "a": .tiles(a), "b": .tiles(b)]
            )
        }
    }

    @Test func invalidBindingsGridsIDsAndRootAreExplicitFailures() throws {
        for id in ["", "../leaf", "a/b", "a:b", "-leaf", "snow☃", String(repeating: "a", count: 49)] {
            #expect(throws: SculptureCompositionError.invalidID(id)) {
                try SculptureModelBinding(glyph: 65, modelID: id)
            }
        }
        #expect(throws: SculptureCompositionError.invalidBindingGlyph(46)) { try binding(46, "leaf") }
        #expect(throws: SculptureCompositionError.invalidBindingGlyph(255)) { try binding(255, "leaf") }
        #expect(throws: SculptureCompositionError.invalidRotation) { try binding(65, "leaf", turns: 4) }
        #expect(throws: SculptureCompositionError.duplicateBinding(65)) {
            try map(width: 1, rows: [[65]], bindings: [binding(65, "leaf"), binding(65, "other")])
        }
        #expect(throws: SculptureCompositionError.unboundGlyph(66)) {
            try map(width: 1, rows: [[66]], bindings: [binding(65, "leaf")])
        }
        #expect(throws: SculptureCompositionError.invalidGrid) {
            try map(width: 2, rows: [[65]], bindings: [binding(65, "leaf")])
        }
        #expect(throws: SculptureCompositionError.invalidRoot) {
            try SculptureComposition(title: "Leaf root", rootID: "leaf", models: ["leaf": .sculpture(unit())])
        }
        #expect(throws: SculptureCompositionError.invalidTitle) {
            try SculptureComposition(
                title: "",
                rootID: "root",
                models: ["root": .tiles(map(width: 1, rows: [[46]], bindings: []))]
            )
        }
    }

    @Test func dimensionsAndRotatedChildFitNeverCropOrOverflow() throws {
        #expect(throws: SculptureCompositionError.invalidDimensions) {
            try SculptureTileSize(width: Int.max, height: 1, depth: 1)
        }
        #expect(throws: SculptureCompositionError.invalidDimensions) {
            try SculptureTileMap(
                width: 129,
                height: 1,
                layers: [Array(repeating: Sculpture.empty, count: 129)],
                tileSize: .init(width: 2, height: 1, depth: 1),
                bindings: []
            )
        }
        let rectangular = try Sculpture(
            title: "Rectangle",
            width: 2,
            height: 3,
            layers: [Array(repeating: UInt8(35), count: 6)]
        )
        let root = try SculptureTileMap(
            width: 1,
            height: 1,
            layers: [[65]],
            tileSize: .init(width: 2, height: 3, depth: 1),
            bindings: [binding(65, "leaf", turns: 1)]
        )
        #expect(throws: SculptureCompositionError.childDoesNotFit("leaf")) {
            try SculptureComposition(
                title: "Too wide",
                rootID: "root",
                models: ["root": .tiles(root), "leaf": .sculpture(rectangular)]
            )
        }
    }

    @Test func modelAndDependencyDepthLimitsHaveAcceptedBoundaryCases() throws {
        let empty = try map(width: 1, rows: [[46]], bindings: [])
        let leaf = try unit()
        var models: [String: SculptureCompositionModel] = ["root": .tiles(empty)]
        for index in 0..<63 { models["leaf-\(index)"] = .sculpture(leaf) }
        #expect(try SculptureComposition(title: "64 models", rootID: "root", models: models).models.count == 64)
        models["one-too-many"] = .sculpture(leaf)
        #expect(throws: SculptureCompositionError.tooManyModels) {
            try SculptureComposition(title: "65 models", rootID: "root", models: models)
        }
        #expect(try chain(depth: 16).expanded().layers == [[35]])
        #expect(throws: SculptureCompositionError.excessiveDepth) { try chain(depth: 17) }
    }

    @Test func recursivePlacementLimitIncludesRepeatedNestedOccurrences() throws {
        let leaf = try unit()
        let nested = try map(width: 1, rows: [[65]], bindings: [binding(65, "leaf")])
        let root = try map(
            width: 256,
            rows: [Array(repeating: UInt8(78), count: 65_536)],
            bindings: [binding(78, "nested")],
            height: 256
        )
        #expect(throws: SculptureCompositionError.excessivePlacements) {
            try SculptureComposition(
                title: "Nested limit",
                rootID: "root",
                models: ["root": .tiles(root), "nested": .tiles(nested), "leaf": .sculpture(leaf)]
            )
        }
        let direct = try map(
            width: 256,
            rows: [Array(repeating: UInt8(65), count: 65_536)],
            bindings: [binding(65, "leaf")],
            height: 256
        )
        let accepted = try SculptureComposition(
            title: "Exact placement limit",
            rootID: "root",
            models: ["root": .tiles(direct), "leaf": .sculpture(leaf)]
        )
        #expect(try accepted.expanded().occupiedCount == 65_536)
    }

    @Test func resolvedVolumeBudgetCountsDistinctUnusedModelsBeforeExpansion() throws {
        let leaf = try Sculpture(
            title: "Large unused",
            width: 256,
            height: 256,
            layers: Array(repeating: Array(repeating: Sculpture.empty, count: 65_536), count: 256)
        )
        let root = try map(width: 1, rows: [[46]], bindings: [])
        let models: [String: SculptureCompositionModel] = [
            "root": .tiles(root), "a": .sculpture(leaf), "b": .sculpture(leaf), "c": .sculpture(leaf),
            "d": .sculpture(leaf),
        ]
        #expect(throws: SculptureCompositionError.excessiveVolume) {
            try SculptureComposition(title: "64 MiB plus root", rootID: "root", models: models)
        }
    }

    @Test func canonicalCodecPreservesTheGraphAndExpandedResult() throws {
        let composition = try sample()
        let data = try SculptureCompositionCodec.encode(composition)
        #expect(SculptureCompositionCodec.isComposition(data))
        let reopened = try SculptureCompositionCodec.decode(data)
        #expect(reopened == composition)
        #expect(try reopened.expanded() == composition.expanded())
        #expect(try SculptureCompositionCodec.encode(reopened) == data)
        #expect(!SculptureCompositionCodec.isComposition(SculptureCodec.encode(try unit())))
        let withBOM = Data([0xEF, 0xBB, 0xBF]) + data
        #expect(SculptureCompositionCodec.isComposition(withBOM))
        #expect(try SculptureCompositionCodec.decode(withBOM) == composition)
    }

    @Test func fenceLookingRowsAndDirectiveLookingCharactersRoundTripExactly() throws {
        let text = ["```...", "~~~...", "@plane", " :...."]
        let glyphs = Set(text.joined().utf8).filter { $0 != Sculpture.empty }
        let bindings = try glyphs.map { try binding($0, "leaf") }
        let root = try SculptureTileMap(
            width: 6,
            height: 4,
            layers: [Array(text.joined().utf8)],
            tileSize: .init(width: 1, height: 1, depth: 1),
            bindings: bindings
        )
        let composition = try SculptureComposition(
            title: "Literal characters",
            rootID: "root",
            models: ["root": .tiles(root), "leaf": .sculpture(unit())]
        )
        let data = try SculptureCompositionCodec.encode(composition)
        let source = String(decoding: data, as: UTF8.self)
        #expect(source.contains("bind-0x20:") && source.contains("bind-0x3A:"))
        #expect(source.contains("[\"```...\",\"~~~...\",\"@plane\",\" :....\"]"))
        #expect(try SculptureCompositionCodec.decode(data) == composition)
        #expect(try SculptureCompositionCodec.decode(data).expanded().occupiedCount == 14)
    }

    @Test func unknownAndOverwrittenMetadataPlaneAttributesAndBindingAliasesFail() throws {
        let data = try SculptureCompositionCodec.encode(sample())
        let source = String(decoding: data, as: UTF8.self)
        for malformed in [
            source.replacingOccurrences(of: "scene-schema:", with: "unknown: x\nscene-schema:"),
            source.replacingOccurrences(of: "width: 2\n", with: "width: 2\nwidth: 1\n"),
            source.replacingOccurrences(of: "@plane z=0", with: "@plane z=0 z=1"),
            source.replacingOccurrences(of: "@plane z=0", with: "@plane z=0 x=0"),
            source.replacingOccurrences(of: "bind-A: leaf:0", with: "bind-A: leaf:0\nbind-0x41: leaf:0"),
            source.replacingOccurrences(of: "```ascii", with: "```unknown"),
        ] {
            #expect(throws: SculptureCompositionError.self) {
                try SculptureCompositionCodec.decode(Data(malformed.utf8))
            }
        }
    }

    @Test func libraryRejectsUnknownKeysDuplicateKeysDuplicateIDsAndNestedLibraries() throws {
        let data = try SculptureCompositionCodec.encode(sample())
        let source = String(decoding: data, as: UTF8.self)
        let leafDocument = String(decoding: SculptureCodec.encode(try unit()), as: UTF8.self)
        let quotedLeaf = String(decoding: try JSONEncoder().encode(leafDocument), as: UTF8.self)
        let record = "{\"id\":\"leaf\",\"document\":\(quotedLeaf)}"
        for library in [
            "{\"version\":1,\"models\":[],\"unknown\":true}",
            "{\"version\":1,\"version\":1,\"models\":[]}",
            "{\"version\":1,\"models\":[\(record),\(record)]}",
            "{\"version\":1,\"models\":[{\"id\":\"leaf\",\"document\":\(quotedLeaf),\"path\":\"/tmp/leaf\"}]}",
            "{\"version\":2,\"models\":[]}",
        ] {
            #expect(throws: SculptureCompositionError.self) {
                try SculptureCompositionCodec.decode(replaceLibrary(source, with: library))
            }
        }
        let nestedRecord =
            "{\"id\":\"leaf\",\"document\":\(String(decoding: try JSONEncoder().encode(source), as: UTF8.self))}"
        #expect(throws: SculptureCompositionError.invalidLibrary) {
            try SculptureCompositionCodec.decode(
                replaceLibrary(source, with: "{\"version\":1,\"models\":[\(nestedRecord)]}")
            )
        }
    }

    @Test func decoderBoundsPhysicalLinesBytesJSONDepthAndDirectiveAllocations() throws {
        #expect(throws: SculptureCompositionError.oversizedFile) {
            try SculptureCompositionCodec.decode(Data(repeating: 32, count: SculptureCompositionCodec.maximumBytes + 1))
        }
        #expect(throws: SculptureCompositionError.unsupportedSchema) {
            try SculptureCompositionCodec.decode(Data(repeating: 10, count: 100_001))
        }
        let source = String(decoding: try SculptureCompositionCodec.encode(sample()), as: UTF8.self)
        #expect(throws: SculptureCompositionError.invalidLibrary) {
            try SculptureCompositionCodec.decode(
                replaceLibrary(source, with: "{\"version\":1,\"models\":[[[[[[]]]]]]}")
            )
        }
        let tooMany = source + (1...256).map { "@plane z=\($0)\n```ascii\nAA\n```\n" }.joined()
        #expect(throws: SculptureCompositionError.unsupportedPlane) {
            try SculptureCompositionCodec.decode(Data(tooMany.utf8))
        }
    }

    @Test func nativeEncodingSharesTheDecodeLineBudgetSoEveryAcceptedSaveReopens() throws {
        let limit = 100_000
        func lines(_ text: String) -> Int {
            var count = 0
            text.enumerateLines { _, _ in count += 1 }
            return count
        }
        func tall(layers: Int) throws -> Sculpture {
            try Sculpture(
                title: "Tall",
                width: 1,
                height: 256,
                layers: Array(repeating: Array(repeating: Sculpture.empty, count: 256), count: layers)
            )
        }
        func graph(secondLayers: Int) throws -> SculptureComposition {
            let map = try SculptureTileMap(
                width: 2,
                height: 1,
                layers: [[65, 66]],
                tileSize: .init(width: 1, height: 256, depth: 256),
                bindings: [binding(65, "first"), binding(66, "second")]
            )
            return try SculptureComposition(
                title: "Tall pair",
                rootID: "root",
                models: [
                    "root": .tiles(map), "first": .sculpture(tall(layers: 256)),
                    "second": .sculpture(tall(layers: secondLayers)),
                ]
            )
        }
        func documentLines(_ sculpture: Sculpture) -> Int {
            lines(String(decoding: SculptureCodec.encode(sculpture), as: UTF8.self))
        }

        // Decoding counts the whole root source plus every library document against one budget.
        let probe = try SculptureCompositionCodec.encode(graph(secondLayers: 1))
        let rootLines = lines(String(decoding: probe, as: UTF8.self))
        let first = try documentLines(tall(layers: 256))
        let perLayer = try documentLines(tall(layers: 2)) - documentLines(tall(layers: 1))
        let header = try documentLines(tall(layers: 1)) - perLayer
        let fitting = (limit - rootLines - first - header) / perLayer
        #expect(perLayer > 256 && fitting > 1 && fitting < 256)

        let accepted = try graph(secondLayers: fitting)
        let total = try rootLines + first + documentLines(tall(layers: fitting))
        #expect(total <= limit && limit - total < perLayer)
        try SculptureCompositionCodec.validateNativeCapacity(accepted)
        let reopened = try SculptureCompositionCodec.decode(SculptureCompositionCodec.encode(accepted))
        #expect(reopened == accepted)

        let refused = try graph(secondLayers: fitting + 1)
        #expect(try rootLines + first + documentLines(tall(layers: fitting + 1)) > limit)
        for operation in [
            { try SculptureCompositionCodec.validateNativeCapacity(refused) },
            { _ = try SculptureCompositionCodec.encode(refused) },
            {
                try SculptureWorldCodec.validateNativeCapacity(
                    SculptureWorld(title: "Tall world", library: refused, instances: [])
                )
            },
        ] {
            do {
                try operation()
                Issue.record("A graph that decoding would refuse was accepted for saving")
            } catch SculptureCompositionError.tooLargeToReopen(let measured, _) {
                #expect(measured > limit || measured == 0)
            }
        }
        let message = try #require(
            SculptureCompositionError.tooLargeToReopen(lines: limit + 1, bytes: 1).errorDescription
        )
        #expect(message.contains("too large to reopen") && message.contains("\(limit + 1)"))

        // The same refused graph written without the encoder fails decoding, so the encoder's refusal is exact.
        let library = try JSONSerialization.data(
            withJSONObject: [
                "version": 1,
                "models": [
                    [
                        "id": "first",
                        "document": String(decoding: SculptureCodec.encode(tall(layers: 256)), as: UTF8.self),
                    ],
                    [
                        "id": "second",
                        "document": String(decoding: SculptureCodec.encode(tall(layers: fitting + 1)), as: UTF8.self),
                    ],
                ],
            ],
            options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        )
        let forged = try replaceLibrary(
            String(decoding: SculptureCompositionCodec.encode(accepted), as: UTF8.self),
            with: String(decoding: library, as: UTF8.self)
        )
        #expect(throws: SculptureCompositionError.unsupportedSchema) { try SculptureCompositionCodec.decode(forged) }
    }

    @Test func cancellationRejectsEncodingDecodingAndExpansionWithoutPartialOutput() async throws {
        let composition = try sample()
        let data = try SculptureCompositionCodec.encode(composition)
        for operation in 0..<3 {
            let gate = CompositionCancellationGate()
            let task = Task {
                await gate.wait()
                switch operation {
                case 0: _ = try SculptureCompositionCodec.encode(composition)
                case 1: _ = try SculptureCompositionCodec.decode(data)
                default: _ = try composition.expanded()
                }
            }
            task.cancel()
            await gate.release()
            await #expect(throws: CancellationError.self) { try await task.value }
        }
    }

    private func binding(_ glyph: UInt8, _ id: String, turns: Int = 0) throws -> SculptureModelBinding {
        try SculptureModelBinding(glyph: glyph, modelID: id, quarterTurns: turns)
    }

    private func unit(_ glyph: UInt8 = 35) throws -> Sculpture {
        try Sculpture(title: "Unit", width: 1, height: 1, layers: [[glyph]])
    }

    private func map(width: Int, rows: [[UInt8]], bindings: [SculptureModelBinding], height: Int = 1) throws
        -> SculptureTileMap
    {
        try SculptureTileMap(
            width: width,
            height: height,
            layers: rows,
            tileSize: .init(width: 1, height: 1, depth: 1),
            bindings: bindings
        )
    }

    private func sample() throws -> SculptureComposition {
        try SculptureComposition(
            title: "Repeated unit",
            rootID: "root",
            models: [
                "root": .tiles(map(width: 2, rows: [[65, 46]], bindings: [binding(65, "leaf")])),
                "leaf": .sculpture(unit()),
            ]
        )
    }

    private func chain(depth: Int) throws -> SculptureComposition {
        var models: [String: SculptureCompositionModel] = [:]
        for index in 0..<depth {
            let id = String(format: "m%02d", index)
            models[id] =
                index == depth - 1
                ? .sculpture(try unit())
                : .tiles(try map(width: 1, rows: [[65]], bindings: [binding(65, String(format: "m%02d", index + 1))]))
        }
        return try SculptureComposition(title: "Chain", rootID: "m00", models: models)
    }

    private func replaceLibrary(_ source: String, with json: String) throws -> Data {
        let opening = try #require(source.range(of: "```json\n"))
        let closing = try #require(source.range(of: "\n```", range: opening.upperBound..<source.endIndex))
        return Data((source[..<opening.upperBound] + json + source[closing.lowerBound...]).utf8)
    }
}

private actor CompositionCancellationGate {
    private var released = false
    private var waiter: CheckedContinuation<Void, Never>?
    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func release() { released = true; waiter?.resume(); waiter = nil }
}
