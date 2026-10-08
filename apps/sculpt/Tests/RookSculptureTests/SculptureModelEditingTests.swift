import RookSculpture
import Testing

@Suite("Shared model value editing")
struct SculptureModelEditingTests {
    @Test func replacementPropagatesThroughRepeatedNestedRotatedReferences() throws {
        let (composition, source) = try fixture()
        let replacement = try Sculpture(title: "Changed leaf", width: 1, height: 1, layers: [[64]])
        let changed = try SculptureModelEditing.replacingVoxelModel(
            in: composition,
            modelID: "leaf",
            expected: source,
            with: replacement
        )
        #expect(changed.title == composition.title && changed.rootID == composition.rootID)
        #expect(changed.models["root"] == composition.models["root"])
        #expect(changed.models["nested"] == composition.models["nested"])
        #expect(try changed.expanded().layers == [[64, 64, 64, 64]])
        #expect(try SculptureCompositionCodec.decode(SculptureCompositionCodec.encode(changed)) == changed)
        #expect(try composition.expanded().layers == [[35, 35, 35, 35]])
    }

    @Test func staleLeafAndOversizedReplacementAreRejectedWithoutChangingSource() throws {
        let (composition, source) = try fixture()
        let stale = try Sculpture(title: "Other title", width: 1, height: 1, layers: [[35]])
        #expect(throws: SculptureModelEditingError.expectedModelChanged("leaf")) {
            try SculptureModelEditing.replacingVoxelModel(
                in: composition,
                modelID: "leaf",
                expected: stale,
                with: source
            )
        }
        let oversized = try Sculpture(title: "Too wide", width: 2, height: 1, layers: [[35, 35]])
        #expect(throws: SculptureCompositionError.childDoesNotFit("leaf")) {
            try SculptureModelEditing.replacingVoxelModel(
                in: composition,
                modelID: "leaf",
                expected: source,
                with: oversized
            )
        }
        #expect(throws: SculptureModelEditingError.voxelModelRequired("nested")) {
            try SculptureModelEditing.replacingVoxelModel(
                in: composition,
                modelID: "nested",
                expected: source,
                with: source
            )
        }
        #expect(try composition.expanded().layers == [[35, 35, 35, 35]])
    }

    @Test func uniquePlacementClonesOneLeafAndPreservesOthersAndTransforms() throws {
        let (composition, source) = try fixture()
        let instances = try ["first", "second"].enumerated().map { index, id in
            try SculptureWorldInstance(
                id: id,
                modelID: "leaf",
                origin: SculptureWorldPoint(x: Int64(index * 10), y: -20, z: 30),
                quarterTurns: 3
            )
        }
        let world = try SculptureWorld(title: "Shared world", library: composition, instances: instances)
        let unique = try SculptureModelEditing.makingUnique(in: world, instanceID: "first", newModelID: "unique-leaf")
        #expect(unique.library.models["unique-leaf"] == .sculpture(source))
        #expect(unique.instances[0].id == instances[0].id)
        #expect(unique.instances[0].origin == instances[0].origin)
        #expect(unique.instances[0].quarterTurns == 3)
        #expect(unique.instances[0].modelID == "unique-leaf")
        #expect(unique.instances[1] == instances[1])
        let replacement = try Sculpture(title: "Unique changed", width: 1, height: 1, layers: [[64]])
        let edited = try SculptureModelEditing.replacingVoxelModel(
            in: unique,
            modelID: "unique-leaf",
            expected: source,
            with: replacement
        )
        #expect(edited.library.models["leaf"] == .sculpture(source))
        #expect(edited.library.models["unique-leaf"] == .sculpture(replacement))
        #expect(try edited.library.expanded().layers == [[35, 35, 35, 35]])
        #expect(try SculptureWorldCodec.decode(SculptureWorldCodec.encode(edited)) == edited)
    }

    @Test func uniqueRejectsNestedMapsDuplicateInvalidIDsAndLibraryCapacity() throws {
        let (composition, _) = try fixture()
        let instance = try SculptureWorldInstance(id: "placed", modelID: "nested", origin: .init(x: 0, y: 0, z: 0))
        let world = try SculptureWorld(title: "Nested world", library: composition, instances: [instance])
        #expect(throws: SculptureModelEditingError.voxelModelRequired("nested")) {
            try SculptureModelEditing.makingUnique(in: world, instanceID: "placed", newModelID: "unique")
        }
        let leafInstance = try SculptureWorldInstance(id: "placed", modelID: "leaf", origin: .init(x: 0, y: 0, z: 0))
        let leafWorld = try SculptureWorld(title: "Leaf world", library: composition, instances: [leafInstance])
        #expect(throws: SculptureCompositionError.duplicateModel("nested")) {
            try SculptureModelEditing.makingUnique(in: leafWorld, instanceID: "placed", newModelID: "nested")
        }
        #expect(throws: SculptureCompositionError.invalidID("../other")) {
            try SculptureModelEditing.makingUnique(in: leafWorld, instanceID: "placed", newModelID: "../other")
        }
        var models = composition.models
        for index in 0..<61 { models["unused-\(index)"] = models["leaf"] }
        let full = try SculptureComposition(title: composition.title, rootID: composition.rootID, models: models)
        let fullWorld = try SculptureWorld(title: "Full", library: full, instances: [leafInstance])
        #expect(throws: SculptureCompositionError.tooManyModels) {
            try SculptureModelEditing.makingUnique(in: fullWorld, instanceID: "placed", newModelID: "unique")
        }
    }

    @Test func cancelledReplacementDoesNotPublish() async throws {
        let (composition, source) = try fixture()
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return try SculptureModelEditing.replacingVoxelModel(
                in: composition,
                modelID: "leaf",
                expected: source,
                with: source
            )
        }
        task.cancel()
        do {
            _ = try await task.value; Issue.record("Cancelled model replacement succeeded")
        } catch is CancellationError {}
        #expect(try composition.expanded().layers == [[35, 35, 35, 35]])
    }

    @Test func uniqueCloneRejectsReadableFileOverflowBeforePublishingLibrary() throws {
        let large = try Sculpture(
            title: "Large shared model",
            width: 256,
            height: 256,
            layers: Array(repeating: Array(repeating: 35, count: 256 * 256), count: 128)
        )
        let map = try SculptureTileMap(
            width: 1,
            height: 1,
            layers: [[65]],
            tileSize: .init(width: 256, height: 256, depth: 128),
            bindings: [SculptureModelBinding(glyph: 65, modelID: "large")]
        )
        let library = try SculptureComposition(
            title: "Bounded library",
            rootID: "root",
            models: [
                "root": .tiles(map), "large": .sculpture(large), "spare": .sculpture(large),
            ]
        )
        let instance = try SculptureWorldInstance(id: "placed", modelID: "large", origin: .init(x: 0, y: 0, z: 0))
        let world = try SculptureWorld(title: "Bounded world", library: library, instances: [instance])
        #expect(try SculptureWorldCodec.encode(world).count <= SculptureWorldCodec.maximumBytes)
        // A third copy would exceed the native byte and line budgets, so the file could not be reopened.
        do {
            _ = try SculptureModelEditing.makingUnique(in: world, instanceID: "placed", newModelID: "unique")
            Issue.record("A unique copy that cannot reopen was accepted")
        } catch SculptureCompositionError.tooLargeToReopen {
        }
        #expect(world.library.models.count == 3 && world.instances == [instance])
    }

    private func fixture() throws -> (SculptureComposition, Sculpture) {
        let source = try Sculpture(title: "Leaf", width: 1, height: 1, layers: [[35]])
        let leafTile = try SculptureTileSize(width: 1, height: 1, depth: 1)
        let nested = try SculptureTileMap(
            width: 2,
            height: 1,
            layers: [[65, 65]],
            tileSize: leafTile,
            bindings: [SculptureModelBinding(glyph: 65, modelID: "leaf", quarterTurns: 1)]
        )
        let root = try SculptureTileMap(
            width: 2,
            height: 1,
            layers: [[66, 66]],
            tileSize: SculptureTileSize(width: 2, height: 1, depth: 1),
            bindings: [SculptureModelBinding(glyph: 66, modelID: "nested")]
        )
        return (
            try SculptureComposition(
                title: "Nested shared",
                rootID: "root",
                models: ["root": .tiles(root), "nested": .tiles(nested), "leaf": .sculpture(source)]
            ), source
        )
    }
}
