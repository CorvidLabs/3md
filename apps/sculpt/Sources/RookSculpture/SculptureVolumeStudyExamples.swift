import Foundation

/// Reusable stress-study scenes whose address domain exceeds a single editable model.
public enum SculptureVolumeStudyExamples {
    public static let extent = 1_024
    public static let chunkDimension = 64

    /// Fills a 1024-cubed domain using 4,096 references to one solid 64-cubed model.
    /// Construction stores only the shared model and placement records, never a dense world buffer.
    public static func denseEquivalentWorld() throws -> SculptureWorld {
        SculptureGenerationProbe.record("solid-1024-world")
        try Task.checkCancellation()
        let dimension = chunkDimension
        let layer = [UInt8](repeating: StudyMaterial.stone, count: dimension * dimension)
        let cube = try Sculpture(
            title: "Shared solid 64-cubed chunk",
            width: dimension,
            height: dimension,
            layers: [[UInt8]](repeating: layer, count: dimension)
        )
        let library = try library(title: "Dense-equivalent chunk library", models: ["solid": .sculpture(cube)])
        let chunks = extent / dimension
        var instances: [SculptureWorldInstance] = []
        instances.reserveCapacity(chunks * chunks * chunks)
        for z in 0..<chunks {
            for y in 0..<chunks {
                try Task.checkCancellation()
                for x in 0..<chunks {
                    instances.append(
                        try SculptureWorldInstance(
                            id: "solid-\(x)-\(y)-\(z)",
                            modelID: "solid",
                            origin: point(x: x, y: y, z: z)
                        )
                    )
                }
            }
        }
        return try SculptureWorld(title: "1024-cubed dense-equivalent world", library: library, instances: instances)
    }

    /// A sparse valley and elevated island archipelago across the same 1024-cubed address domain.
    /// Disjoint chunk boxes make actual occupancy the sum of their model occupancies, including repeats.
    public static func landscapeWorld() throws -> SculptureWorld {
        SculptureGenerationProbe.record("skyreach-1024-world")
        try Task.checkCancellation()
        var models: [String: SculptureCompositionModel] = [:]
        for kind in StudyModelKind.allCases {
            try Task.checkCancellation()
            models[kind.rawValue] = .sculpture(try StudyVolume.make(kind))
        }
        let library = try library(title: "Skyreach reusable landscape library", models: models)
        let chunks = extent / chunkDimension
        var instances: [SculptureWorldInstance] = []
        instances.reserveCapacity(chunks * chunks + 24)
        for z in 0..<chunks {
            try Task.checkCancellation()
            for x in 0..<chunks {
                let kind = groundKind(x: x, z: z)
                instances.append(
                    try SculptureWorldInstance(
                        id: "valley-\(x)-\(z)",
                        modelID: kind.rawValue,
                        origin: point(x: x, y: chunks - 1, z: z)
                    )
                )
            }
        }
        let islands = [(3, 3), (12, 3), (5, 7), (10, 8), (3, 12), (12, 12)]
        for (level, y) in [0, 4, 8, 12].enumerated() {
            try Task.checkCancellation()
            for (index, position) in islands.enumerated() {
                instances.append(
                    try SculptureWorldInstance(
                        id: "sky-\(level)-\(index)",
                        modelID: index.isMultiple(of: 3)
                            ? StudyModelKind.citadel.rawValue : StudyModelKind.island.rawValue,
                        origin: point(x: position.0, y: y, z: position.1)
                    )
                )
            }
        }
        return try SculptureWorld(title: "Skyreach 1024-cubed landscape", library: library, instances: instances)
    }

    private static func point(x: Int, y: Int, z: Int) -> SculptureWorldPoint {
        SculptureWorldPoint(
            x: Int64(x * chunkDimension),
            y: Int64(y * chunkDimension),
            z: Int64(z * chunkDimension)
        )
    }

