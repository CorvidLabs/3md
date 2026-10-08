import Foundation

/// Immutable edits retain reusable references and validate the complete readable document before publication.
public enum SculptureModelEditing {
    public static func replacingVoxelModel(
        in composition: SculptureComposition,
        modelID: String,
        expected: Sculpture,
        with replacement: Sculpture
    ) throws -> SculptureComposition {
        try Task.checkCancellation()
        guard case .sculpture(let source) = composition.models[modelID] else {
            throw SculptureModelEditingError.voxelModelRequired(modelID)
        }
        guard source == expected else { throw SculptureModelEditingError.expectedModelChanged(modelID) }
        var models = composition.models
        models[modelID] = .sculpture(replacement)
        let candidate = try SculptureComposition(title: composition.title, rootID: composition.rootID, models: models)
        _ = try SculptureCompositionCodec.encode(candidate)
        try Task.checkCancellation()
        return candidate
    }

    public static func replacingVoxelModel(
        in world: SculptureWorld,
        modelID: String,
        expected: Sculpture,
        with replacement: Sculpture
    ) throws -> SculptureWorld {
        let library = try replacingVoxelModel(
            in: world.library,
            modelID: modelID,
            expected: expected,
            with: replacement
        )
        let candidate = try SculptureWorld(title: world.title, library: library, instances: world.instances)
        _ = try SculptureWorldCodec.encode(candidate)
        try Task.checkCancellation()
        return candidate
    }

    /// Clones one voxel leaf and rebinds exactly one placement. Nested tile maps require explicit shared editing.
    public static func makingUnique(
        in world: SculptureWorld,
        instanceID: String,
        newModelID: String
    ) throws -> SculptureWorld {
        try Task.checkCancellation()
        guard let instance = world.instances.first(where: { $0.id == instanceID }) else {
            throw SculptureModelEditingError.unknownInstance(instanceID)
        }
        guard case .sculpture(let source) = world.library.models[instance.modelID] else {
            throw SculptureModelEditingError.voxelModelRequired(instance.modelID)
        }
        guard newModelID != instance.modelID else { throw SculptureModelEditingError.unchangedModelID }
        guard world.library.models[newModelID] == nil else {
            throw SculptureCompositionError.duplicateModel(newModelID)
        }
        var models = world.library.models
        models[newModelID] = .sculpture(source)
        let library = try SculptureComposition(title: world.library.title, rootID: world.library.rootID, models: models)
        let replacement = try SculptureWorldInstance(
            id: instance.id,
            modelID: newModelID,
            origin: instance.origin,
            quarterTurns: instance.quarterTurns
        )
        let candidate = try SculptureWorld(
            title: world.title,
            library: library,
            instances: world.instances.map { $0.id == instanceID ? replacement : $0 }
        )
        _ = try SculptureWorldCodec.encode(candidate)
        try Task.checkCancellation()
        return candidate
    }
}

public enum SculptureModelEditingError: Error, LocalizedError, Equatable, Sendable {
    case expectedModelChanged(String), voxelModelRequired(String), unknownInstance(String), unchangedModelID

    public var errorDescription: String? {
        switch self {
        case .expectedModelChanged(let id): "The model '\(id)' changed after editing began. Reopen it before applying."
        case .voxelModelRequired(let id): "Choose a voxel model to edit. '\(id)' is missing or is a nested tile map."
        case .unknownInstance(let id): "The world placement '\(id)' is missing. Select another placement."
        case .unchangedModelID: "A unique model needs a new model ID."
        }
    }
}
