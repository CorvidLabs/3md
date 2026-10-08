import Foundation
import Testing
import ThreeMD

@testable import RookSculpture

struct SculptureSceneInsertionTests {
    @Test func selectedVoxelGetsABindingAndImmediatePlacementWithoutChangingTheParent() throws {
        let parent = try emptyParent(width: 2)
        let child = try leaf()
        let result = try SculptureSceneInsertion.intoComposition(
            parent,
            inputs: [.init(scene: .voxels(child))],
            at: .init(x: 1, y: 0, z: 0)
        )
        let composition = try composition(result.scene)
        let root = try tileMap(composition)
        #expect(root.layers == [[Sculpture.empty, 65]])
        #expect(root.bindings == [try .init(glyph: 65, modelID: "insert-model-1")])
        #expect(result.placedRootIDs == ["insert-model-1"])
        #expect(composition.models["insert-model-1"] == .sculpture(child))
        #expect(try composition.expanded().glyph(at: .init(x: 2, y: 0, z: 0)) == 35)
        #expect(try tileMap(parent).layers == [[Sculpture.empty, Sculpture.empty]])
        #expect(parent.models.count == 1)
    }

    @Test func batchPlacementCrossesRowsAndLayersInSelectionOrder() throws {
        let parent = try emptyParent(width: 2, height: 2, depth: 2)
        let inputs = try [35, 64, 43].map { glyph in
            SculptureInsertionInput(scene: .voxels(try leaf(glyph: UInt8(glyph))))
        }
        let result = try SculptureSceneInsertion.intoComposition(
            parent,
            inputs: inputs,
            at: .init(x: 0, y: 1, z: 0)
        )
        let composition = try composition(result.scene)
        let root = try tileMap(composition)
        #expect(root.layers == [[46, 46, 65, 66], [67, 46, 46, 46]])
        #expect(result.placedRootIDs.count == 3)
        #expect(root.bindings.map(\.modelID) == result.placedRootIDs)
        for (index, rootID) in result.placedRootIDs.enumerated() {
            #expect(composition.models[rootID] == inputs[index].scene.voxelModel)
        }
    }

    @Test func placingOverAnOccupiedCellRetainsItsExistingReusableModelAndBinding() throws {
        let parent = try nestedChild()
        let result = try SculptureSceneInsertion.intoComposition(
            parent,
            inputs: [.init(scene: .voxels(leaf(glyph: 43)))],
            at: .init(x: 0, y: 0, z: 0)
        )
        let composition = try composition(result.scene)
        let root = try tileMap(composition)
        #expect(root.layers == [[67, 66]])
        let oldBindings = try tileMap(parent).bindings
        #expect(Array(root.bindings.prefix(2)) == oldBindings)
        #expect(composition.models["leaf"] == parent.models["leaf"])
        #expect(composition.models["unused"] == parent.models["unused"])
    }

    @Test func nestedGraphsNamespaceCollisionsAndRetainSharedChildrenRotationsAndUnusedModels() throws {
        let source = try nestedChild()
        var parentModels = try emptyParent(width: 2, tileWidth: 4).models
        parentModels["insert-model-1"] = .sculpture(try leaf())
        let parent = try SculptureComposition(title: "Parent", rootID: "root", models: parentModels)
        let result = try SculptureSceneInsertion.intoComposition(
            parent,
            preserving: try SculptureThreeMDCodec.capture(.composition(parent)),
            inputs: [.init(scene: .composition(source))],
            at: .init(x: 0, y: 0, z: 0)
        )
        let composition = try composition(result.scene)
        let rootID = try #require(result.placedRootIDs.first)
        guard case .tiles(let imported)? = composition.models[rootID] else {
            Issue.record("Expected a reusable nested tile model"); return
        }
        #expect(imported.layers == [[65, 66]])
        #expect(imported.bindings.count == 2)
        #expect(imported.bindings[0].modelID == imported.bindings[1].modelID)
        #expect(imported.bindings.map(\.quarterTurns) == [0, 1])
        #expect(imported.bindings[0].modelID != "leaf")
        #expect(composition.models.count == parent.models.count + source.models.count)
        #expect(composition.models["insert-model-1"] == parent.models["insert-model-1"])
        #expect(try composition.expanded().occupiedCount == 2)
        let graph = try graph(portable(result))
        #expect(graph.entry(id: rootID)?.document.title == "Nested child")
        #expect(try SculptureThreeMDCodec.modelTitle(for: rootID, in: portable(result)) == "Nested child")
        #expect(try SculptureThreeMDCodec.modelTitle(for: "missing", in: portable(result)) == nil)
        #expect(graph.entry(id: rootID)?.references.map(\.targetID) == imported.bindings.map(\.modelID))
    }

    @Test func repeatedInputKeepsEachImportIndependentButItsInternalSharingIntact() throws {
        let child = try nestedChild()
        let input = SculptureInsertionInput(scene: .composition(child))
        let result = try SculptureSceneInsertion.intoComposition(
            emptyParent(width: 2, tileWidth: 4),
            inputs: [input, input],
            at: .init(x: 0, y: 0, z: 0)
        )
        let composition = try composition(result.scene)
        #expect(Set(result.placedRootIDs).count == 2)
        let first = try tileMap(composition, id: result.placedRootIDs[0])
        let second = try tileMap(composition, id: result.placedRootIDs[1])
        #expect(first.bindings[0].modelID == first.bindings[1].modelID)
        #expect(second.bindings[0].modelID == second.bindings[1].modelID)
        #expect(first.bindings[0].modelID != second.bindings[0].modelID)
    }

