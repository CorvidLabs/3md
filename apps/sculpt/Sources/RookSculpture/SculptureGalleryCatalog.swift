import Foundation

/// The kind of scene a gallery entry creates, which selects the editor that opens it.
public enum SculptureGalleryKind: String, Codable, CaseIterable, Sendable {
    /// One editable voxel sculpture for the main editor.
    case model
    /// A reusable model graph for the composition editor.
    case composition
    /// Sparse placements for the world editor.
    case world
}

/// Cells along each axis. A composition measures its expanded root; a world measures the bounding box of its
/// placements, saturating at `Int.max` for anchors farther apart than an `Int` can count.
public struct SculptureGalleryExtent: Hashable, Codable, Sendable {
    public let width: Int
    public let height: Int
    public let depth: Int

    /// Records a declared extent.
    public init(width: Int, height: Int, depth: Int) {
        self.width = width
        self.height = height
        self.depth = depth
    }

    /// Measures an already created scene without expanding it. An empty world measures zero on every axis.
    public init(of scene: SculptureScene) {
        switch scene {
        case .voxels(let sculpture):
            self.init(width: sculpture.width, height: sculpture.height, depth: sculpture.depth)
        case .composition(let composition):
            let size = composition.models[composition.rootID].map(Self.size(of:)) ?? (width: 0, height: 0, depth: 0)
            self.init(width: size.width, height: size.height, depth: size.depth)
        case .world(let world):
            self = Self.bounds(of: world)
        }
    }

    // MARK: - Private Methods

    private static func size(of model: SculptureCompositionModel) -> (width: Int, height: Int, depth: Int) {
        switch model {
        case .sculpture(let sculpture): (sculpture.width, sculpture.height, sculpture.depth)
        case .tiles(let map):
            (map.width * map.tileSize.width, map.height * map.tileSize.height, map.depth * map.tileSize.depth)
        }
    }

    private static func bounds(of world: SculptureWorld) -> Self {
        var minimum: (x: Int64, y: Int64, z: Int64) = (.max, .max, .max)
        var maximum: (x: Int64, y: Int64, z: Int64) = (.min, .min, .min)
        var sizes: [String: (width: Int, height: Int, depth: Int)] = [:]
        for instance in world.instances {
            let size: (width: Int, height: Int, depth: Int)
            if let cached = sizes[instance.modelID] {
                size = cached
            } else {
                size = world.library.models[instance.modelID].map(Self.size(of:)) ?? (0, 0, 0)
                sizes[instance.modelID] = size
            }
            let odd = !instance.quarterTurns.isMultiple(of: 2)
            let origin = instance.origin
            // Anchors stay at or below Int64.max - 256 and models within 256 cells, so these sums cannot overflow.
            minimum = (min(minimum.x, origin.x), min(minimum.y, origin.y), min(minimum.z, origin.z))
            maximum = (
                max(maximum.x, origin.x + Int64(odd ? size.height : size.width)),
                max(maximum.y, origin.y + Int64(odd ? size.width : size.height)),
                max(maximum.z, origin.z + Int64(size.depth))
            )
        }
        guard !world.instances.isEmpty else { return Self(width: 0, height: 0, depth: 0) }
        return Self(
            width: span(from: minimum.x, to: maximum.x),
            height: span(from: minimum.y, to: maximum.y),
            depth: span(from: minimum.z, to: maximum.z)
        )
    }

    private static func span(from lower: Int64, to upper: Int64) -> Int {
        let (difference, overflow) = upper.subtractingReportingOverflow(lower)
        guard !overflow, let value = Int(exactly: difference) else { return .max }
        return value
    }
}

/// One built-in example as plain metadata. Entries hold no scene, so listing them generates nothing.
public struct SculptureGalleryEntry: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let title: String
    public let summary: String
    public let category: String
    /// Which editor opens the created scene.
    public let kind: SculptureGalleryKind
    /// The created scene's extent, declared without generating it.
    public let extent: SculptureGalleryExtent
    /// The generating formula of a math ladder entry; nil for authored examples.
    public let formula: String?

    /// Records entry metadata. Only entries listed by `SculptureGalleryCatalog` can create a scene.
    public init(
        id: String,
        title: String,
        summary: String,
        category: String,
        kind: SculptureGalleryKind,
        extent: SculptureGalleryExtent,
        formula: String? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.category = category
        self.kind = kind
        self.extent = extent
        self.formula = formula
    }
}

/// Every built-in example in one list: the voxel catalog, the five math models, and the composition and world
/// examples. Listing reads static metadata only; `scene(for:progress:)` creates one entry's scene on demand.
public enum SculptureGalleryCatalog {
    /// Every entry: voxel models, the five math models, then compositions and worlds.
    public static let entries: [SculptureGalleryEntry] = table.map(\.entry)

    /// The five math ladder models from 16 cells to 256 cells on each axis, smallest first.
    public static let mathLadder: [SculptureGalleryEntry] = makeMathLadder()

    // MARK: - Public Methods

