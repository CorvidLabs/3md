import Foundation

/// The fixed voxel block reserved for each character in a tile map.
public struct SculptureTileSize: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let depth: Int

    public init(width: Int, height: Int, depth: Int) throws {
        guard [width, height, depth].allSatisfy({ (1...Sculpture.maximumDimension).contains($0) }) else {
            throw SculptureCompositionError.invalidDimensions
        }
        self.width = width
        self.height = height
        self.depth = depth
    }
}

/// A printable map character places a named model, optionally rotated clockwise in document XY.
public struct SculptureModelBinding: Equatable, Sendable {
    public let glyph: UInt8
    public let modelID: String
    public let quarterTurns: Int

    public init(glyph: UInt8, modelID: String, quarterTurns: Int = 0) throws {
        guard (32...126).contains(glyph), glyph != Sculpture.empty else {
            throw SculptureCompositionError.invalidBindingGlyph(glyph)
        }
        guard SculptureCompositionValidation.isValidID(modelID) else {
            throw SculptureCompositionError.invalidID(modelID)
        }
        guard (0...3).contains(quarterTurns) else { throw SculptureCompositionError.invalidRotation }
        self.glyph = glyph
        self.modelID = modelID
        self.quarterTurns = quarterTurns
    }
}

/// Explicit, nonoverlapping tile blocks. A period leaves its entire block empty.
public struct SculptureTileMap: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let layers: [[UInt8]]
    public let tileSize: SculptureTileSize
    public let bindings: [SculptureModelBinding]
    public var depth: Int { layers.count }

    public init(
        width: Int,
        height: Int,
        layers: [[UInt8]],
        tileSize: SculptureTileSize,
        bindings: [SculptureModelBinding]
    ) throws {
        try Task.checkCancellation()
        guard (1...Sculpture.maximumDimension).contains(width),
            (1...Sculpture.maximumDimension).contains(height),
            (1...Sculpture.maximumDimension).contains(layers.count),
            width * tileSize.width <= Sculpture.maximumDimension,
            height * tileSize.height <= Sculpture.maximumDimension,
            layers.count * tileSize.depth <= Sculpture.maximumDimension
        else { throw SculptureCompositionError.invalidDimensions }
        var glyphs: Set<UInt8> = []
        for binding in bindings {
            guard glyphs.insert(binding.glyph).inserted else {
                throw SculptureCompositionError.duplicateBinding(binding.glyph)
            }
        }
        var placements = 0
        for layer in layers {
            guard layer.count == width * height else { throw SculptureCompositionError.invalidGrid }
            for y in 0..<height {
                try Task.checkCancellation()
                for glyph in layer[(y * width)..<((y + 1) * width)] where glyph != Sculpture.empty {
                    guard glyphs.contains(glyph) else { throw SculptureCompositionError.unboundGlyph(glyph) }
                    placements += 1
                    guard placements <= SculptureComposition.maximumPlacements else {
                        throw SculptureCompositionError.excessivePlacements
                    }
                }
            }
        }
        self.width = width
        self.height = height
        self.layers = layers
        self.tileSize = tileSize
        self.bindings = bindings.sorted { $0.glyph < $1.glyph }
    }
}

public enum SculptureCompositionModel: Equatable, Sendable {
    case sculpture(Sculpture)
    case tiles(SculptureTileMap)
}

/// A self-contained library graph. No model ID is a file path, URL, or implicit external resource.
public struct SculptureComposition: Equatable, Sendable {
    public static let maximumModels = 64
    /// Counts model nodes along the longest dependency path, including the root and leaf.
    public static let maximumDepth = 16
    /// Sum of expanded voxel volumes for all unique models, including unused library models.
    public static let maximumResolvedVoxelBytes = 64 * 1_048_576
    /// Bounds nested placement occurrences across the root and every other unique library model.
    public static let maximumPlacements = 65_536

    public let title: String
    public let rootID: String
    public let models: [String: SculptureCompositionModel]

