import Foundation
import Testing
import ThreeMD

@testable import RookSculpture

struct SculptureThreeMDTests {
    @Test func unmarkedGeneralBinaryAdoptsPortableMarkerWithoutLosingImportedIDs() throws {
        let sculpture = try leaf()
        let legacy = SculptureCodec.document(for: sculpture)
        let planes = legacy.planes.enumerated().map { index, plane in
            Plane(z: plane.z, label: plane.label, attributes: ["3md-id": "imported-slice-\(index)"], body: plane.body)
        }
        let unmarked = DocumentHeader(legacy).documentForScene(planes: planes)
        let input = try DocumentStorageCodec.encode(unmarked, format: .binary(compression: .none))
        let snapshot = try SculptureThreeMDCodec.decode(input)
        let text = try SculptureThreeMDCodec.encode(snapshot)
        #expect(SculptureThreeMDCodec.isPortable(text))
        #expect(snapshot.scene == .voxels(sculpture))
        #expect(try SculptureThreeMDCodec.decode(text) == snapshot)
        #expect(try SculptureThreeMDCodec.capture(snapshot.scene, preserving: snapshot) == snapshot)
        let portable = try DocumentStorageCodec.decode(text)
        #expect(portable.metadata["sculpt-storage"] == "portable-scene-1")
        #expect(portable.planes.compactMap(\.stableID) == ["imported-slice-0", "imported-slice-1"])
        #expect(try DocumentStorageCodec.decode(input).metadata["sculpt-storage"] == nil)
    }

    @Test func portableWorldRootNeverOverwritesAUserModelAndRetainsUnusedBindings() throws {
        let source = try library()
        var models = source.models
        models["sculpt-world"] = models.removeValue(forKey: "root")
        let library = try SculptureComposition(title: source.title, rootID: "sculpt-world", models: models)
        let world = try SculptureWorld(title: "Reserved name collision", library: library, instances: [])
        let snapshot = try SculptureThreeMDCodec.capture(.world(world))
        guard case .composition(let graph) = snapshot.storage else { Issue.record("Expected graph"); return }
        #expect(graph.composition.rootID == "sculpt-world-1")
        #expect(graph.composition.entry(id: "sculpt-world")?.references.count == 2)
        #expect(graph.composition.entry(id: "unused") != nil)
        #expect(try SculptureThreeMDCodec.decode(SculptureThreeMDCodec.encode(snapshot)).scene == .world(world))
    }

    @Test func maximumWorldPlacementsKeepUniqueGraphReferencesAndExactIDs() throws {
        let instances = try (0..<SculptureWorld.maximumInstances).map { index in
            try SculptureWorldInstance(
                id: "instance-\(index)",
                modelID: "leaf",
                origin: .init(x: Int64(index) + 9_007_199_254_740_993, y: -Int64(index), z: 0)
            )
        }
        let world = try SculptureWorld(title: "Full sparse world", library: library(), instances: instances)
        let snapshot = try SculptureThreeMDCodec.capture(.world(world))
        guard case .composition(let graph) = snapshot.storage else { Issue.record("Expected graph"); return }
        #expect(graph.composition.rootEntry.references.count == 2)
        let restored = try SculptureThreeMDCodec.decode(SculptureThreeMDCodec.encode(snapshot))
        #expect(restored.scene == .world(world))
    }

    @Test func portableSceneRoundTripsInTextAndUncompressedBinary() throws {
        for scene in try fixtureScenes() {
            let snapshot = try SculptureThreeMDCodec.capture(scene)
            #expect(snapshot.scene == scene)
            #expect(snapshot.diagnostics.diagnostics.isEmpty && !snapshot.diagnostics.isTruncated)
            for format in [DocumentStorageFormat.text, .binary(compression: .none)] {
                let encoded = try SculptureThreeMDCodec.encode(snapshot, format: format)
                #expect(SculptureThreeMDCodec.isPortable(encoded))
                let restored = try SculptureThreeMDCodec.decode(encoded)
                #expect(restored == snapshot)
                #expect(try SculptureThreeMDCodec.encode(restored, format: format) == encoded)
            }
        }
    }

