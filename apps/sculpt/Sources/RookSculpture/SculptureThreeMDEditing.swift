import Foundation
import ThreeMD

/// Shared model changes publish one validated scene through ThreeMD's exact-revision transactions.
public enum SculptureThreeMDEditing {
    public static func replacingVoxelModel(
        in snapshot: SculptureThreeMDSnapshot,
        modelID: String,
        expectedRevision: DocumentRevision,
        with replacement: Sculpture
    ) throws -> SculptureThreeMDSnapshot {
        try Task.checkCancellation()
        guard expectedRevision == snapshot.revision else {
            throw DocumentEditError(
                .init(
                    code: .staleRevision,
                    message: "The scene changed after this model edit was prepared.",
                    path: "expectedRevision"
                )
            )
        }
        guard case .composition(let graphSnapshot) = snapshot.storage,
            let source = graphSnapshot.composition.entry(id: modelID),
            source.document.metadata["scene-schema"] == "ascii-sculpture-1"
        else { throw SculptureModelEditingError.voxelModelRequired(modelID) }

        let scene: SculptureScene
        switch snapshot.scene {
        case .composition(let composition):
            var models = composition.models
            models[modelID] = .sculpture(replacement)
            scene = .composition(
                try SculptureComposition(title: composition.title, rootID: composition.rootID, models: models)
            )
        case .world(let world):
            var models = world.library.models
            models[modelID] = .sculpture(replacement)
            let library = try SculptureComposition(
                title: world.library.title,
                rootID: world.library.rootID,
                models: models
            )
            scene = .world(try SculptureWorld(title: world.title, library: library, instances: world.instances))
        case .voxels: throw SculptureModelEditingError.voxelModelRequired(modelID)
        }

        let documentLimits = try SculptureThreeMDPolicy.document()
        let limits = try SculptureThreeMDPolicy.editing()
        let desired = try DocumentIdentity.adopt(
            SculptureThreeMDCodec.preservingPlanes(SculptureCodec.document(for: replacement), from: source.document),
            documentLimits: documentLimits
        )
        let oldDocument = try DocumentSnapshot(source.document, limits: documentLimits)
        // Remove and reinsert as one transaction so resized/reordered slices retain their identities by Z.
        var operations: [DocumentEdit] = [.replaceHeader(DocumentHeader(desired))]
        for plane in source.document.planes {
            guard let id = plane.stableID else {
                throw DocumentEditError(
                    .init(code: .missingIdentity, message: "The source slice has no stable identity.", path: "planes")
                )
            }
            operations.append(.remove(id: id))
        }
        for (index, plane) in desired.planes.enumerated() { operations.append(.insert(plane: plane, at: index)) }
        let document = try DocumentEditor.apply(
            .init(expectedRevision: oldDocument.revision, operations: operations),
            to: oldDocument,
            limits: limits,
            documentLimits: documentLimits
        )
        let entry = DocumentEntry(id: modelID, document: document.document, references: source.references)
        let graph = try CompositionEditor.apply(
            .init(expectedRevision: expectedRevision, operations: [.replaceEntry(id: modelID, entry: entry)]),
            to: graphSnapshot,
            limits: limits,
            compositionLimits: SculptureThreeMDPolicy.composition(),
            documentLimits: documentLimits
        )
        try Task.checkCancellation()
        return try SculptureThreeMDCodec.makeSnapshot(scene: scene, graph: graph.composition)
    }
}