    @Test func worldBatchUsesExactFocusAndRootWidthsWithoutFlattening() throws {
        let library = try emptyParent()
        let old = try SculptureWorldInstance(
            id: "insert-instance-1",
            modelID: "root",
            origin: .init(x: -600, y: 4, z: 8)
        )
        let parent = try SculptureWorld(title: "World", library: library, instances: [old])
        let focus = SculptureWorldPoint(x: 9_007_199_254_740_993, y: -900, z: Int64.min)
        let result = try SculptureSceneInsertion.intoWorld(
            parent,
            preserving: try SculptureThreeMDCodec.capture(.world(parent)),
            inputs: [.init(scene: .composition(nestedChild())), .init(scene: .voxels(leaf()))],
            at: focus
        )
        guard case .world(let world) = result.scene else { Issue.record("Expected world"); return }
        #expect(world.instances.first == old)
        #expect(world.instances[1].origin == focus)
        #expect(world.instances[2].origin == .init(x: focus.x + 5, y: focus.y, z: focus.z))
        #expect(world.instances.dropFirst().map(\.id) == ["insert-instance-2", "insert-instance-3"])
        #expect(world.instances.dropFirst().map(\.modelID) == result.placedRootIDs)
        #expect(world.instances.allSatisfy { $0.quarterTurns == 0 })
        guard case .tiles? = world.library.models[result.placedRootIDs[0]] else {
            Issue.record("Nested root must remain a tile map"); return
        }
        #expect(parent.instances == [old])
        #expect(try SculptureThreeMDCodec.decode(SculptureThreeMDCodec.encode(portable(result))) == portable(result))
    }