    public init(title: String, rootID: String, models: [String: SculptureCompositionModel]) throws {
        try Task.checkCancellation()
        guard SculptureCompositionValidation.isValidTitle(title) else { throw SculptureCompositionError.invalidTitle }
        guard SculptureCompositionValidation.isValidID(rootID) else {
            throw SculptureCompositionError.invalidID(rootID)
        }
        guard !models.isEmpty, models.count <= Self.maximumModels else { throw SculptureCompositionError.tooManyModels }
        for id in models.keys where !SculptureCompositionValidation.isValidID(id) {
            throw SculptureCompositionError.invalidID(id)
        }
        guard case .tiles? = models[rootID] else { throw SculptureCompositionError.invalidRoot }
        var validator = CompositionValidator(models: models)
        try validator.validate()
        self.title = title
        self.rootID = rootID
        self.models = models
    }

    /// Resolves shared children once, then copies occupied cells into their reserved, empty-padded tile blocks.
    public func expanded() throws -> Sculpture {
        try expanded(modelID: rootID)
    }

    /// Resolves one library model without allocating the root volume or unrelated models.
    public func expanded(modelID: String) throws -> Sculpture {
        try Task.checkCancellation()
        var resolver = CompositionResolver(models: models, rootID: rootID, title: title)
        return try resolver.resolve(modelID)
    }
}

public enum SculptureCompositionError: Error, LocalizedError, Equatable, Sendable {
    case invalidDimensions, invalidGrid, invalidTitle, invalidRotation, invalidRoot
    case invalidID(String), invalidBindingGlyph(UInt8), unboundGlyph(UInt8), duplicateBinding(UInt8)
    case unknownModel(String), duplicateModel(String), cyclicReference(String), childDoesNotFit(String)
    case tooManyModels, excessiveDepth, excessiveVolume, excessivePlacements, oversizedFile
    case unsupportedSchema, unsupportedPlane, invalidLibrary
    /// The readable encoding would exceed a native decode budget, so a saved copy could not be reopened.
    case tooLargeToReopen(lines: Int, bytes: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidDimensions: "Map and tile dimensions must produce a volume of at most 256 cells on each axis."
        case .invalidGrid: "Each tile layer must contain the declared rectangular ASCII grid."
        case .invalidTitle: "Use a title of 1–80 printable ASCII characters."
        case .invalidRotation: "Use zero, one, two, or three clockwise quarter-turns."
        case .invalidRoot: "The root model must exist and be a tile map."
        case .invalidID(let id):
            "Invalid model ID '\(id)'. Use 1–48 ASCII letters, digits, underscores, or hyphens; start with a letter or digit."
        case .invalidBindingGlyph(let glyph): "Binding byte \(glyph) must be printable ASCII other than a period."
        case .unboundGlyph(let glyph): "Map byte \(glyph) has no model binding."
        case .duplicateBinding(let glyph): "Map byte \(glyph) has more than one binding."
        case .unknownModel(let id): "The model '\(id)' is missing from this composition."
        case .duplicateModel(let id): "The model ID '\(id)' occurs more than once."
        case .cyclicReference(let id): "The model '\(id)' forms a dependency cycle."
        case .childDoesNotFit(let id): "The rotated model '\(id)' does not fit its reserved tile block."
        case .tooManyModels: "A composition must contain 1–64 models."
        case .excessiveDepth: "A composition dependency path exceeds 16 model nodes."
        case .excessiveVolume: "The combined resolved model volumes exceed 64 MiB of voxels."
        case .excessivePlacements: "The composition exceeds 65,536 model placements, including nested occurrences."
        case .oversizedFile: "Choose a composition file of at most 20 MiB."
        case .unsupportedSchema: "Use a version 1 ascii-composition-1 document with supported metadata."
        case .unsupportedPlane:
            "Tile planes must be consecutive integer Z slices without spatial offsets or extra attributes."
        case .invalidLibrary:
            "The composition needs one version 1 JSON model library with unique IDs and readable 3md documents."
        case .tooLargeToReopen(let lines, let bytes):
            Self.tooLargeDescription(lines: lines, bytes: bytes)
        }
    }

    private static func tooLargeDescription(lines: Int, bytes: Int) -> String {
        var reasons: [String] = []
        if lines > SculptureCompositionCodec.maximumLines { reasons.append("its readable file reaches \(lines) lines") }
        if bytes > SculptureCompositionCodec.maximumBytes { reasons.append("its readable file exceeds 20 MiB") }
        let detail = reasons.isEmpty ? "it exceeds a native file limit" : reasons.joined(separator: " and ")
        return
            "This scene would be too large to reopen: \(detail), and Sculpt reads at most "
            + "\(SculptureCompositionCodec.maximumLines) lines and 20 MiB per file. "
            + "Remove models or map layers, then try again."
    }
}