    @Test func legacyFilesAndSaveDefaultsRemainDistinct() throws {
        let voxel = try leaf()
        let legacyText = SculptureCodec.encode(voxel)
        let legacyBinary = try SculptureBinaryCodec.encode(voxel)
        #expect(!SculptureThreeMDCodec.isPortable(legacyText))
        #expect(!SculptureThreeMDCodec.isPortable(legacyBinary))
        #expect(try SculptureDocumentCodec.decode(legacyText) == voxel)
        #expect(try SculptureDocumentCodec.decode(legacyBinary) == voxel)
        #expect(try SculptureDocumentCodec.encode(voxel, format: .readable) == legacyText)
        #expect(try SculptureDocumentCodec.encode(voxel, format: .compact) == legacyBinary)
        let composition = try library()
        let oldGraph = try SculptureCompositionCodec.encode(composition)
        #expect(!SculptureThreeMDCodec.isPortable(oldGraph))
        #expect(try SculptureCompositionCodec.decode(oldGraph) == composition)
        let world = try sparseWorld()
        let oldWorld = try SculptureWorldCodec.encode(world)
        #expect(!SculptureThreeMDCodec.isPortable(oldWorld))
        #expect(try SculptureWorldCodec.decode(oldWorld) == world)
    }

    @Test func customPlaneAndReferenceIDsSurviveRecaptureAndSharedEditing() throws {
        let base = try SculptureThreeMDCodec.capture(.composition(library()))
        guard case .composition(let value) = base.storage else { Issue.record("Expected graph"); return }
        let graph = try customIdentities(value.composition)
        let bytes = try DocumentCompositionCodec.encode(graph)
        let imported = try SculptureThreeMDCodec.decode(bytes)
        #expect(try SculptureThreeMDCodec.capture(imported.scene, preserving: imported) == imported)
        guard case .composition(let source) = imported.scene else { Issue.record("Expected composition"); return }
        let renamed = try SculptureComposition(
            title: "Renamed portable map",
            rootID: source.rootID,
            models: source.models
        )
        let next = try SculptureThreeMDCodec.capture(.composition(renamed), preserving: imported)
        #expect(next.revision != imported.revision)
        #expect(try identityMap(next) == identityMap(imported))
        var replacement = try leaf()
        replacement.paint(.init(x: 0, y: 0, z: 0), glyph: 43)
        let edited = try SculptureThreeMDEditing.replacingVoxelModel(
            in: next,
            modelID: "leaf",
            expectedRevision: next.revision,
            with: replacement
        )
        #expect(try identityMap(edited) == identityMap(imported))
        #expect(imported.scene == base.scene)
        guard case .composition(let composition) = edited.scene else { Issue.record("Expected composition"); return }
        #expect(composition.models["leaf"] == .sculpture(replacement))
        #expect(composition.models["unused"] == source.models["unused"])
        #expect(try composition.expanded().glyph(at: .init(x: 0, y: 0, z: 0)) == 43)
        #expect(try SculptureThreeMDCodec.decode(SculptureThreeMDCodec.encode(edited)) == edited)
    }

    @Test func untitledNestedDefinitionsStayUntitledWhileNewOnesAreTitledByTheirID() throws {
        let nested = try nestedLibrary(bind: "first")
        let base = try SculptureThreeMDCodec.capture(.composition(nested))
        guard case .composition(let stored) = base.storage else { Issue.record("Expected graph"); return }
        // Authored files may omit a title for a nested definition. Recapture must not invent one.
        let untitledEntries = stored.composition.entries.map { entry in
            guard entry.id == "first" else { return entry }
            let source = entry.document
            let document = Document(
                version: source.version,
                axis: source.axis,
                title: nil,
                metadata: source.metadata,
                preamble: source.preamble,
                planes: source.planes
            )
            return DocumentEntry(id: entry.id, document: document, references: entry.references)
        }
        let untitledGraph = try DocumentComposition(
            rootID: stored.composition.rootID,
            entries: untitledEntries,
            limits: SculptureThreeMDPolicy.composition(),
            documentLimits: SculptureThreeMDPolicy.document()
        )
        let untitled = try SculptureThreeMDCodec.makeSnapshot(scene: base.scene, graph: untitledGraph)
        #expect(SculptureThreeMDCodec.modelTitle(for: "first", in: untitled) == nil)
        #expect(SculptureThreeMDCodec.modelTitle(for: "second", in: untitled) == "second")

        let renamed = try SculptureComposition(title: "Renamed", rootID: nested.rootID, models: nested.models)
        let next = try SculptureThreeMDCodec.capture(.composition(renamed), preserving: untitled)
        #expect(SculptureThreeMDCodec.modelTitle(for: "first", in: next) == nil)
        #expect(SculptureThreeMDCodec.modelTitle(for: "second", in: next) == "second")
        #expect(try SculptureThreeMDCodec.decode(SculptureThreeMDCodec.encode(next)).scene == next.scene)
    }