    @Test func worldBatchRefusesCheckedOverflowAndUnsafeOriginsAtomically() throws {
        let parent = try SculptureWorld(title: "World", library: emptyParent(), instances: [])
        let wide = try Sculpture(title: "Wide", width: 256, height: 1, layers: [[UInt8](repeating: 35, count: 256)])
        #expect(throws: SculptureInsertionError.coordinateOverflow) {
            try SculptureSceneInsertion.intoWorld(
                parent,
                inputs: [.init(scene: .voxels(wide)), .init(scene: .voxels(leaf()))],
                at: .init(x: Int64.max - 256, y: 0, z: 0)
            )
        }
        #expect(throws: SculptureWorldError.invalidOrigin) {
            try SculptureSceneInsertion.intoWorld(
                parent,
                inputs: [.init(scene: .voxels(leaf()))],
                at: .init(x: Int64.max - 255, y: 0, z: 0)
            )
        }
        #expect(parent.instances.isEmpty)
    }

    @Test func unsupportedChildrenEmptyBatchesAndMismatchedSnapshotsRefuse() throws {
        let parent = try emptyParent()
        let world = try SculptureWorld(title: "World", library: parent, instances: [])
        #expect(throws: SculptureInsertionError.noInputs) {
            try SculptureSceneInsertion.intoComposition(parent, inputs: [], at: .init(x: 0, y: 0, z: 0))
        }
        #expect(throws: SculptureInsertionError.noInputs) {
            try SculptureSceneInsertion.intoWorld(world, inputs: [], at: .init(x: 0, y: 0, z: 0))
        }
        #expect(throws: SculptureInsertionError.unsupportedChild) {
            try SculptureSceneInsertion.intoComposition(
                parent,
                inputs: [.init(scene: .world(world))],
                at: .init(x: 0, y: 0, z: 0)
            )
        }
        let source = try leaf()
        let wrong = try SculptureThreeMDCodec.capture(.voxels(leaf(glyph: 43)))
        #expect(throws: SculptureInsertionError.mismatchedSnapshot) {
            try SculptureSceneInsertion.intoWorld(
                world,
                inputs: [.init(scene: .voxels(source), snapshot: wrong)],
                at: .init(x: 0, y: 0, z: 0)
            )
        }
        #expect(throws: SculptureInsertionError.mismatchedSnapshot) {
            try SculptureSceneInsertion.intoComposition(
                parent,
                preserving: wrong,
                inputs: [.init(scene: .voxels(source))],
                at: .init(x: 0, y: 0, z: 0)
            )
        }
    }

    @Test func invalidSelectionInsufficientSpaceAndChildFitCannotPartiallyEdit() throws {
        let parent = try emptyParent(width: 2)
        let input = SculptureInsertionInput(scene: .voxels(try leaf()))
        #expect(throws: SculptureInsertionError.invalidSelection) {
            try SculptureSceneInsertion.intoComposition(parent, inputs: [input], at: .init(x: -1, y: 0, z: 0))
        }
        #expect(throws: SculptureInsertionError.insufficientCells(needed: 2, available: 1)) {
            try SculptureSceneInsertion.intoComposition(parent, inputs: [input, input], at: .init(x: 1, y: 0, z: 0))
        }
        let wide = try Sculpture(title: "Too wide", width: 3, height: 1, layers: [[35, 35, 35]])
        #expect(
            throws: SculptureInsertionError.modelDoesNotFit(
                source: "Too wide",
                required: "3 × 1 × 1",
                current: "2 × 2 × 1"
            )
        ) {
            try SculptureSceneInsertion.intoComposition(
                parent,
                inputs: [.init(scene: .voxels(wide))],
                at: .init(x: 0, y: 0, z: 0)
            )
        }
        #expect(parent.models.count == 1)
        #expect(try tileMap(parent).bindings.isEmpty)
    }

    @Test func completeUnusedModelCountsRemainBoundedBeforeAnyInsertion() throws {
        var models = try emptyParent().models
        let sculpture = try leaf()
        for index in 0..<63 { models["unused-\(index)"] = .sculpture(sculpture) }
        let parent = try SculptureComposition(title: "Full library", rootID: "root", models: models)
        #expect(throws: SculptureInsertionError.tooManyModels(current: 64, incoming: 1, maximum: 64)) {
            try SculptureSceneInsertion.intoComposition(
                parent,
                inputs: [.init(scene: .voxels(sculpture))],
                at: .init(x: 0, y: 0, z: 0)
            )
        }
        #expect(parent.models.count == 64)
    }

    @Test func portableRefusalInsertsNativeValuesWhenNeitherParentNorInputsCarryPortableData() throws {
        let fixture = try NativeCapacityFixture()
        let input = SculptureInsertionInput(scene: .voxels(fixture.child), sourceName: "child.3md")
        let origin = SculptureCell(x: 0, y: 0, z: 0)

        let result = try SculptureSceneInsertion.intoComposition(fixture.parent, inputs: [input], at: origin)
        #expect(result.snapshot == nil && result.usedNativeFallback)
        #expect(result.placedRootIDs == ["insert-model-1"])
        let placedComposition = result.scene == .composition(fixture.nativeCandidate)
        #expect(placedComposition)
        let native = try SculptureCompositionCodec.encode(fixture.nativeCandidate)
        #expect(native.count < SculptureCompositionCodec.maximumBytes)
        let reopened = try SculptureCompositionCodec.decode(native) == fixture.nativeCandidate
        #expect(reopened)

        let focus = SculptureWorldPoint(x: 4, y: 5, z: 6)
        let world = try SculptureWorld(title: "Native world", library: fixture.parent, instances: [])
        let placed = try SculptureSceneInsertion.intoWorld(world, inputs: [input], at: focus)
        #expect(placed.snapshot == nil && placed.usedNativeFallback)
        guard case .world(let candidate) = placed.scene else { Issue.record("Expected a world"); return }
        #expect(candidate.instances == [try .init(id: "insert-instance-1", modelID: "insert-model-1", origin: focus)])
        let sameLibrary = candidate.library == fixture.nativeWorldLibrary
        #expect(sameLibrary)
        #expect(try SculptureWorldCodec.encode(candidate).count < SculptureWorldCodec.maximumBytes)

        // The refused portable attempt never changes the parents.
        let unchangedWorld = world.library == fixture.parent
        #expect(fixture.parent.models.count == 1 && world.instances.isEmpty && unchangedWorld)
        #expect(fixture.root.layers.allSatisfy { $0.allSatisfy { $0 == Sculpture.empty } })
    }

    @Test func portableDataOnTheParentOrAnInputRefusesNamingThePortableLimitAndSources() throws {
        let fixture = try NativeCapacityFixture()
        let origin = SculptureCell(x: 0, y: 0, z: 0)
        let carrier = SculptureInsertionInput(
            scene: .voxels(fixture.child),
            snapshot: try SculptureThreeMDCodec.capture(.voxels(fixture.child)),
            sourceName: "annotated-child.3md"
        )
        let refusal = SculptureInsertionError.portableLimitExceeded(parent: false, sources: ["annotated-child.3md"])
        #expect(throws: refusal) {
            try SculptureSceneInsertion.intoComposition(fixture.parent, inputs: [carrier], at: origin)
        }
        let message = try #require(refusal.errorDescription)
        #expect(message.contains("16 MiB") && message.contains("annotated-child.3md"))
        #expect(!message.contains("definitionBytesExceeded"))

        // A snapshot on the parent counts as portable data, even when it describes an earlier revision.
        let earlier = try SculptureThreeMDCodec.capture(.composition(emptyParent()))
        #expect(throws: SculptureInsertionError.portableLimitExceeded(parent: true, sources: [])) {
            try SculptureSceneInsertion.intoComposition(
                fixture.parent,
                preserving: earlier,
                inputs: [.init(scene: .voxels(fixture.child))],
                at: origin
            )
        }
        let world = try SculptureWorld(title: "World", library: fixture.parent, instances: [])
        #expect(throws: refusal) {
            try SculptureSceneInsertion.intoWorld(world, inputs: [carrier], at: .init(x: 0, y: 0, z: 0))
        }
        let both = SculptureInsertionError.portableLimitExceeded(parent: true, sources: ["a.3md", "b.3md"])
        #expect(both.errorDescription?.contains("the open scene, a.3md and b.3md") == true)
        #expect(fixture.parent.models.count == 1 && world.instances.isEmpty)
    }

    @Test func portableDataOnlyOnAnInputStillYieldsASnapshotAndNoneYieldsNone() throws {
        let parent = try emptyParent(width: 2, tileWidth: 4)
        let origin = SculptureCell(x: 0, y: 0, z: 0)
        let plain = SculptureInsertionInput(scene: .voxels(try leaf()))
        let carrier = SculptureInsertionInput(
            scene: .voxels(try leaf(glyph: 43)),
            snapshot: try SculptureThreeMDCodec.capture(.voxels(leaf(glyph: 43))),
            sourceName: "annotated.3md"
        )
        let none = try SculptureSceneInsertion.intoComposition(parent, inputs: [plain], at: origin)
        #expect(none.snapshot == nil && !none.usedNativeFallback)
        let some = try SculptureSceneInsertion.intoComposition(parent, inputs: [plain, carrier], at: origin)
        let snapshot = try #require(some.snapshot)
        #expect(snapshot.scene == some.scene && !some.usedNativeFallback)
        let world = try SculptureWorld(title: "World", library: parent, instances: [])
        let worldNone = try SculptureSceneInsertion.intoWorld(world, inputs: [plain], at: .init(x: 0, y: 0, z: 0))
        #expect(worldNone.snapshot == nil && !worldNone.usedNativeFallback)
        let worldSome = try SculptureSceneInsertion.intoWorld(world, inputs: [carrier], at: .init(x: 0, y: 0, z: 0))
        #expect(worldSome.snapshot?.scene == worldSome.scene)
    }

    @Test func nativeCapacityIsCheckedBeforeBlamingThePortableLimit() throws {
        // A native copy of this graph would also exceed the 20 MiB file limit, so the portable limit is not the cause.
        let fixture = try NativeCapacityFixture()
        let large = try Sculpture(
            title: "Large",
            width: 256,
            height: 256,
            layers: Array(repeating: Array(repeating: 35, count: 256 * 256), count: 100)
        )
        let carrier = SculptureInsertionInput(
            scene: .voxels(large),
            snapshot: try SculptureThreeMDCodec.capture(.voxels(large)),
            sourceName: "large.3md"
        )
        // A world places any size, so both the annotated and the plain input reach the capacity checks.
        let world = try SculptureWorld(title: "World", library: fixture.parent, instances: [])
        for inputs in [[carrier], [SculptureInsertionInput(scene: .voxels(large), sourceName: "plain.3md")]] {
            do {
                _ = try SculptureSceneInsertion.intoWorld(world, inputs: inputs, at: .init(x: 0, y: 0, z: 0))
                Issue.record("A world that cannot reopen was accepted")
            } catch SculptureCompositionError.tooLargeToReopen {
            }
        }
        #expect(world.instances.isEmpty)
    }

    @Test func nativeVariantsMatchThePortablePlacementWithoutAnySnapshot() throws {
        let parent = try emptyParent(width: 3, tileWidth: 4)
        let inputs = [
            SculptureInsertionInput(scene: .voxels(try leaf())),
            SculptureInsertionInput(scene: .composition(try nestedChild())),
        ]
        let origin = SculptureCell(x: 0, y: 0, z: 0)
        let portable = try SculptureSceneInsertion.intoComposition(parent, inputs: inputs, at: origin)
        let native = try SculptureSceneInsertion.intoCompositionNatively(parent, inputs: inputs, at: origin)
        #expect(native.scene == portable.scene && native.placedRootIDs == portable.placedRootIDs)
        // Without portable data on the parent or any input, the portable attempt validates but keeps no snapshot.
        #expect(native.snapshot == nil && portable.snapshot == nil)
        #expect(!native.usedNativeFallback && !portable.usedNativeFallback)
        let carrying = try SculptureSceneInsertion.intoComposition(
            parent,
            preserving: SculptureThreeMDCodec.capture(.composition(parent)),
            inputs: inputs,
            at: origin
        )
        #expect(carrying.scene == native.scene && carrying.snapshot != nil && !carrying.usedNativeFallback)

        let world = try SculptureWorld(title: "World", library: parent, instances: [])
        let focus = SculptureWorldPoint(x: Int64.min, y: 7, z: -9)
        let portableWorld = try SculptureSceneInsertion.intoWorld(world, inputs: inputs, at: focus)
        let nativeWorld = try SculptureSceneInsertion.intoWorldNatively(world, inputs: inputs, at: focus)
        #expect(nativeWorld.scene == portableWorld.scene && nativeWorld.placedRootIDs == portableWorld.placedRootIDs)
        #expect(nativeWorld.snapshot == nil && portableWorld.snapshot == nil)
        let carryingWorld = try SculptureSceneInsertion.intoWorld(
            world,
            preserving: SculptureThreeMDCodec.capture(.world(world)),
            inputs: inputs,
            at: focus
        )
        #expect(carryingWorld.scene == nativeWorld.scene && carryingWorld.snapshot != nil)
    }

    @Test func insertionTargetsDescribeRowMajorTilesAndTheModelsTheyReplace() throws {
        let parent = try nestedChild()
        let targets = try SculptureSceneInsertion.targets(in: parent, count: 2, at: .init(x: 0, y: 0, z: 0))
        #expect(targets.map(\.cell) == [.init(x: 0, y: 0, z: 0), .init(x: 1, y: 0, z: 0)])
        #expect(targets.map(\.currentGlyph) == [65, 66] && targets.allSatisfy(\.isOccupied))
        #expect(targets.map(\.currentModelID) == ["leaf", "leaf"])
        let wrapped = try SculptureSceneInsertion.targets(
            in: try emptyParent(width: 2, height: 2, depth: 2),
            count: 3,
            at: .init(x: 1, y: 1, z: 0)
        )
        #expect(wrapped.map(\.cell) == [.init(x: 1, y: 1, z: 0), .init(x: 0, y: 0, z: 1), .init(x: 1, y: 0, z: 1)])
        #expect(wrapped.allSatisfy { !$0.isOccupied && $0.currentModelID == nil })
        #expect(throws: SculptureInsertionError.noInputs) {
            try SculptureSceneInsertion.targets(in: parent, count: 0, at: .init(x: 0, y: 0, z: 0))
        }
        #expect(throws: SculptureInsertionError.invalidSelection) {
            try SculptureSceneInsertion.targets(in: parent, count: 1, at: .init(x: 2, y: 0, z: 0))
        }
        #expect(throws: SculptureInsertionError.insufficientCells(needed: 3, available: 1)) {
            try SculptureSceneInsertion.targets(in: parent, count: 3, at: .init(x: 1, y: 0, z: 0))
        }
    }
    @Test func insertionRefusesNativeGraphsThatWouldNotReopenAndLeavesTheParentIntact() throws {
        // Tall children keep voxel data small but share the 100,000-line decode budget across the whole graph.
        let first = try tall()
        let second = try tall()
        let lines = String(decoding: SculptureCodec.encode(first), as: UTF8.self).split(separator: "\n").count
        #expect(lines < 100_000 && lines * 2 > 100_000)
        let map = try SculptureTileMap(
            width: 2,
            height: 1,
            layers: [[65, Sculpture.empty]],
            tileSize: .init(width: 1, height: 256, depth: 256),
            bindings: [.init(glyph: 65, modelID: "first")]
        )
        let parent = try SculptureComposition(
            title: "Tall parent",
            rootID: "root",
            models: ["root": .tiles(map), "first": .sculpture(first)]
        )
        try SculptureCompositionCodec.validateNativeCapacity(parent)
        let input = SculptureInsertionInput(scene: .voxels(second), sourceName: "second.3md")
        let target = SculptureCell(x: 1, y: 0, z: 0)
        for portable in [true, false] {
            do {
                _ =
                    portable
                    ? try SculptureSceneInsertion.intoComposition(parent, inputs: [input], at: target)
                    : try SculptureSceneInsertion.intoCompositionNatively(parent, inputs: [input], at: target)
                Issue.record("An insertion that cannot reopen was accepted")
            } catch SculptureCompositionError.tooLargeToReopen(let measured, _) {
                #expect(measured > 100_000)
            }
        }
        let message = try #require(
            SculptureCompositionError.tooLargeToReopen(lines: 133_000, bytes: 1).errorDescription
        )
        #expect(message.contains("too large to reopen") && message.contains("133000"))
        let world = try SculptureWorld(title: "Tall world", library: parent, instances: [])
        #expect(throws: SculptureCompositionError.self) {
            try SculptureSceneInsertion.intoWorld(world, inputs: [input], at: .init(x: 0, y: 0, z: 0))
        }
        #expect(parent.models.count == 2 && world.instances.isEmpty && world.library == parent)
    }

    @Test func exhaustedBindingCharactersRefuseWithoutRemovingExistingBindings() throws {
        let bindings = try (32...126).filter { $0 != Int(Sculpture.empty) }.map {
            try SculptureModelBinding(glyph: UInt8($0), modelID: "leaf")
        }
        let map = try SculptureTileMap(
            width: 1,
            height: 1,
            layers: [[Sculpture.empty]],
            tileSize: .init(width: 1, height: 1, depth: 1),
            bindings: bindings
        )
        let parent = try SculptureComposition(
            title: "Bound characters",
            rootID: "root",
            models: ["root": .tiles(map), "leaf": .sculpture(leaf())]
        )
        #expect(throws: SculptureInsertionError.noAvailableGlyph(needed: 1, available: 0)) {
            try SculptureSceneInsertion.intoComposition(
                parent,
                inputs: [.init(scene: .voxels(leaf()))],
                at: .init(x: 0, y: 0, z: 0)
            )
        }
        #expect(try tileMap(parent).bindings == bindings)
    }

    @Test func parentAndImportedOpaqueDocumentsAndScopedIdentitiesSurviveNamespaceInsertion() throws {
        let parent = try emptyParent(tileWidth: 4)
        let child = try nestedChild()
        let oldParent = try decorated(SculptureThreeMDCodec.capture(.composition(parent)), tag: "parent")
        let oldChild = try decorated(SculptureThreeMDCodec.capture(.composition(child)), tag: "child", reversed: true)
        let result = try SculptureSceneInsertion.intoComposition(
            parent,
            preserving: oldParent,
            inputs: [.init(scene: .composition(child), snapshot: oldChild)],
            at: .init(x: 0, y: 0, z: 0)
        )
        let source = try graph(oldChild)
        let inserted = try graph(portable(result))
        #expect(inserted.rootEntry.document.metadata["author"] == "parent")
        #expect(inserted.rootEntry.document.preamble == "Notes for parent.")
        let parentAttributes = try graph(oldParent).rootEntry.document.planes[0].attributes
        #expect(inserted.rootEntry.document.planes[0].attributes == parentAttributes)
        let rootID = try #require(result.placedRootIDs.first)
        let importedRoot = try #require(inserted.entry(id: rootID))
        #expect(importedRoot.document.title == "Nested child")
        #expect(importedRoot.document.metadata["author"] == "child")
        #expect(importedRoot.document.preamble == "Notes for child.")
        #expect(importedRoot.document.planes[0].label == "Custom child 0")
        #expect(importedRoot.document.planes[0].attributes == source.rootEntry.document.planes[0].attributes)
        #expect(importedRoot.references.map(\.attributes) == source.rootEntry.references.map(\.attributes))
        #expect(importedRoot.references.map(\.targetID) != source.rootEntry.references.map(\.targetID))
        #expect(inserted.entries.dropFirst().contains { $0.document.planes.first?.stableID == "shared-plane-0" })
        for format in [DocumentStorageFormat.text, .binary(compression: .none)] {
            let bytes = try SculptureThreeMDCodec.encode(portable(result), format: format)
            #expect(try SculptureThreeMDCodec.decode(bytes) == portable(result))
        }
    }

    @Test func authoredLeafAndTilePlaneOrderSurvivesInsertionAndPortableReopen() throws {
        let leaf = try Sculpture(title: "Two slices", width: 1, height: 1, layers: [[35], [43]])
        let map = try SculptureTileMap(
            width: 1,
            height: 1,
            layers: [[65], [65]],
            tileSize: .init(width: 1, height: 1, depth: 2),
            bindings: [.init(glyph: 65, modelID: "leaf")]
        )
        let child = try SculptureComposition(
            title: "Layered child",
            rootID: "root",
            models: ["root": .tiles(map), "leaf": .sculpture(leaf)]
        )
        let parentMap = try SculptureTileMap(
            width: 2,
            height: 1,
            layers: [[46, 46], [46, 46]],
            tileSize: .init(width: 1, height: 1, depth: 4),
            bindings: []
        )
        let parent = try SculptureComposition(title: "Parent", rootID: "parent", models: ["parent": .tiles(parentMap)])
        let parentSnapshot = try reversingPlanes(
            decorated(SculptureThreeMDCodec.capture(.composition(parent)), tag: "parent")
        )
        let leafSnapshot = try reversingPlanes(decorated(SculptureThreeMDCodec.capture(.voxels(leaf)), tag: "leaf"))
        let childSnapshot = try reversingPlanes(
            decorated(SculptureThreeMDCodec.capture(.composition(child)), tag: "child")
        )
        // Both authored source orders are valid spatial documents before they enter the insertion operation.
        #expect(try SculptureThreeMDCodec.decode(SculptureThreeMDCodec.encode(leafSnapshot)) == leafSnapshot)
        #expect(try SculptureThreeMDCodec.decode(SculptureThreeMDCodec.encode(childSnapshot)) == childSnapshot)
        let result = try SculptureSceneInsertion.intoComposition(
            parent,
            preserving: parentSnapshot,
            inputs: [
                .init(scene: .voxels(leaf), snapshot: leafSnapshot),
                .init(scene: .composition(child), snapshot: childSnapshot),
            ],
            at: .init(x: 0, y: 0, z: 0)
        )
        let inserted = try graph(portable(result))
        let leafID = result.placedRootIDs[0]
        let tileID = result.placedRootIDs[1]
        let childRoot = try #require(inserted.entry(id: tileID))
        let nestedLeafID = try #require(childRoot.references.first?.targetID)
        let originals: [(String, Document)] = [
            ("parent", try graph(parentSnapshot).rootEntry.document),
            (leafID, try DocumentStorageCodec.decode(SculptureThreeMDCodec.encode(leafSnapshot))),
            (tileID, try graph(childSnapshot).rootEntry.document),
            (nestedLeafID, try #require(graph(childSnapshot).entry(id: "leaf")).document),
        ]
        for (id, original) in originals {
            let document = try #require(inserted.entry(id: id)).document
            #expect(document.planes.map(\.z) == [1, 0])
            #expect(document.planes.map(\.z) == original.planes.map(\.z))
            #expect(document.planes.map(\.stableID) == original.planes.map(\.stableID))
            #expect(document.planes.map(\.label) == original.planes.map(\.label))
            #expect(document.planes.map(\.attributes) == original.planes.map(\.attributes))
        }
        for format in [DocumentStorageFormat.text, .binary(compression: .none)] {
            let reopened = try SculptureThreeMDCodec.decode(
                SculptureThreeMDCodec.encode(portable(result), format: format)
            )
            #expect(try reopened == portable(result))
            for (id, original) in originals {
                let document = try #require(graph(reopened).entry(id: id)).document
                #expect(document.planes.map(\.z) == original.planes.map(\.z))
                #expect(document.planes.map(\.stableID) == original.planes.map(\.stableID))
                #expect(document.planes.map(\.label) == original.planes.map(\.label))
            }
        }
    }

    @Test func recaptureKeepsSurvivingAuthoredOrderAndAppendsNewSlicesByZ() throws {
        let source = try Sculpture(title: "Source", width: 1, height: 1, layers: [[35], [43]])
        let previous = try reversingPlanes(decorated(SculptureThreeMDCodec.capture(.voxels(source)), tag: "authored"))
        let expanded = try Sculpture(title: "Expanded", width: 1, height: 1, layers: [[35], [43], [64], [42]])
        let next = try SculptureThreeMDCodec.capture(.voxels(expanded), preserving: previous)
        guard case .document(let value) = next.storage else { Issue.record("Expected document"); return }
        #expect(value.document.planes.map(\.z) == [1, 0, 2, 3])
        #expect(value.document.planes.prefix(2).map(\.stableID) == ["shared-plane-1", "shared-plane-0"])
        #expect(value.document.planes.prefix(2).map(\.label) == ["Custom authored 1", "Custom authored 0"])
        #expect(Set(value.document.planes.compactMap(\.stableID)).count == 4)
        let shrunk = try Sculpture(title: "Shrunk", width: 1, height: 1, layers: [[35]])
        let surviving = try SculptureThreeMDCodec.capture(.voxels(shrunk), preserving: next)
        guard case .document(let survivor) = surviving.storage else { Issue.record("Expected document"); return }
        #expect(survivor.document.planes.map(\.z) == [0])
        #expect(survivor.document.planes.first?.stableID == "shared-plane-0")
        for snapshot in [next, surviving] {
            for format in [DocumentStorageFormat.text, .binary(compression: .none)] {
                #expect(
                    try SculptureThreeMDCodec.decode(SculptureThreeMDCodec.encode(snapshot, format: format)) == snapshot
                )
            }
        }
    }

    @Test func standaloneVoxelMetadataIsCarriedIntoItsImportedDefinition() throws {
        let child = try leaf()
        let source = try decorated(SculptureThreeMDCodec.capture(.voxels(child)), tag: "voxel")
        #expect(SculptureThreeMDCodec.modelTitle(for: "leaf", in: source) == nil)
        let result = try SculptureSceneInsertion.intoComposition(
            emptyParent(),
            inputs: [.init(scene: .voxels(child), snapshot: source)],
            at: .init(x: 0, y: 0, z: 0)
        )
        let entry = try #require(graph(portable(result)).entry(id: result.placedRootIDs[0]))
        #expect(entry.document.metadata["author"] == "voxel")
        #expect(entry.document.metadata["sculpt-storage"] == "portable-scene-1")
        #expect(entry.document.preamble == "Notes for voxel.")
        #expect(entry.document.planes[0].attributes == ["3md-id": "shared-plane-0", "material": "voxel"])
        #expect(entry.document.planes[0].label == "Custom voxel 0")
        #expect(try SculptureThreeMDCodec.decode(SculptureThreeMDCodec.encode(portable(result))) == portable(result))
    }

    @Test func worldRootAndNestedDocumentMetadataSurvivePlacementChangesAndSharedEditing() throws {
        let parent = try SculptureWorld(title: "World", library: nestedChild(), instances: [])
        let source = try decorated(SculptureThreeMDCodec.capture(.world(parent)), tag: "world", reversed: true)
        let result = try SculptureSceneInsertion.intoWorld(
            parent,
            preserving: source,
            inputs: [.init(scene: .voxels(leaf()))],
            at: .init(x: 10, y: 20, z: 30)
        )
        let oldGraph = try graph(source)
        let newGraph = try graph(portable(result))
        #expect(newGraph.rootEntry.document.metadata["author"] == "world")
        #expect(newGraph.rootEntry.document.preamble == oldGraph.rootEntry.document.preamble)
        #expect(newGraph.rootEntry.document.planes[0].attributes == oldGraph.rootEntry.document.planes[0].attributes)
        #expect(newGraph.rootEntry.references.first?.attributes == oldGraph.rootEntry.references.first?.attributes)
        let replacement = try leaf(glyph: 43)
        let edited = try SculptureThreeMDEditing.replacingVoxelModel(
            in: portable(result),
            modelID: "leaf",
            expectedRevision: portable(result).revision,
            with: replacement
        )
        let oldLeaf = try #require(newGraph.entry(id: "leaf"))
        let newLeaf = try #require(graph(edited).entry(id: "leaf"))
        #expect(newLeaf.document.metadata == oldLeaf.document.metadata)
        #expect(newLeaf.document.preamble == oldLeaf.document.preamble)
        #expect(newLeaf.document.planes[0].attributes == oldLeaf.document.planes[0].attributes)
        #expect(try SculptureThreeMDCodec.decode(SculptureThreeMDCodec.encode(edited)) == edited)
    }

    @Test func recapturePreservesOpaqueMetadataWhileRecognizedGeometryStillChanges() throws {
        let sculpture = try leaf()
        let source = try decorated(SculptureThreeMDCodec.capture(.voxels(sculpture)), tag: "original")
        let resized = try Sculpture(title: "Changed title", width: 2, height: 1, layers: [[35, 43]])
        let result = try SculptureThreeMDCodec.capture(.voxels(resized), preserving: source)
        guard case .document(let document) = result.storage else { Issue.record("Expected document"); return }
        #expect(document.document.title == "Changed title")
        #expect(document.document.metadata["width"] == "2")
        #expect(document.document.metadata["author"] == "original")
        #expect(document.document.preamble == "Notes for original.")
        #expect(document.document.planes[0].stableID == "shared-plane-0")
        #expect(try SculptureThreeMDCodec.decode(SculptureThreeMDCodec.encode(result)) == result)
    }

    @Test func metadataPreservationDoesNotPermitArbitraryMarkdownOrMalformedGeometry() throws {
        let arbitrary = Document(version: "1.0", axis: .space, title: "Notes", planes: [Plane(z: 0, body: "Hello")])
        #expect(throws: (any Error).self) {
            try SculptureThreeMDCodec.decode(DocumentStorageCodec.encode(arbitrary))
        }
        let source = try decorated(SculptureThreeMDCodec.capture(.voxels(leaf())), tag: "opaque")
        guard case .document(let snapshot) = source.storage else { Issue.record("Expected document"); return }
        var metadata = snapshot.document.metadata
        metadata["width"] = "5"
        let malformed = Document(
            version: snapshot.document.version,
            axis: snapshot.document.axis,
            title: snapshot.document.title,
            metadata: metadata,
            preamble: snapshot.document.preamble,
            planes: snapshot.document.planes
        )
        #expect(throws: (any Error).self) {
            try SculptureThreeMDCodec.decode(DocumentStorageCodec.encode(malformed))
        }
    }

    @Test func portableOpaqueAttributesDoNotHideInvalidIdentitiesOrBindingEdges() throws {
        let source = try graph(SculptureThreeMDCodec.capture(.composition(nestedChild())))
        let root = source.rootEntry
        let invalid = root.references.map { reference in
            var attributes = reference.attributes
            attributes["3md-id"] = "duplicate"
            attributes["caption"] = "Opaque"
            return DocumentReference(targetID: reference.targetID, attributes: attributes)
        }
        let duplicate = try DocumentComposition(
            rootID: source.rootID,
            entries: source.entries.map {
                $0.id == source.rootID ? .init(id: $0.id, document: $0.document, references: invalid) : $0
            }
        )
        #expect(throws: DocumentEditError.self) {
            try SculptureThreeMDCodec.decode(DocumentCompositionCodec.encode(duplicate))
        }
        var attributes = root.references[0].attributes
        attributes["quarter-turns"] = "3"
        let changed = DocumentReference(targetID: root.references[0].targetID, attributes: attributes)
        let mismatch = try DocumentComposition(
            rootID: source.rootID,
            entries: source.entries.map {
                $0.id == source.rootID
                    ? .init(id: $0.id, document: $0.document, references: [changed, root.references[1]]) : $0
            }
        )
        #expect(throws: SculptureThreeMDError.self) {
            try SculptureThreeMDCodec.decode(DocumentCompositionCodec.encode(mismatch))
        }
    }

    @Test func cancellationReturnsNoPartialInsertionForEitherParentKind() async throws {
        let composition = try emptyParent()
        let world = try SculptureWorld(title: "World", library: composition, instances: [])
        let inputs = [SculptureInsertionInput(scene: .voxels(try leaf()))]
        for worldMode in [false, true] {
            let gate = InsertionCancellationGate()
            let task = Task {
                await gate.wait()
                if worldMode {
                    return try SculptureSceneInsertion.intoWorld(world, inputs: inputs, at: .init(x: 0, y: 0, z: 0))
                }
                return try SculptureSceneInsertion.intoComposition(
                    composition,
                    inputs: inputs,
                    at: .init(x: 0, y: 0, z: 0)
                )
            }
            task.cancel()
            await gate.release()
            await #expect(throws: CancellationError.self) { try await task.value }
        }
        #expect(world.instances.isEmpty)
        #expect(composition.models.count == 1)
    }

    private func leaf(glyph: UInt8 = 35) throws -> Sculpture {
        try Sculpture(title: "Leaf", width: 1, height: 1, layers: [[glyph]])
    }

    private func tall() throws -> Sculpture {
        try Sculpture(
            title: "Tall",
            width: 1,
            height: 256,
            layers: [[UInt8]](repeating: [UInt8](repeating: Sculpture.empty, count: 256), count: 256)
        )
    }

    private func portable(_ result: SculptureInsertionResult) throws -> SculptureThreeMDSnapshot {
        try #require(result.snapshot)
    }

    private func emptyParent(width: Int = 1, height: Int = 1, depth: Int = 1, tileWidth: Int = 2) throws
        -> SculptureComposition
    {
        let map = try SculptureTileMap(
            width: width,
            height: height,
            layers: [[UInt8]](repeating: [UInt8](repeating: Sculpture.empty, count: width * height), count: depth),
            tileSize: .init(width: tileWidth, height: 2, depth: 1),
            bindings: []
        )
        return try .init(title: "Parent", rootID: "root", models: ["root": .tiles(map)])
    }

    private func nestedChild() throws -> SculptureComposition {
        let map = try SculptureTileMap(
            width: 2,
            height: 1,
            layers: [[65, 66]],
            tileSize: .init(width: 2, height: 2, depth: 1),
            bindings: [.init(glyph: 65, modelID: "leaf"), .init(glyph: 66, modelID: "leaf", quarterTurns: 1)]
        )
        return try .init(
            title: "Nested child",
            rootID: "root",
            models: ["root": .tiles(map), "leaf": .sculpture(leaf()), "unused": .sculpture(leaf(glyph: 64))]
        )
    }

    private func composition(_ scene: SculptureScene) throws -> SculptureComposition {
        guard case .composition(let composition) = scene else {
            throw SculptureInsertionError.mismatchedSnapshot
        }
        return composition
    }

    private func tileMap(_ composition: SculptureComposition, id: String? = nil) throws -> SculptureTileMap {
        guard case .tiles(let map)? = composition.models[id ?? composition.rootID] else {
            throw SculptureCompositionError.invalidRoot
        }
        return map
    }

    private func graph(_ snapshot: SculptureThreeMDSnapshot) throws -> DocumentComposition {
        guard case .composition(let value) = snapshot.storage else {
            throw SculptureInsertionError.mismatchedSnapshot
        }
        return value.composition
    }

    private func decorated(_ snapshot: SculptureThreeMDSnapshot, tag: String, reversed: Bool = false) throws
        -> SculptureThreeMDSnapshot
    {
        switch snapshot.storage {
        case .document(let value):
            return try SculptureThreeMDCodec.makeSnapshot(
                scene: snapshot.scene,
                document: decorated(value.document, tag: tag)
            )
        case .composition(let value):
            let entries = value.composition.entries.map { entry in
                let references = entry.references.enumerated().map { index, reference in
                    var attributes = reference.attributes
                    attributes["3md-id"] = "shared-reference-\(index)"
                    attributes["caption"] = "\(tag)-\(index)"
                    attributes["source-file"] = "models/child.3md"
                    return DocumentReference(targetID: reference.targetID, attributes: attributes)
                }
                return DocumentEntry(
                    id: entry.id,
                    document: decorated(entry.document, tag: tag),
                    references: reversed ? Array(references.reversed()) : references
                )
            }
            let graph = try DocumentComposition(
                rootID: value.composition.rootID,
                entries: entries,
                limits: SculptureThreeMDPolicy.composition(),
                documentLimits: SculptureThreeMDPolicy.document()
            )
            return try SculptureThreeMDCodec.makeSnapshot(scene: snapshot.scene, graph: graph)
        }
    }

    private func reversingPlanes(_ snapshot: SculptureThreeMDSnapshot) throws -> SculptureThreeMDSnapshot {
        switch snapshot.storage {
        case .document(let value):
            let document = DocumentHeader(value.document).documentForScene(
                planes: Array(value.document.planes.reversed())
            )
            return try SculptureThreeMDCodec.makeSnapshot(scene: snapshot.scene, document: document)
        case .composition(let value):
            let entries = value.composition.entries.map { entry in
                DocumentEntry(
                    id: entry.id,
                    document: DocumentHeader(entry.document).documentForScene(
                        planes: Array(entry.document.planes.reversed())
                    ),
                    references: entry.references
                )
            }
            let graph = try DocumentComposition(
                rootID: value.composition.rootID,
                entries: entries,
                limits: SculptureThreeMDPolicy.composition(),
                documentLimits: SculptureThreeMDPolicy.document()
            )
            return try SculptureThreeMDCodec.makeSnapshot(scene: snapshot.scene, graph: graph)
        }
    }

    private func decorated(_ document: Document, tag: String) -> Document {
        var metadata = document.metadata
        metadata["author"] = tag
        let planes = document.planes.enumerated().map { index, plane in
            Plane(
                z: plane.z,
                label: document.metadata["scene-schema"] == "ascii-world-2" ? "World" : "Custom \(tag) \(index)",
                x: plane.x,
                y: plane.y,
                attributes: ["3md-id": "shared-plane-\(index)", "material": tag],
                body: plane.body
            )
        }
        return Document(
            version: document.version,
            axis: document.axis,
            title: document.title,
            metadata: metadata,
            preamble: "Notes for \(tag).",
            planes: planes
        )
    }
}