    /// Returns the listed entry with this identity.
    /// - Parameter id: The stable entry identity.
    /// - Returns: The entry, or nil when the catalog has no such entry.
    public static func entry(id: String) -> SculptureGalleryEntry? {
        sources[id]?.entry
    }

    /// Creates a listed entry's scene and no other. Math ladder entries check cancellation and report progress per
    /// layer; other entries check cancellation before and after building only that entry and report only
    /// their start and end. An authored voxel entry builds its own volume without the rest of the voxel catalog.
    /// - Parameters:
    ///   - entry: An entry exactly as `entries` lists it.
    ///   - progress: Receives the completed fraction from zero to one.
    /// - Returns: The scene, whose kind and extent match the entry.
    public static func scene(
        for entry: SculptureGalleryEntry,
        progress: @Sendable (Double) async -> Void = { _ in }
    ) async throws -> SculptureScene {
        guard let listed = sources[entry.id], listed.entry == entry else {
            throw SculptureGalleryError.unknownEntry(entry.id)
        }
        try Task.checkCancellation()
        await progress(0)
        let scene: SculptureScene
        switch listed.source {
        case .voxel:
            try Task.checkCancellation()
            guard let example = SculptureExamples.example(id: entry.id) else {
                throw SculptureGalleryError.unknownEntry(entry.id)
            }
            try Task.checkCancellation()
            scene = .voxels(example.sculpture)
        case .courtyard: scene = .composition(try SculptureCompositionExamples.courtyard())
        case .blockhavenComposition: scene = .composition(try SculptureBlockWorldExamples.composition())
        case .wideWorld: scene = .world(try SculptureWorldExamples.wideWorld())
        case .blockhavenWorld: scene = .world(try SculptureBlockWorldExamples.world())
        case .solidStudy: scene = .world(try SculptureVolumeStudyExamples.denseEquivalentWorld())
        case .landscapeStudy: scene = .world(try SculptureVolumeStudyExamples.landscapeWorld())
        case .mathModel(let model):
            scene = .voxels(try await SculptureMathExamples.sculpture(model, progress: progress))
        }
        try Task.checkCancellation()
        await progress(1)
        return scene
    }

    // MARK: - Internal

    /// Which builder creates an entry's scene.
    internal enum Source: Sendable {
        case voxel
        case courtyard, blockhavenComposition
        case wideWorld, blockhavenWorld, solidStudy, landscapeStudy
        case mathModel(SculptureMathExamples.Model)
    }

    /// One listed entry and the builder of its scene.
    internal struct Listing: Sendable {
        internal let entry: SculptureGalleryEntry
        internal let source: Source
    }

    /// Builds the listing from static metadata, uncached, so a test can check that listing runs no builder.
    /// - Returns: Every listing in `entries` order.
    internal static func makeTable() -> [Listing] {
        voxelExamples.map { id, title, summary, category, size in
            Listing(
                entry: SculptureGalleryEntry(
                    id: id,
                    title: title,
                    summary: summary,
                    category: category,
                    kind: .model,
                    extent: SculptureGalleryExtent(width: size, height: size, depth: size)
                ),
                source: .voxel
            )
        }
            + SculptureMathExamples.Model.allCases.map { Listing(entry: entry(for: $0), source: .mathModel($0)) }
            + [
                authored(
                    "courtyard-of-courtyards",
                    "Courtyard of courtyards",
                    "Eight shared gardens of trees and gates nested inside one courtyard map.",
                    "Compositions",
                    .composition,
                    (144, 24, 144),
                    .courtyard
                ),
                authored(
                    "blockhaven-composition",
                    "Blockhaven valley",
                    "Thirty-six shared terrain chunks with a river, village, castle, ruin and caves.",
                    "Landscapes",
                    .composition,
                    (192, 64, 192),
                    .blockhavenComposition
                ),
                authored(
                    "gardens-wide-world",
                    "Gardens without a boundary",
                    "Four placements of one garden, including one a trillion cells away.",
                    "Sparse worlds",
                    .world,
                    (1_000_000_000_048, 24, 1_000_000_000_304),
                    .wideWorld
                ),
                authored(
                    "blockhaven-world",
                    "Blockhaven valley",
                    "The Blockhaven chunks placed as thirty-six sparse world instances.",
                    "Landscapes",
                    .world,
                    (192, 64, 192),
                    .blockhavenWorld
                ),
                authored(
                    "solid-1024-world",
                    "1024-cubed dense-equivalent world",
                    "4,096 placements of one solid 64-cell chunk fill a 1,024-cell cube.",
                    "Volume studies",
                    .world,
                    (1_024, 1_024, 1_024),
                    .solidStudy
                ),
                authored(
                    "skyreach-1024-world",
                    "Skyreach 1024-cubed landscape",
                    "A valley floor and floating islands from eight shared 64-cell chunks.",
                    "Volume studies",
                    .world,
                    (1_024, 1_024, 1_024),
                    .landscapeStudy
                ),
            ]
    }