    @Test func preservedReferenceAttributesFollowTheGlyphAndItsTargetNotTheGlyphAlone() throws {
        let first = try nestedLibrary(bind: "first")
        let base = try SculptureThreeMDCodec.capture(.composition(first))
        guard case .composition(let stored) = base.storage else { Issue.record("Expected graph"); return }
        let annotatedEntries = stored.composition.entries.map { entry in
            let references = entry.references.map { reference in
                var attributes = reference.attributes
                attributes["caption"] = "keep with \(reference.targetID)"
                return DocumentReference(targetID: reference.targetID, attributes: attributes)
            }
            return DocumentEntry(id: entry.id, document: entry.document, references: references)
        }
        let annotated = try SculptureThreeMDCodec.makeSnapshot(
            scene: base.scene,
            graph: DocumentComposition(
                rootID: stored.composition.rootID,
                entries: annotatedEntries,
                limits: SculptureThreeMDPolicy.composition(),
                documentLimits: SculptureThreeMDPolicy.document()
            )
        )
        // Same glyph, different target: the old binding's annotations must not follow the glyph to a new model.
        let retargeted = try nestedLibrary(bind: "second")
        let moved = try SculptureThreeMDCodec.capture(.composition(retargeted), preserving: annotated)
        guard case .composition(let movedStored) = moved.storage else { Issue.record("Expected graph"); return }
        let movedRoot = try #require(movedStored.composition.entry(id: "root"))
        #expect(movedRoot.references.map(\.targetID) == ["second"])
        #expect(movedRoot.references.first?.attributes["caption"] == nil)
        // Same glyph and target: annotations survive a recapture that changes other document content.
        let renamed = try SculptureComposition(title: "Renamed", rootID: first.rootID, models: first.models)
        let kept = try SculptureThreeMDCodec.capture(.composition(renamed), preserving: annotated)
        guard case .composition(let keptStored) = kept.storage else { Issue.record("Expected graph"); return }
        let keptRoot = try #require(keptStored.composition.entry(id: "root"))
        #expect(keptRoot.references.first?.attributes["caption"] == "keep with first")
    }

    @Test func wholeSceneRevisionRejectsStaleModelEditWithoutPublishingChanges() throws {
        let initial = try SculptureThreeMDCodec.capture(.world(sparseWorld()))
        guard case .world(let world) = initial.scene else { Issue.record("Expected world"); return }
        let changed = try SculptureWorld(title: "Changed parent", library: world.library, instances: world.instances)
        let current = try SculptureThreeMDCodec.capture(.world(changed), preserving: initial)
        do {
            _ = try SculptureThreeMDEditing.replacingVoxelModel(
                in: current,
                modelID: "leaf",
                expectedRevision: initial.revision,
                with: leaf()
            )
            Issue.record("Expected stale revision")
        } catch let error as DocumentEditError {
            #expect(error.diagnostic.code == .staleRevision)
            #expect(error.diagnostic.path == "expectedRevision")
            #expect(!SculptureThreeMDCodec.isCapacityError(error))
        }
        #expect(current.scene == .world(changed))
        #expect(initial.scene == .world(world))
    }