private extension SculptureScene {
    var voxelModel: SculptureCompositionModel? {
        if case .voxels(let sculpture) = self { return .sculpture(sculpture) }
        return nil
    }
}

private actor InsertionCancellationGate {
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { self.continuation = $0 }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

/// One empty 256-cell root uses the native axis bounds without allocating any expanded child scene.
/// Its readable file fits native storage, but its canonical portable definition exceeds the portable limit.
private struct NativeCapacityFixture {
    let root: SculptureTileMap
    let parent: SculptureComposition
    let child: Sculpture
    let nativeCandidate: SculptureComposition
    let nativeWorldLibrary: SculptureComposition

    init() throws {
        let dimension = Sculpture.maximumDimension
        root = try SculptureTileMap(
            width: dimension,
            height: dimension,
            layers: Array(repeating: Array(repeating: Sculpture.empty, count: dimension * dimension), count: dimension),
            tileSize: .init(width: 1, height: 1, depth: 1),
            bindings: []
        )
        parent = try SculptureComposition(title: "Native capacity", rootID: "root", models: ["root": .tiles(root)])
        child = try Sculpture(title: "Child", width: 1, height: 1, layers: [[35]])
        var layers = root.layers
        layers[0][0] = 65
        let placed = try SculptureTileMap(
            width: dimension,
            height: dimension,
            layers: layers,
            tileSize: root.tileSize,
            bindings: [.init(glyph: 65, modelID: "insert-model-1")]
        )
        nativeCandidate = try SculptureComposition(
            title: parent.title,
            rootID: parent.rootID,
            models: ["root": .tiles(placed), "insert-model-1": .sculpture(child)]
        )
        nativeWorldLibrary = try SculptureComposition(
            title: parent.title,
            rootID: parent.rootID,
            models: ["root": .tiles(root), "insert-model-1": .sculpture(child)]
        )
    }
}