    private static func library(
        title: String,
        models: [String: SculptureCompositionModel]
    ) throws -> SculptureComposition {
        let identifiers = models.keys.sorted()
        let glyphs = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ".utf8)
        let bindings = try identifiers.enumerated().map { index, identifier in
            try SculptureModelBinding(glyph: glyphs[index], modelID: identifier)
        }
        let root = try SculptureTileMap(
            width: 1,
            height: 1,
            layers: [[glyphs[0]]],
            tileSize: SculptureTileSize(width: chunkDimension, height: chunkDimension, depth: chunkDimension),
            bindings: bindings
        )
        var libraryModels = models
        libraryModels["study-root"] = .tiles(root)
        return try SculptureComposition(title: title, rootID: "study-root", models: libraryModels)
    }

    private static func groundKind(x: Int, z: Int) -> StudyModelKind {
        if x == 7 || x == 8 { return .river }
        if (x == 3 && z == 4) || (x == 12 && z == 11) { return .castle }
        if x <= 1 || x >= 14 { return .mountain }
        if (x + z * 3).isMultiple(of: 5) { return .terraces }
        return (x * 7 + z * 11).isMultiple(of: 3) ? .forest : .meadow
    }
}

private enum StudyModelKind: String, CaseIterable {
    case meadow, forest, river, castle, mountain, terraces, island, citadel

    var title: String {
        switch self {
        case .meadow: "Rolling meadow"
        case .forest: "Pine forest"
        case .river: "River and stone bridge"
        case .castle: "Valley castle"
        case .mountain: "Mountain ridge"
        case .terraces: "Irrigated terraces"
        case .island: "Floating wooded island"
        case .citadel: "Sky citadel"
        }
    }
}

private enum StudyMaterial {
    static let stone: UInt8 = 64
    static let soil: UInt8 = 61
    static let grass: UInt8 = 111
    static let leaves: UInt8 = 58
    static let water: UInt8 = 43
    static let foam: UInt8 = 45
    static let crop: UInt8 = 42
    static let roof: UInt8 = 120
}

private struct StudyVolume {
    private static let dimension = SculptureVolumeStudyExamples.chunkDimension
    private var layers = [[UInt8]](
        repeating: [UInt8](repeating: Sculpture.empty, count: Self.dimension * Self.dimension),
        count: Self.dimension
    )

    static func make(_ kind: StudyModelKind) throws -> Sculpture {
        var volume = StudyVolume()
        try volume.ground(kind)
        try Task.checkCancellation()
        switch kind {
        case .forest:
            for z in [12, 32, 52] {
                for x in [12, 32, 52] { volume.tree(x: x, z: z, floor: 42 + ((x / 8 + z / 8) % 3)) }
            }
        case .river:
            volume.box(x: 0..<64, y: 36..<39, z: 28..<36, glyph: StudyMaterial.stone)
            for z in [28, 35] { volume.box(x: 0..<64, y: 33..<36, z: z..<(z + 1), glyph: StudyMaterial.soil) }
        case .castle: volume.castle(inset: 10, floor: 44, towers: 14)
        case .island:
            for (x, z) in [(20, 24), (42, 24), (32, 42)] {
                volume.tree(x: x, z: z, floor: 40 + (abs(x - 32) + abs(z - 32)) / 12)
            }
        case .citadel:
            volume.castle(inset: 18, floor: 43, towers: 8)
            volume.box(x: 28..<36, y: 5..<40, z: 28..<36, glyph: StudyMaterial.stone)
            volume.box(x: 26..<38, y: 5..<8, z: 26..<38, glyph: StudyMaterial.roof)
            volume.box(x: 32..<33, y: 0..<5, z: 32..<33, glyph: StudyMaterial.soil)
            volume.box(x: 33..<42, y: 1..<4, z: 32..<33, glyph: StudyMaterial.crop)
        case .meadow, .mountain, .terraces: break
        }
        try Task.checkCancellation()
        return try Sculpture(title: kind.title, width: Self.dimension, height: Self.dimension, layers: volume.layers)
    }

