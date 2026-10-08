import Foundation
import Testing

@testable import RookSculpture

struct SculptureInsertionPlanTests {
    @Test func naturalFilenameOrderIsDeterministicForAnySelectionOrder() {
        let paths = ["/b/model10.3md", "/a/model2.3md", "/a/Model1.3md", "/z/model2.3md", "/a/model2.3mdb"]
        let expected = ["/a/Model1.3md", "/a/model2.3md", "/z/model2.3md", "/a/model2.3mdb", "/b/model10.3md"]
        for rotation in 0..<paths.count {
            let shuffled = Array(paths[rotation...] + paths[..<rotation])
            #expect(shuffled.sorted(by: SculptureInsertionPlan.precedes) == expected)
        }
        #expect(SculptureInsertionPlan.precedes("/x/model2.3md", "/x/model10.3md"))
        #expect(!SculptureInsertionPlan.precedes("/x/model10.3md", "/x/model2.3md"))
        #expect(SculptureInsertionPlan.precedes("/a/same.3md", "/b/same.3md"))
        #expect(!SculptureInsertionPlan.precedes("/a/same.3md", "/a/same.3md"))
    }

    @Test func onlyReadableAndCompactFilesAreInsertableInAnyLetterCase() {
        for supported in ["3md", "3MD", "3mdb", "3MdB"] {
            #expect(SculptureInsertionPlan.isSupportedFile(pathExtension: supported))
        }
        for unsupported in ["", "md", "txt", "3mdx", "obj"] {
            #expect(!SculptureInsertionPlan.isSupportedFile(pathExtension: unsupported))
        }
    }

