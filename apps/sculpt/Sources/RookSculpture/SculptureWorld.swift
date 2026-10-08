import Foundation

/// An exact sparse-world anchor. Voxel Y grows downward, matching sculpture document coordinates.
public struct SculptureWorldPoint: Hashable, Codable, Sendable {
    public let x: Int64
    public let y: Int64
    public let z: Int64

    public init(x: Int64, y: Int64, z: Int64) {
        self.x = x
        self.y = y
        self.z = z
    }
}

/// One model reference and transform; distant anchors do not allocate intervening cells.
public struct SculptureWorldInstance: Equatable, Sendable {
    public let id: String
    public let modelID: String
    public let origin: SculptureWorldPoint
    public let quarterTurns: Int

    public init(id: String, modelID: String, origin: SculptureWorldPoint, quarterTurns: Int = 0) throws {
        guard SculptureCompositionValidation.isValidID(id) else { throw SculptureWorldError.invalidID(id) }
        guard SculptureCompositionValidation.isValidID(modelID) else { throw SculptureWorldError.invalidID(modelID) }
        guard (0...3).contains(quarterTurns) else { throw SculptureWorldError.invalidRotation }
        // Every model is at most 256³; adding its nonnegative local coordinates cannot overflow.
        let maximum = Int64.max - Int64(Sculpture.maximumDimension)
        guard origin.x <= maximum, origin.y <= maximum, origin.z <= maximum else {
            throw SculptureWorldError.invalidOrigin
        }
        self.id = id
        self.modelID = modelID
        self.origin = origin
        self.quarterTurns = quarterTurns
    }
}

/// A self-contained sparse scene with finite placement capacity and no fixed spatial extent.
/// Model volumes stay bounded; constructing or saving a world never expands its library.
public struct SculptureWorld: Equatable, Sendable {
    public static let maximumInstances = 65_536
    public let title: String
    public let library: SculptureComposition
    public let instances: [SculptureWorldInstance]

    public init(title: String, library: SculptureComposition, instances: [SculptureWorldInstance]) throws {
        try Task.checkCancellation()
        guard SculptureCompositionValidation.isValidTitle(title) else { throw SculptureWorldError.invalidTitle }
        guard instances.count <= Self.maximumInstances else { throw SculptureWorldError.tooManyInstances }
        var ids: Set<String> = []
        ids.reserveCapacity(instances.count)
        for instance in instances {
            try Task.checkCancellation()
            guard ids.insert(instance.id).inserted else { throw SculptureWorldError.duplicateInstance(instance.id) }
            guard library.models[instance.modelID] != nil else {
                throw SculptureWorldError.unknownModel(instance.modelID)
            }
        }
        self.title = title
        self.library = library
        self.instances = instances
    }
}

public enum SculptureWorldError: Error, LocalizedError, Equatable, Sendable {
    case invalidTitle, invalidRotation, invalidOrigin, tooManyInstances
    case invalidID(String), duplicateInstance(String), unknownModel(String)
    case oversizedFile, unsupportedSchema, unsupportedPlane, invalidEnvelope, invalidLibrary

    public var errorDescription: String? {
        switch self {
        case .invalidTitle: "Use a world title of 1–80 printable ASCII characters."
        case .invalidRotation: "Use zero, one, two, or three clockwise quarter-turns."
        case .invalidOrigin: "Keep world anchors at or below Int64.max minus 256 so model coordinates cannot overflow."
        case .tooManyInstances: "A sparse world can hold at most 65,536 model instances."
        case .invalidID(let id):
            "Invalid ID '\(id)'. Use 1–48 ASCII letters, digits, underscores, or hyphens; start with a letter or digit."
        case .duplicateInstance(let id): "The instance ID '\(id)' occurs more than once."
        case .unknownModel(let id): "The world references missing library model '\(id)'."
        case .oversizedFile: "Choose a world file of at most 20 MiB."
        case .unsupportedSchema: "Use a version 1 ascii-world-1 document with supported metadata."
        case .unsupportedPlane: "A world needs exactly one Z-zero World plane without offsets or extra attributes."
        case .invalidEnvelope: "The world needs a version 1 JSON envelope with a library and explicit model instances."
        case .invalidLibrary: "The embedded world library must be a valid, self-contained composition."
        }
    }
}