    @Test func invalidSharedReplacementIsAtomicAndWorldAnchorsStayExact() throws {
        let world = try sparseWorld()
        let snapshot = try SculptureThreeMDCodec.capture(.world(world))
        let tooLarge = try Sculpture(title: "Too wide", width: 3, height: 1, layers: [[35, 35, 35]])
        #expect(throws: SculptureCompositionError.childDoesNotFit("leaf")) {
            try SculptureThreeMDEditing.replacingVoxelModel(
                in: snapshot,
                modelID: "leaf",
                expectedRevision: snapshot.revision,
                with: tooLarge
            )
        }
        var replacement = try leaf()
        replacement.paint(.init(x: 1, y: 0, z: 0), glyph: 43)
        let edited = try SculptureThreeMDEditing.replacingVoxelModel(
            in: snapshot,
            modelID: "leaf",
            expectedRevision: snapshot.revision,
            with: replacement
        )
        guard case .world(let result) = edited.scene else { Issue.record("Expected world"); return }
        #expect(result.instances == world.instances)
        #expect(result.library.models["unused"] == world.library.models["unused"])
        #expect(snapshot.scene == .world(world))
        guard case .composition(let graph) = edited.storage else { Issue.record("Expected graph"); return }
        #expect(graph.composition.rootEntry.references.count == 2)
        #expect(graph.composition.entries.count == world.library.models.count + 1)
    }

    @Test func malformedIdentitiesAndDisagreeingReferencesNeverUseLegacyFallback() throws {
        let base = try SculptureThreeMDCodec.capture(.composition(library()))
        guard case .composition(let value) = base.storage else { Issue.record("Expected graph"); return }
        let graph = value.composition
        let entries = graph.entries.map { entry in
            guard entry.id == "root" else { return entry }
            var references = entry.references
            references[0] = .init(targetID: "unused", attributes: references[0].attributes)
            return DocumentEntry(id: entry.id, document: entry.document, references: references)
        }
        let mismatched = try DocumentComposition(rootID: graph.rootID, entries: entries)
        do {
            _ = try SculptureThreeMDCodec.decode(DocumentCompositionCodec.encode(mismatched))
            Issue.record("Expected reference mismatch")
        } catch let error as SculptureThreeMDError {
            #expect(error.diagnostic.path == "entries[root].references")
            #expect(!SculptureThreeMDCodec.isCapacityError(error))
        }
        let voxel = try SculptureThreeMDCodec.capture(.voxels(leaf()))
        guard case .document(let document) = voxel.storage else { Issue.record("Expected document"); return }
        let badPlanes = document.document.planes.map {
            Plane(z: $0.z, label: $0.label, attributes: ["3md-id": "bad identity"], body: $0.body)
        }
        let bad = DocumentHeader(document.document).documentForScene(planes: badPlanes)
        do {
            _ = try SculptureThreeMDCodec.decode(DocumentStorageCodec.encode(bad))
            Issue.record("Expected invalid identity")
        } catch let error as DocumentEditError {
            #expect(error.diagnostic.code == .invalidIdentity)
            #expect(!SculptureThreeMDCodec.isCapacityError(error))
        }
    }

    @Test func largeLegacyLibraryRetainsItsOwnCapacityAndPortableFailureIsExplicit() throws {
        let large = try Sculpture(
            title: "Maximum leaf",
            width: 256,
            height: 256,
            layers: Array(repeating: Array(repeating: UInt8(35), count: 65_536), count: 256)
        )
        let map = try SculptureTileMap(
            width: 1,
            height: 1,
            layers: [[65]],
            tileSize: .init(width: 256, height: 256, depth: 256),
            bindings: [.init(glyph: 65, modelID: "large")]
        )
        let composition = try SculptureComposition(
            title: "Large legacy",
            rootID: "root",
            models: ["root": .tiles(map), "large": .sculpture(large)]
        )
        #expect(try SculptureCompositionCodec.encode(composition).count < SculptureCompositionCodec.maximumBytes)
        do {
            _ = try SculptureThreeMDCodec.capture(.composition(composition))
            Issue.record("Expected upstream definition capacity")
        } catch let error as DocumentCompositionError {
            #expect(error == .definitionBytesExceeded)
            #expect(SculptureThreeMDCodec.isCapacityError(error))
        }
        let voxel = try SculptureThreeMDCodec.capture(.voxels(large))
        #expect(try SculptureThreeMDCodec.decode(SculptureThreeMDCodec.encode(voxel)).scene == .voxels(large))
    }

    @Test func cancellationPropagatesThroughAllPublicPortableOperations() async throws {
        let scene = try SculptureScene.composition(library())
        let snapshot = try SculptureThreeMDCodec.capture(scene)
        let data = try SculptureThreeMDCodec.encode(snapshot)
        let operations: [@Sendable () throws -> Void] = [
            { _ = try SculptureThreeMDCodec.capture(scene) },
            { _ = try SculptureThreeMDCodec.decode(data) },
            { _ = try SculptureThreeMDCodec.encode(snapshot) },
            {
                _ = try SculptureThreeMDEditing.replacingVoxelModel(
                    in: snapshot,
                    modelID: "leaf",
                    expectedRevision: snapshot.revision,
                    with: leaf()
                )
            },
        ]
        for operation in operations {
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                try operation()
            }
            await #expect(throws: CancellationError.self) { try await task.value }
        }
    }

    /// Root can regenerate these actual public-codec files for its separate nine-pair interchange check.
    @Test func deterministicPortableInterchangeFixtures() throws {
        let scenes = try fixtureScenes()
        let destination = ProcessInfo.processInfo.environment["ROOK_PORTABLE_FIXTURE_DIRECTORY"]
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let directory =
            destination.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? repository.appendingPathComponent("docs/evidence/3md-2-adoption/interchange", isDirectory: true)
        if destination != nil {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        for (name, scene) in zip(["portable-voxel", "portable-composition", "portable-world"], scenes) {
            let snapshot = try SculptureThreeMDCodec.capture(scene)
            for (suffix, format) in [(".3md", DocumentStorageFormat.text), (".3mdb", .binary(compression: .none))] {
                let data = try SculptureThreeMDCodec.encode(snapshot, format: format)
                let path = directory.appendingPathComponent(name + suffix)
                if destination != nil { try data.write(to: path) }
                #expect(try Data(contentsOf: path) == data)
            }
        }
    }
}