    @Test func countsCellsGlyphsAndModelsAreRefusedBeforeAnyFileIsRead() throws {
        let plan = try SculptureInsertionPlan(composition: parent(width: 2), at: .init(x: 1, y: 0, z: 0))
        #expect(throws: SculptureInsertionError.noInputs) { try plan.admitFileCount(0) }
        #expect(throws: SculptureInsertionError.insufficientCells(needed: 2, available: 1)) {
            try plan.admitFileCount(2)
        }
        try plan.admitFileCount(1)
        #expect(throws: SculptureInsertionError.tooManyFiles(count: 65, maximum: 64)) {
            try SculptureInsertionPlan().admitFileCount(65)
        }
        var models = try parent(width: 4).models
        for index in 0..<61 { models["leaf-\(index)"] = .sculpture(try leaf("Leaf", 35)) }
        let crowded = try SculptureComposition(title: "Crowded", rootID: "root", models: models)
        let tight = try SculptureInsertionPlan(composition: crowded, at: .init(x: 0, y: 0, z: 0))
        #expect(throws: SculptureInsertionError.tooManyModels(current: 62, incoming: 3, maximum: 64)) {
            try tight.admitFileCount(3)
        }
        var bound = try (33...126).filter { $0 != Int(Sculpture.empty) }.map {
            try SculptureModelBinding(glyph: UInt8($0), modelID: "leaf")
        }
        bound.removeLast(1)
        let map = try SculptureTileMap(
            width: 4,
            height: 1,
            layers: [[Sculpture.empty, Sculpture.empty, Sculpture.empty, Sculpture.empty]],
            tileSize: .init(width: 4, height: 4, depth: 4),
            bindings: bound
        )
        let ledger = try SculptureComposition(
            title: "Ledger",
            rootID: "root",
            models: ["root": .tiles(map), "leaf": .sculpture(leaf("Leaf", 35))]
        )
        let glyphs = try SculptureInsertionPlan(composition: ledger, at: .init(x: 0, y: 0, z: 0))
        #expect(throws: SculptureInsertionError.noAvailableGlyph(needed: 2, available: 1)) {
            try glyphs.admitFileCount(2)
        }
    }

    @Test func worldPlansBoundPlacementsAndHaveNoTileFit() throws {
        let library = try parent(width: 1)
        let instances = try (0..<(SculptureWorld.maximumInstances - 1)).map {
            try SculptureWorldInstance(id: "placed-\($0)", modelID: "root", origin: .init(x: Int64($0), y: 0, z: 0))
        }
        let world = try SculptureWorld(title: "Nearly full", library: library, instances: instances)
        let plan = SculptureInsertionPlan(world: world)
        #expect(plan.tileSize == nil)
        try plan.admitFileCount(1)
        #expect(
            throws: SculptureInsertionError.tooManyPlacements(
                current: SculptureWorld.maximumInstances - 1,
                incoming: 2,
                maximum: SculptureWorld.maximumInstances
            )
        ) {
            try plan.admitFileCount(2)
        }
        var admitting = plan
        try admitting.admit(.init(scene: .voxels(leaf("Huge for any tile", 35, width: 256))))
    }

    @Test func aggregateBytesAreBudgetedAcrossFilesAndRefuseByName() throws {
        var plan = SculptureInsertionPlan()
        try plan.admitBytes(SculptureInsertionPlan.maximumBytes - 10, source: "first.3mdb")
        try plan.admitBytes(10, source: "second.3md")
        #expect(
            throws: SculptureInsertionError.aggregateBytesExceeded(
                source: "third.3md",
                maximum: SculptureInsertionPlan.maximumBytes
            )
        ) {
            try plan.admitBytes(1, source: "third.3md")
        }
        var single = SculptureInsertionPlan()
        #expect(throws: SculptureInsertionError.self) {
            try single.admitBytes(SculptureInsertionPlan.maximumBytes + 1, source: "huge.3mdb")
        }
    }

    @Test func decodeNamesTheSourceForWorldsGenericMarkdownAndMalformedInput() throws {
        let world = try SculptureWorld(title: "A world", library: parent(width: 1), instances: [])
        let worldBytes = try SculptureWorldCodec.encode(world)
        for (name, bytes) in [
            ("sparse.3md", worldBytes),
            ("notes.3md", Data("---\ntitle: Notes\n---\nHello\n".utf8)),
            ("garbage.3mdb", Data("not a model".utf8)),
        ] {
            do {
                _ = try SculptureInsertionPlan.decode(bytes, source: name)
                Issue.record("\(name) was accepted")
            } catch SculptureInsertionError.source(let refused, let reason) {
                #expect(refused == name && !reason.isEmpty)
            }
        }
        let worldReason = SculptureInsertionError.unsupportedChild.localizedDescription
        do {
            _ = try SculptureInsertionPlan.decode(worldBytes, source: "sparse.3md")
        } catch SculptureInsertionError.source(_, let reason) {
            #expect(reason == worldReason)
        }
        let accepted = try SculptureInsertionPlan.decode(SculptureCodec.encode(leaf("Fine", 35)), source: "fine.3md")
        #expect(accepted.sourceName == "fine.3md" && accepted.displayName == "fine.3md")
        #expect(accepted.scene == .voxels(try leaf("Fine", 35)) && accepted.snapshot == nil)
    }

    @Test func admittedFilesAreCheckedForFitAndCumulativeModelCountRightAfterTheirOwnDecode() throws {
        var plan = try SculptureInsertionPlan(composition: parent(width: 3), at: .init(x: 0, y: 0, z: 0))
        let tooWide = SculptureCodec.encode(try leaf("Wide", 35, width: 5))
        #expect(
            throws: SculptureInsertionError.modelDoesNotFit(
                source: "wide.3md",
                required: "5 × 1 × 1",
                current: "4 × 4 × 4"
            )
        ) {
            try plan.admit(tooWide, source: "wide.3md")
        }
        _ = try plan.admit(SculptureCodec.encode(leaf("Fits", 35, width: 4)), source: "fits.3md")
        var crowded = try SculptureInsertionPlan(composition: parent(width: 3), at: .init(x: 0, y: 0, z: 0))
        let manyModels = try SculptureCompositionCodec.encode(library(modelCount: 63))
        do {
            _ = try crowded.admit(manyModels, source: "library.3md")
            Issue.record("A library larger than the remaining model budget was accepted")
        } catch SculptureInsertionError.source(let name, let reason) {
            #expect(name == "library.3md" && reason.contains("64"))
        }
    }

    @Test func compactHeaderFitIsRefusedBeforeDecompressionAndOnlyForSupportedHeaders() throws {
        let big = try Sculpture(
            title: "Big",
            width: 10,
            height: 10,
            layers: Array(repeating: Array(repeating: Sculpture.empty, count: 100), count: 10)
        )
        let compact = try SculptureBinaryCodec.encode(big)
        let dimensions = try #require(SculptureBinaryCodec.dimensions(inHeader: compact))
        #expect(dimensions.width == 10 && dimensions.height == 10 && dimensions.depth == 10)
        #expect(SculptureBinaryCodec.dimensions(inHeader: Data(compact.prefix(59))) == nil)
        #expect(SculptureBinaryCodec.dimensions(inHeader: SculptureCodec.encode(big)) == nil)
        var badVersion = compact
        badVersion[8] = 9
        #expect(SculptureBinaryCodec.dimensions(inHeader: badVersion) == nil)
        // Only the header and title remain, so decompressing would fail. Fit is decided from the header first.
        let truncated = Data(compact.prefix(60 + "Big".utf8.count))
        var small = try SculptureInsertionPlan(composition: parent(width: 2), at: .init(x: 0, y: 0, z: 0))
        #expect(
            throws: SculptureInsertionError.modelDoesNotFit(
                source: "big.3mdb",
                required: "10 × 10 × 10",
                current: "4 × 4 × 4"
            )
        ) {
            try small.admit(truncated, source: "big.3mdb")
        }
        var roomy = try SculptureInsertionPlan(
            composition: parent(width: 1, tile: .init(width: 16, height: 16, depth: 16)),
            at: .init(x: 0, y: 0, z: 0)
        )
        // A header that fits is decoded, and the truncated body then fails by name instead of being mistaken for fit.
        do {
            _ = try roomy.admit(truncated, source: "big.3mdb")
            Issue.record("A truncated compact file was decoded")
        } catch SculptureInsertionError.source(let name, let reason) {
            #expect(name == "big.3mdb" && !reason.isEmpty)
        }
        let decoded = try roomy.admit(compact, source: "big.3mdb")
        #expect(decoded.scene == .voxels(big))
    }

    @Test func resolvedVolumeIsBudgetedFromTheParentLibraryAndRefusedByNameBeforeDecoding() throws {
        let budget = SculptureComposition.maximumResolvedVoxelBytes
        // Four unused 256-cubed models exactly fill the 64 MiB budget, using almost no memory.
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
        let full = try SculptureComposition(title: "Full volume", rootID: "root", models: models)
        #expect(full.models.values.reduce(0) { $0 + $1.resolvedVolume } == budget)
        // The validator and the plan share one accounting: a fifth such model is refused by both.
        models["d"] = try volumeModel()
        #expect(throws: SculptureCompositionError.excessiveVolume) {
            try SculptureComposition(title: "Too much", rootID: "root", models: models)
        }
        let refusal = SculptureInsertionError.resolvedVolumeExceeded(source: "leaf.3md", maximum: budget)
        var composition = try SculptureInsertionPlan(composition: full, at: .init(x: 0, y: 0, z: 0))
        #expect(throws: refusal) { try composition.admit(SculptureCodec.encode(leaf("Leaf", 35)), source: "leaf.3md") }
        let world = try SculptureWorld(title: "World", library: full, instances: [])
        var sparse = SculptureInsertionPlan(world: world)
        #expect(throws: refusal) { try sparse.admit(SculptureCodec.encode(leaf("Leaf", 35)), source: "leaf.3md") }
        #expect(
            refusal.errorDescription?.contains("leaf.3md") == true
                && refusal.errorDescription?.contains("64 MiB") == true
        )

        // A compact file whose header claims a 256-cubed volume is refused by name from its header alone.
        let compact = try SculptureBinaryCodec.encode(leaf("Tiny", 35))
        var claimed = compact
        for offset in stride(from: 12, to: 18, by: 2) { claimed[offset] = 0; claimed[offset + 1] = 1 }
        #expect(SculptureBinaryCodec.dimensions(inHeader: claimed)?.width == 256)
        let truncated = Data(claimed.prefix(60 + "Tiny".utf8.count))
        let headerRefusal = SculptureInsertionError.resolvedVolumeExceeded(source: "huge.3mdb", maximum: budget)
        #expect(throws: headerRefusal) { try composition.admit(truncated, source: "huge.3mdb") }
        #expect(throws: headerRefusal) { try sparse.admit(truncated, source: "huge.3mdb") }
    }

    @Test func resolvedVolumeAccumulatesAcrossAdmittedInputsWithoutAnyParent() throws {
        func bigComposition(_ title: String) throws -> SculptureInsertionInput {
            let map = try SculptureTileMap(
                width: 1,
                height: 1,
                layers: [[Sculpture.empty]],
                tileSize: .init(width: 256, height: 256, depth: 256),
                bindings: []
            )
            let composition = try SculptureComposition(title: title, rootID: "root", models: ["root": .tiles(map)])
            return SculptureInsertionInput(scene: .composition(composition), sourceName: "\(title).3md")
        }
        var plan = SculptureInsertionPlan()
        for index in 0..<4 { try plan.admit(bigComposition("block\(index)")) }
        #expect(
            throws: SculptureInsertionError.resolvedVolumeExceeded(
                source: "block4.3md",
                maximum: SculptureComposition.maximumResolvedVoxelBytes
            )
        ) {
            try plan.admit(bigComposition("block4"))
        }
    }

    private func leaf(_ title: String, _ glyph: UInt8, width: Int = 1) throws -> Sculpture {
        try Sculpture(title: title, width: width, height: 1, layers: [Array(repeating: glyph, count: width)])
    }

    private func parent(
        width: Int,
        tile: SculptureTileSize? = nil
    ) throws -> SculptureComposition {
        let map = try SculptureTileMap(
            width: width,
            height: 1,
            layers: [Array(repeating: Sculpture.empty, count: width)],
            tileSize: try tile ?? .init(width: 4, height: 4, depth: 4),
            bindings: []
        )
        return try SculptureComposition(title: "Parent", rootID: "root", models: ["root": .tiles(map)])
    }

    /// A one-tile root over `modelCount` unused library leaves: small enough to fit any tile, large in model count.
    private func library(modelCount: Int) throws -> SculptureComposition {
        var models: [String: SculptureCompositionModel] = [:]
        for index in 0..<modelCount { models["leaf-\(index)"] = .sculpture(try leaf("Leaf", 35)) }
        let map = try SculptureTileMap(
            width: 1,
            height: 1,
            layers: [[Sculpture.empty]],
            tileSize: .init(width: 1, height: 1, depth: 1),
            bindings: []
        )
        models["root"] = .tiles(map)
        return try SculptureComposition(title: "Library", rootID: "root", models: models)
    }
}