internal enum SculptureCompositionValidation {
    static func isValidID(_ id: String) -> Bool {
        let bytes = Array(id.utf8)
        guard (1...48).contains(bytes.count), let first = bytes.first, isAlphanumeric(first) else { return false }
        return bytes.allSatisfy { isAlphanumeric($0) || $0 == 45 || $0 == 95 }
    }

    static func isValidTitle(_ title: String) -> Bool {
        !title.isEmpty && title.utf8.count <= 80 && title.utf8.allSatisfy { (32...126).contains($0) }
    }

    private static func isAlphanumeric(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
    }
}

private struct CompositionInfo {
    let width: Int
    let height: Int
    let depth: Int
    let graphDepth: Int
    let placements: Int
}

private struct CompositionValidator {
    let models: [String: SculptureCompositionModel]
    private var resolved: [String: CompositionInfo] = [:]
    private var visiting: Set<String> = []
    private var volume = 0
    private var placements = 0

    init(models: [String: SculptureCompositionModel]) { self.models = models }

    mutating func validate() throws {
        for id in models.keys.sorted() { _ = try visit(id, pathDepth: 1) }
    }

    private mutating func visit(_ id: String, pathDepth: Int) throws -> CompositionInfo {
        try Task.checkCancellation()
        guard pathDepth <= SculptureComposition.maximumDepth else { throw SculptureCompositionError.excessiveDepth }
        if let info = resolved[id] { return info }
        guard !visiting.contains(id) else { throw SculptureCompositionError.cyclicReference(id) }
        guard let model = models[id] else { throw SculptureCompositionError.unknownModel(id) }
        visiting.insert(id)
        let info: CompositionInfo
        switch model {
        case .sculpture(let sculpture):
            info = CompositionInfo(
                width: sculpture.width,
                height: sculpture.height,
                depth: sculpture.depth,
                graphDepth: 1,
                placements: 0
            )
        case .tiles(let map):
            var children: [UInt8: CompositionInfo] = [:]
            var graphDepth = 1
            for binding in map.bindings {
                let child = try visit(binding.modelID, pathDepth: pathDepth + 1)
                let odd = !binding.quarterTurns.isMultiple(of: 2)
                guard (odd ? child.height : child.width) <= map.tileSize.width,
                    (odd ? child.width : child.height) <= map.tileSize.height,
                    child.depth <= map.tileSize.depth
                else { throw SculptureCompositionError.childDoesNotFit(binding.modelID) }
                children[binding.glyph] = child
                graphDepth = max(graphDepth, child.graphDepth + 1)
            }
            guard graphDepth <= SculptureComposition.maximumDepth else {
                throw SculptureCompositionError.excessiveDepth
            }
            var occurrences = 0
            for layer in map.layers {
                for y in 0..<map.height {
                    try Task.checkCancellation()
                    for glyph in layer[(y * map.width)..<((y + 1) * map.width)] where glyph != Sculpture.empty {
                        guard let child = children[glyph] else { throw SculptureCompositionError.unboundGlyph(glyph) }
                        let added = child.placements + 1
                        guard added <= SculptureComposition.maximumPlacements - occurrences else {
                            throw SculptureCompositionError.excessivePlacements
                        }
                        occurrences += added
                    }
                }
            }
            info = CompositionInfo(
                width: map.width * map.tileSize.width,
                height: map.height * map.tileSize.height,
                depth: map.depth * map.tileSize.depth,
                graphDepth: graphDepth,
                placements: occurrences
            )
        }
        let modelVolume = model.resolvedVolume
        guard modelVolume <= SculptureComposition.maximumResolvedVoxelBytes - volume else {
            throw SculptureCompositionError.excessiveVolume
        }
        guard info.placements <= SculptureComposition.maximumPlacements - placements else {
            throw SculptureCompositionError.excessivePlacements
        }
        volume += modelVolume
        placements += info.placements
        visiting.remove(id)
        resolved[id] = info
        return info
    }
}

