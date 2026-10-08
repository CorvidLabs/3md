import Foundation

/// Bounded, host-independent checks for a batch of explicitly chosen files.
///
/// Hosts perform the file I/O. They call `admitFileCount` and `admitBytes` before reading content, and `admit`
/// right after each file's bytes are available, so an oversized batch is refused early and by filename.
public struct SculptureInsertionPlan: Sendable {
    public static let maximumFiles = SculptureComposition.maximumModels
    public static let maximumBytes = SculptureDocumentCodec.maximumBytes
    public static let maximumDiscoveryEntries = 4_096

    /// The tile size a composition reserves for each inserted model, or nil for worlds and generic limits.
    public let tileSize: SculptureTileSize?
    private let capacity: Capacity
    private let parentModelCount: Int
    private var incomingModels = 0
    private var byteCount = 0
    private var resolvedVolume = 0

    private enum Capacity: Sendable {
        case unconstrained
        case composition(freeCells: Int, glyphs: Int)
        case world(placed: Int)
    }

    /// Generic file, byte and model-count bounds when no parent scene is known.
    public init() {
        tileSize = nil
        capacity = .unconstrained
        parentModelCount = 0
    }

    /// Bounds for inserting into `parent`, filling consecutive tiles from `cell`.
    public init(composition parent: SculptureComposition, at cell: SculptureCell) throws {
        guard case .tiles(let map)? = parent.models[parent.rootID],
            (0..<map.width).contains(cell.x), (0..<map.height).contains(cell.y), (0..<map.depth).contains(cell.z)
        else { throw SculptureInsertionError.invalidSelection }
        let start = cell.z * map.width * map.height + cell.y * map.width + cell.x
        tileSize = map.tileSize
        capacity = .composition(
            freeCells: map.width * map.height * map.depth - start,
            glyphs: SculptureSceneInsertion.availableGlyphs(for: map).count
        )
        parentModelCount = parent.models.count
        resolvedVolume = parent.models.values.reduce(0) { $0 + $1.resolvedVolume }
    }

    /// Bounds for inserting into a sparse `parent`, which has no tile size.
    public init(world parent: SculptureWorld) {
        tileSize = nil
        capacity = .world(placed: parent.instances.count)
        parentModelCount = parent.library.models.count
        resolvedVolume = parent.library.models.values.reduce(0) { $0 + $1.resolvedVolume }
    }

    /// Refuses a batch of `count` files that cannot fit the parent, before any file is read.
    public func admitFileCount(_ count: Int) throws {
        guard count > 0 else { throw SculptureInsertionError.noInputs }
        guard count <= Self.maximumFiles else {
            throw SculptureInsertionError.tooManyFiles(count: count, maximum: Self.maximumFiles)
        }
        switch capacity {
        case .unconstrained: break
        case .composition(let freeCells, let glyphs):
            guard count <= freeCells else {
                throw SculptureInsertionError.insufficientCells(needed: count, available: freeCells)
            }
            guard count <= glyphs else {
                throw SculptureInsertionError.noAvailableGlyph(needed: count, available: glyphs)
            }
        case .world(let placed):
            guard count <= SculptureWorld.maximumInstances - placed else {
                throw SculptureInsertionError.tooManyPlacements(
                    current: placed,
                    incoming: count,
                    maximum: SculptureWorld.maximumInstances
                )
            }
        }
        // Every file adds at least one model definition.
        guard count <= SculptureComposition.maximumModels - parentModelCount else {
            throw SculptureInsertionError.tooManyModels(
                current: parentModelCount,
                incoming: count,
                maximum: SculptureComposition.maximumModels
            )
        }
    }

    /// Adds `size` bytes to the running total and refuses by name when the batch would exceed the shared budget.
    public mutating func admitBytes(_ size: Int, source: String) throws {
        guard size >= 0, size <= Self.maximumBytes - byteCount else {
            throw SculptureInsertionError.aggregateBytesExceeded(source: source, maximum: Self.maximumBytes)
        }
        byteCount += size
    }

    /// Decodes one file's bytes and checks its kind, tile fit, cumulative model count and resolved volume.
    /// A compact voxel file whose header does not fit a tile or the volume budget is refused by name before it
    /// is decompressed, so a batch of large volumes cannot be decoded past the 64 MiB limit.
    public mutating func admit(_ data: Data, source: String) throws -> SculptureInsertionInput {
        try Task.checkCancellation()
        if let header = SculptureBinaryCodec.dimensions(inHeader: data) {
            if let tileSize { try Self.requireFit(header, tileSize: tileSize, source: source) }
            try requireVolume(header.width * header.height * header.depth, source: source)
        }
        let input = try Self.decode(data, source: source)
        do { try admit(input) } catch let error as SculptureInsertionError {
            switch error {
            case .tooManyModels, .mismatchedSnapshot, .unsupportedChild:
                throw SculptureInsertionError.source(name: source, reason: error.localizedDescription)
            default: throw error
            }
        }
        return input
    }