    private mutating func ground(_ kind: StudyModelKind) throws {
        for z in 0..<Self.dimension {
            try Task.checkCancellation()
            for x in 0..<Self.dimension {
                let distance = abs(x - 32) + abs(z - 32)
                let top: Int
                switch kind {
                case .meadow, .forest: top = 42 + ((x / 8 + z / 8) % 3)
                case .river: top = (24..<40).contains(x) ? 48 : 43
                case .castle: top = 44
                case .mountain: top = 10 + distance / 2
                case .terraces: top = 28 + min(5, distance / 8) * 4
                case .island, .citadel:
                    guard distance <= 29 else { continue }
                    top = 40 + distance / 12
                }
                let bottom = kind == .island || kind == .citadel ? min(64, 64 - distance / 3) : 64
                for y in top..<bottom {
                    let glyph: UInt8
                    if y == top {
                        glyph = kind == .terraces ? StudyMaterial.crop : StudyMaterial.grass
                    } else {
                        glyph = y < top + 3 ? StudyMaterial.soil : StudyMaterial.stone
                    }
                    set(x: x, y: y, z: z, glyph: glyph)
                }
                if kind == .river, (24..<40).contains(x) {
                    for y in 42..<top {
                        let glyph = y == 42 && (x + z).isMultiple(of: 11) ? StudyMaterial.foam : StudyMaterial.water
                        set(x: x, y: y, z: z, glyph: glyph)
                    }
                }
                if kind == .terraces, distance.isMultiple(of: 8) {
                    set(x: x, y: top, z: z, glyph: StudyMaterial.water)
                }
            }
        }
    }

    private mutating func tree(x: Int, z: Int, floor: Int) {
        box(x: x..<(x + 1), y: (floor - 24)..<floor, z: z..<(z + 1), glyph: StudyMaterial.soil)
        for y in (floor - 26)..<(floor - 7) {
            let radius = min(7, (y - floor + 28) / 3)
            for dz in (-radius)...radius {
                for dx in (-radius)...radius where abs(dx) + abs(dz) <= radius + 1 {
                    set(x: x + dx, y: y, z: z + dz, glyph: StudyMaterial.leaves)
                }
            }
        }
    }

    private mutating func castle(inset: Int, floor: Int, towers: Int) {
        let opposite = Self.dimension - inset - 1
        for z in inset...opposite {
            for x in inset...opposite where x <= inset + 2 || x >= opposite - 2 || z <= inset + 2 || z >= opposite - 2 {
                box(x: x..<(x + 1), y: (towers + 8)..<floor, z: z..<(z + 1), glyph: StudyMaterial.stone)
                if (x + z) % 4 < 2 {
                    box(x: x..<(x + 1), y: (towers + 5)..<(towers + 8), z: z..<(z + 1), glyph: StudyMaterial.stone)
                }
            }
        }
        for z in [inset, opposite] {
            for x in [inset, opposite] {
                for dz in -3...3 {
                    for dx in -3...3 where abs(dx) == 3 || abs(dz) == 3 {
                        box(
                            x: (x + dx)..<(x + dx + 1),
                            y: towers..<floor,
                            z: (z + dz)..<(z + dz + 1),
                            glyph: StudyMaterial.stone
                        )
                    }
                }
                box(
                    x: (x - 4)..<(x + 5),
                    y: (towers - 2)..<(towers + 1),
                    z: (z - 4)..<(z + 5),
                    glyph: StudyMaterial.roof
                )
            }
        }
        box(x: 28..<36, y: (floor - 10)..<floor, z: (opposite - 2)..<(opposite + 1), glyph: Sculpture.empty)
    }

    private mutating func box(x: Range<Int>, y: Range<Int>, z: Range<Int>, glyph: UInt8) {
        for depth in z {
            for row in y {
                for column in x { set(x: column, y: row, z: depth, glyph: glyph) }
            }
        }
    }

    private mutating func set(x: Int, y: Int, z: Int, glyph: UInt8) {
        guard (0..<Self.dimension).contains(x), (0..<Self.dimension).contains(y), (0..<Self.dimension).contains(z)
        else { return }
        layers[z][y * Self.dimension + x] = glyph
    }
}