private struct CompositionResolver {
    let models: [String: SculptureCompositionModel]
    let rootID: String
    let title: String
    private var cache: [String: Sculpture] = [:]

    init(models: [String: SculptureCompositionModel], rootID: String, title: String) {
        self.models = models
        self.rootID = rootID
        self.title = title
    }

    mutating func resolve(_ id: String) throws -> Sculpture {
        try Task.checkCancellation()
        if let sculpture = cache[id] { return sculpture }
        guard let model = models[id] else { throw SculptureCompositionError.unknownModel(id) }
        let sculpture: Sculpture
        switch model {
        case .sculpture(let leaf): sculpture = leaf
        case .tiles(let map):
            let width = map.width * map.tileSize.width
            let height = map.height * map.tileSize.height
            var layers = Array(
                repeating: Array(repeating: Sculpture.empty, count: width * height),
                count: map.depth * map.tileSize.depth
            )
            let bindings = Dictionary(uniqueKeysWithValues: map.bindings.map { ($0.glyph, $0) })
            for (z, layer) in map.layers.enumerated() {
                for y in 0..<map.height {
                    try Task.checkCancellation()
                    for x in 0..<map.width {
                        let glyph = layer[y * map.width + x]
                        guard glyph != Sculpture.empty else { continue }
                        guard let binding = bindings[glyph] else { throw SculptureCompositionError.unboundGlyph(glyph) }
                        let child = try resolve(binding.modelID)
                        let origin = SculptureCell(
                            x: x * map.tileSize.width,
                            y: y * map.tileSize.height,
                            z: z * map.tileSize.depth
                        )
                        for childZ in 0..<child.depth where child.containsOccupiedCells(inLayer: childZ) {
                            for childY in 0..<child.height {
                                try Task.checkCancellation()
                                guard child.containsOccupiedCells(inRow: childY, ofLayer: childZ) else { continue }
                                for childX in 0..<child.width {
                                    let voxel = child.layers[childZ][childY * child.width + childX]
                                    guard voxel != Sculpture.empty else { continue }
                                    let destination: (x: Int, y: Int)
                                    switch binding.quarterTurns {
                                    case 1: destination = (child.height - childY - 1, childX)
                                    case 2: destination = (child.width - childX - 1, child.height - childY - 1)
                                    case 3: destination = (childY, child.width - childX - 1)
                                    default: destination = (childX, childY)
                                    }
                                    layers[origin.z + childZ][
                                        (origin.y + destination.y) * width + origin.x + destination.x
                                    ] = voxel
                                }
                            }
                        }
                    }
                }
            }
            try Task.checkCancellation()
            sculpture = try Sculpture(title: id == rootID ? title : id, width: width, height: height, layers: layers)
        }
        try Task.checkCancellation()
        cache[id] = sculpture
        return sculpture
    }
}

extension SculptureCompositionModel {
    /// The expanded voxel volume this model adds to the resolved-volume budget. Validation and early insertion
    /// checks share this one accounting, which counts every unique model once, including unused ones.
    internal var resolvedVolume: Int {
        switch self {
        case .sculpture(let sculpture): sculpture.width * sculpture.height * sculpture.depth
        case .tiles(let map):
            (map.width * map.tileSize.width) * (map.height * map.tileSize.height) * (map.depth * map.tileSize.depth)
        }
    }
}