    /// Checks an already decoded input: supported kind, snapshot agreement, tile fit, cumulative model count and
    /// cumulative resolved volume, using the same per-model accounting as composition validation.
    public mutating func admit(_ input: SculptureInsertionInput) throws {
        try Self.validate(input, tileSize: tileSize)
        incomingModels += Self.modelCount(of: input)
        guard incomingModels <= SculptureComposition.maximumModels - parentModelCount else {
            throw SculptureInsertionError.tooManyModels(
                current: parentModelCount,
                incoming: incomingModels,
                maximum: SculptureComposition.maximumModels
            )
        }
        let volume = Self.resolvedVolume(of: input)
        try requireVolume(volume, source: input.displayName)
        resolvedVolume += volume
    }

    private func requireVolume(_ volume: Int, source: String) throws {
        guard volume <= SculptureComposition.maximumResolvedVoxelBytes - resolvedVolume else {
            throw SculptureInsertionError.resolvedVolumeExceeded(
                source: source,
                maximum: SculptureComposition.maximumResolvedVoxelBytes
            )
        }
    }

    private static func resolvedVolume(of input: SculptureInsertionInput) -> Int {
        switch input.scene {
        case .voxels(let sculpture): SculptureCompositionModel.sculpture(sculpture).resolvedVolume
        case .composition(let composition): composition.models.values.reduce(0) { $0 + $1.resolvedVolume }
        case .world: 0
        }
    }

    /// Decodes native or portable bytes into an input named for its source.
    /// Sparse worlds and unsupported documents are refused naming the source.
    public static func decode(_ data: Data, source: String) throws -> SculptureInsertionInput {
        do {
            let opened = try SculptureSceneReader.decode(data)
            if case .world = opened.scene {
                throw SculptureInsertionError.source(
                    name: source,
                    reason: SculptureInsertionError.unsupportedChild.localizedDescription
                )
            }
            return SculptureInsertionInput(scene: opened.scene, snapshot: opened.snapshot, sourceName: source)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as SculptureInsertionError {
            throw error
        } catch {
            throw SculptureInsertionError.source(name: source, reason: SculptureDiagnosticMessage.describe(error))
        }
    }

    /// Natural, deterministic filename order: the last path component by Finder-style comparison, then the full path.
    public static func precedes(_ lhsPath: String, _ rhsPath: String) -> Bool {
        let lhsName = (lhsPath as NSString).lastPathComponent
        let rhsName = (rhsPath as NSString).lastPathComponent
        switch lhsName.localizedStandardCompare(rhsName) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return lhsPath < rhsPath
        }
    }

    /// Readable and compact 3md files are the insertable extensions, in any letter case.
    public static func isSupportedFile(pathExtension: String) -> Bool {
        ["3md", "3mdb"].contains(pathExtension.lowercased())
    }

    // MARK: - Shared checks

    internal static func validate(_ input: SculptureInsertionInput, tileSize: SculptureTileSize?) throws {
        if case .world = input.scene { throw SculptureInsertionError.unsupportedChild }
        if let snapshot = input.snapshot, snapshot.scene != input.scene {
            throw SculptureInsertionError.mismatchedSnapshot
        }
        guard let tileSize else { return }
        let dimensions: (width: Int, height: Int, depth: Int)
        switch input.scene {
        case .voxels(let sculpture):
            dimensions = (sculpture.width, sculpture.height, sculpture.depth)
        case .composition(let composition):
            guard case .tiles(let map)? = composition.models[composition.rootID] else {
                throw SculptureCompositionError.invalidRoot
            }
            dimensions = (
                map.width * map.tileSize.width, map.height * map.tileSize.height, map.depth * map.tileSize.depth
            )
        case .world: return
        }
        try requireFit(dimensions, tileSize: tileSize, source: input.displayName)
    }

    internal static func modelCount(of input: SculptureInsertionInput) -> Int {
        switch input.scene {
        case .voxels: 1
        case .composition(let composition): composition.models.count
        case .world: 0
        }
    }

    private static func requireFit(
        _ dimensions: (width: Int, height: Int, depth: Int),
        tileSize: SculptureTileSize,
        source: String
    ) throws {
        guard dimensions.width <= tileSize.width, dimensions.height <= tileSize.height,
            dimensions.depth <= tileSize.depth
        else {
            throw SculptureInsertionError.modelDoesNotFit(
                source: source,
                required: "\(dimensions.width) × \(dimensions.height) × \(dimensions.depth)",
                current: "\(tileSize.width) × \(tileSize.height) × \(tileSize.depth)"
            )
        }
    }
}