private func leaf() throws -> Sculpture {
    try Sculpture(title: "Portable \"leaf\" \\ study", width: 2, height: 1, layers: [[35, 64], [46, 43]])
}

private func library() throws -> SculptureComposition {
    let map = try SculptureTileMap(
        width: 2,
        height: 1,
        layers: [[65, 66]],
        tileSize: .init(width: 2, height: 2, depth: 2),
        bindings: [.init(glyph: 65, modelID: "leaf"), .init(glyph: 66, modelID: "leaf", quarterTurns: 1)]
    )
    return try SculptureComposition(
        title: "Portable repeated library",
        rootID: "root",
        models: [
            "root": .tiles(map), "leaf": .sculpture(leaf()),
            "unused": .sculpture(Sculpture(title: "Unused", width: 1, height: 1, layers: [[42]])),
        ]
    )
}

private func sparseWorld() throws -> SculptureWorld {
    try SculptureWorld(
        title: "Portable exact world",
        library: library(),
        instances: [
            .init(
                id: "minimum",
                modelID: "leaf",
                origin: .init(x: .min, y: 9_007_199_254_740_993, z: -9_007_199_254_740_993)
            ),
            .init(
                id: "adjacent",
                modelID: "leaf",
                origin: .init(x: .min + 1, y: 9_007_199_254_740_994, z: -9_007_199_254_740_992),
                quarterTurns: 1
            ),
            .init(id: "maximum", modelID: "leaf", origin: .init(x: .max - 256, y: 0, z: 0), quarterTurns: 3),
        ]
    )
}

private func fixtureScenes() throws -> [SculptureScene] {
    try [.voxels(leaf()), .composition(library()), .world(sparseWorld())]
}

private func customIdentities(_ graph: DocumentComposition) throws -> DocumentComposition {
    let entries = graph.entries.map { entry in
        let planes = entry.document.planes.enumerated().map { index, plane in
            Plane(
                z: plane.z,
                label: plane.label,
                x: plane.x,
                y: plane.y,
                attributes: ["3md-id": "custom-\(entry.id)-slice-\(index)"],
                body: plane.body
            )
        }
        let references = entry.references.enumerated().map { index, reference in
            var attributes = reference.attributes
            attributes["3md-id"] = "custom-\(entry.id)-binding-\(index)"
            return DocumentReference(targetID: reference.targetID, attributes: attributes)
        }
        return DocumentEntry(
            id: entry.id,
            document: DocumentHeader(entry.document).documentForScene(planes: planes),
            references: references
        )
    }
    return try DocumentComposition(rootID: graph.rootID, entries: entries)
}

private func identityMap(_ snapshot: SculptureThreeMDSnapshot) throws -> [String: [String]] {
    guard case .composition(let value) = snapshot.storage else { throw SculptureCompositionError.invalidLibrary }
    return Dictionary(
        uniqueKeysWithValues: value.composition.entries.map { entry in
            (entry.id, entry.document.planes.compactMap(\.stableID) + entry.references.compactMap(\.stableID))
        }
    )
}

/// A root map binding one glyph to a nested tile model, beside a second nested model it could be retargeted to.
private func nestedLibrary(bind target: String) throws -> SculptureComposition {
    func tiles(binding modelID: String? = nil, title: String = "Nested") throws -> SculptureTileMap {
        try SculptureTileMap(
            width: 1,
            height: 1,
            layers: [[modelID == nil ? Sculpture.empty : 65]],
            tileSize: .init(width: 2, height: 2, depth: 1),
            bindings: modelID.map { [try .init(glyph: 65, modelID: $0)] } ?? []
        )
    }
    let cell = try Sculpture(title: "Cell", width: 1, height: 1, layers: [[35]])
    return try SculptureComposition(
        title: "Nested library",
        rootID: "root",
        models: [
            "root": .tiles(tiles(binding: target)),
            "first": .tiles(tiles(binding: "cell")),
            "second": .tiles(tiles(binding: "cell")),
            "cell": .sculpture(cell),
        ]
    )
}