    /// Builds the math ladder entries from static metadata, uncached, so a test can check that it runs no builder.
    /// - Returns: The five model rungs, from 16 cells to 256 cells on each axis.
    internal static func makeMathLadder() -> [SculptureGalleryEntry] {
        SculptureMathExamples.Model.allCases.map(entry(for:))
    }

    // MARK: - Private

    private static let table: [Listing] = makeTable()

    private static let sources: [String: Listing] = Dictionary(
        uniqueKeysWithValues: table.map { ($0.entry.id, $0) }
    )

    private static let mathCategory = "Math ladder"

    private static func entry(for model: SculptureMathExamples.Model) -> SculptureGalleryEntry {
        SculptureGalleryEntry(
            id: model.id,
            title: model.title,
            summary: model.summary,
            category: mathCategory,
            kind: .model,
            extent: SculptureGalleryExtent(width: model.dimension, height: model.dimension, depth: model.dimension),
            formula: model.formula
        )
    }

    private static func authored(
        _ id: String,
        _ title: String,
        _ summary: String,
        _ category: String,
        _ kind: SculptureGalleryKind,
        _ extent: (Int, Int, Int),
        _ source: Source
    ) -> Listing {
        Listing(
            entry: SculptureGalleryEntry(
                id: id,
                title: title,
                summary: summary,
                category: category,
                kind: kind,
                extent: SculptureGalleryExtent(width: extent.0, height: extent.1, depth: extent.2)
            ),
            source: source
        )
    }

    /// Static metadata for `SculptureExamples.all`, in its order, so listing never builds those volumes.
    /// A test compares this table with the generated catalog so the two cannot drift.
    private static let voxelExamples: [(String, String, String, String, Int)] = [
        ("character-orb", "Character orb", "A hollow shell with a readable interior.", "Sculptures", 16),
        ("woven-torus", "Woven torus", "Follow the striped ring around its open center.", "Sculptures", 24),
        ("moon-gate", "Moon gate", "A freestanding arch, stepped plinth and lanterns.", "Sculptures", 24),
        ("spiral-tower", "Spiral tower", "A helix climbing around a slender central mast.", "Sculptures", 24),
        ("crystal-garden", "Crystal garden", "Faceted crystals growing from a low rocky bed.", "Sculptures", 24),
        (
            "little-rocket", "Little rocket", "A hollow hull, round window, fins and a bright plume.", "Sculptures",
            24
        ),
        (
            "pixel-bonsai", "Pixel bonsai", "A branching trunk and cloudlike canopy in a shallow pot.", "Sculptures",
            24
        ),
        ("orbital-rings", "Orbital rings", "Three perpendicular hoops around a small star.", "Sculptures", 24),
        (
            "hill-observatory", "Hill observatory", "A domed tower on a stepped hill, with a winding stair.",
            "Sculptures", 24
        ),
        ("terraced-island", "Terraced island", "Raised land, a winding stream, tiny trees and a bridge.", "Maps", 24),
        ("canal-city", "Canal city", "A canal divides roofed blocks, quays and a central bridge.", "Maps", 24),
        ("alpine-valley", "Alpine valley", "Snowy peaks frame a river, a cabin and a forest.", "Maps", 24),
        (
            "wandering-cartographer", "Wandering cartographer",
            "A posed explorer with a face, coat, boots, map and walking staff.", "Characters", 64
        ),
        (
            "clockwork-dragon", "Clockwork dragon",
            "Raised membrane wings, horns, an open jaw, four clawed feet and a curling tail.", "Creatures", 64
        ),
        (
            "woodland-fox", "Woodland fox",
            "Pointed ears, a long muzzle, separated paws and a sweeping pale-tipped tail.", "Creatures", 64
        ),
        (
            "deep-sea-whale", "Deep sea whale",
            "A broad whale with flippers, a notched fluke, throat pleats and a branching spout.", "Creatures", 64
        ),
        (
            "citadel-of-arches", "Citadel of arches",
            "A moated castle with four towers, battlements, an open gate, keep and courtyard.", "Architecture", 64
        ),
        (
            "sky-island-village", "Sky island village",
            "Three floating islands, rope bridges, roofed homes, trees and a windmill.", "Worlds", 64
        ),
        (
            "canyon-waterfall", "Canyon waterfall",
            "Layered canyon cliffs, a waterfall, river, hollow stone arch, cave and watchtower.", "Worlds", 64
        ),
        (
            "moonlit-harbor", "Moonlit harbor",
            "A crescent moon above a coastal village, lighthouse, wooden piers and sailboats.", "Worlds", 64
        ),
        (
            "grand-solar-system", "Grand solar system",
            "Eight planets, rings, moons and a comet at artistic scale with compressed distances.", "Space", 256
        ),
    ]
}

/// A refused gallery request.
public enum SculptureGalleryError: Error, LocalizedError, Equatable, Sendable {
    /// The entry is not listed by the catalog, or differs from the listed entry with its identity.
    case unknownEntry(String)

    public var errorDescription: String? {
        switch self {
        case .unknownEntry(let id): "The example '\(id)' is not in the built-in gallery."
        }
    }
}
