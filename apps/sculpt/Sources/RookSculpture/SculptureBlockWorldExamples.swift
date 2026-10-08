import Foundation

/// An original block landscape, authored as reusable 3md chunks rather than a game or external map format.
public enum SculptureBlockWorldExamples {
    /// Thirty-six aligned 32×64×32 chunk definitions and one 6×1×6 composition root.
    public static func composition() throws -> SculptureComposition {
        SculptureGenerationProbe.record("blockhaven-composition")
        let volume = try BlockhavenLandscape.make()
        let glyphs = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij".utf8)
        var models: [String: SculptureCompositionModel] = [:]
        var bindings: [SculptureModelBinding] = []
        var mapLayers: [[UInt8]] = []
        for z in 0..<6 {
            var row: [UInt8] = []
            for x in 0..<6 {
                try Task.checkCancellation()
                let id = "chunk-\(x)-\(z)"
                let glyph = glyphs[z * 6 + x]
                models[id] = .sculpture(try volume.chunk(x: x, z: z))
                bindings.append(try SculptureModelBinding(glyph: glyph, modelID: id))
                row.append(glyph)
            }
            mapLayers.append(row)
        }
        let root = try SculptureTileMap(
            width: 6,
            height: 1,
            layers: mapLayers,
            tileSize: SculptureTileSize(width: 32, height: 64, depth: 32),
            bindings: bindings
        )
        models["blockhaven"] = .tiles(root)
        return try SculptureComposition(title: "Blockhaven valley", rootID: "blockhaven", models: models)
    }

    /// Uses the same shared chunk library, with no allocation between sparse placements.
    public static func world() throws -> SculptureWorld {
        SculptureGenerationProbe.record("blockhaven-world")
        let library = try composition()
        let instances = try (0..<6).flatMap { z in
            try (0..<6).map { x in
                try SculptureWorldInstance(
                    id: "land-\(x)-\(z)",
                    modelID: "chunk-\(x)-\(z)",
                    origin: SculptureWorldPoint(x: Int64(x * 32), y: 0, z: Int64(z * 32))
                )
            }
        }
        return try SculptureWorld(title: "Blockhaven valley", library: library, instances: instances)
    }
}

private enum BlockhavenMaterial {
    static let stone: UInt8 = 64
    static let soil: UInt8 = 61
    static let grass: UInt8 = 111
    static let leaves: UInt8 = 58
    static let water: UInt8 = 43
    static let foam: UInt8 = 45
    static let roof: UInt8 = 120
    static let crop: UInt8 = 42
    static let ore: UInt8 = 35
}

private enum BlockhavenLandscape {
    private static let size = 192
    private static let height = 64
    private static let waterY = 46

    static func make() throws -> BlockhavenVolume {
        try Task.checkCancellation()
        var volume = BlockhavenVolume()
        var ground = [Int](repeating: 0, count: size * size)
        var wet = [Bool](repeating: false, count: size * size)
        for z in 0..<size {
            try Task.checkCancellation()
            let riverX = 88 + Int((8 * sin(Double(z) / 24)).rounded())
            for x in 0..<size {
                let riverDistance = abs(x - riverX)
                let lakeDistance = pow(Double(x - 92) / 21, 2) + pow(Double(z - 116) / 27, 2)
                let isWet = riverDistance <= 4 || lakeDistance <= 1
                var top = surfaceY(x: x, z: z)
                if isWet {
                    top = lakeDistance < 0.6 ? 54 : 51
                } else if riverDistance <= 8 {
                    top = min(top, 46 - (riverDistance - 4))
                } else if lakeDistance < 1.3 {
                    top = min(top, 45 - Int(((lakeDistance - 1) * 10).rounded()))
                }
                ground[z * size + x] = top
                wet[z * size + x] = isWet
                let tunnelZ = 47 + Int((6 * sin(Double(x - 125) / 14)).rounded())
                for y in top..<height {
                    if cave(x: x, y: y, z: z, tunnelZ: tunnelZ) { continue }
                    let material: UInt8
                    if y == top {
                        material = isWet ? BlockhavenMaterial.soil : BlockhavenMaterial.grass
                    } else if y < top + 3 {
                        material = BlockhavenMaterial.soil
                    } else {
                        material =
                            (x * 11 + z * 7 + y * 3) % 61 == 0 ? BlockhavenMaterial.ore : BlockhavenMaterial.stone
                    }
                    volume.set(x, y, z, material)
                }
                if isWet {
                    for y in waterY..<top {
                        let material =
                            y == waterY && (x + z).isMultiple(of: 11)
                            ? BlockhavenMaterial.foam : BlockhavenMaterial.water
                        volume.set(x, y, z, material)
                    }
                } else if top > 30, !reserved(x: x, z: z), (x * 13 + z * 7) % 53 == 0 {
                    volume.set(x, top - 1, z, BlockhavenMaterial.crop)
                }
            }
        }
        try forest(&volume, ground: ground, wet: wet)
        try village(&volume, ground: ground)
        castle(&volume)
        ruin(&volume, ground: ground)
        try Task.checkCancellation()
        return volume
    }

    private static func surfaceY(x: Int, z: Int) -> Int {
        if (20...61).contains(x), (20...61).contains(z) { return 33 }
        if (28...78).contains(x), (66...138).contains(z) { return 43 }
        let elevation =
            18 + 2 * sin(Double(x) / 23) + 2 * cos(Double(z) / 27)
            + 1.5 * sin(Double(x + z) / 31)
            + hill(x: x, z: z, cx: 153, cz: 44, radius: 47, height: 17)
            + hill(x: x, z: z, cx: 163, cz: 154, radius: 32, height: 10)
            + hill(x: x, z: z, cx: 22, cz: 145, radius: 40, height: 7)
        return 63 - Int(max(10, min(40, elevation)).rounded())
    }

    private static func hill(x: Int, z: Int, cx: Int, cz: Int, radius: Double, height: Double) -> Double {
        let distance = Double((x - cx) * (x - cx) + (z - cz) * (z - cz)) / (radius * radius)
        return height * pow(max(0, 1 - distance), 2)
    }

    private static func cave(x: Int, y: Int, z: Int, tunnelZ: Int) -> Bool {
        if (118...191).contains(x), abs(y - 42) <= 3, abs(z - tunnelZ) <= 3,
            (y - 42) * (y - 42) + (z - tunnelZ) * (z - tunnelZ) <= 10
        {
            return true
        }
        if (146...170).contains(x), (46...64).contains(z), (35...45).contains(y) {
            let ellipse = pow(Double(x - 158) / 12, 2) + pow(Double(y - 40) / 5, 2) + pow(Double(z - 55) / 9, 2)
            if ellipse <= 1 { return true }
        }
        return false
    }

    private static func reserved(x: Int, z: Int) -> Bool {
        ((16...65).contains(x) && (16...66).contains(z))
            || ((22...85).contains(x) && (58...145).contains(z))
            || ((76...112).contains(x) && (83...96).contains(z))
            || ((144...164).contains(x) && (149...169).contains(z))
    }

    private static func forest(_ volume: inout BlockhavenVolume, ground: [Int], wet: [Bool]) throws {
        let signatureTrees = [(22, 154, 0), (48, 154, 1), (68, 163, 2)]
        for z in stride(from: 12, through: 174, by: 18) {
            try Task.checkCancellation()
            for x in stride(from: 12, through: 174, by: 18) {
                let index = z * size + x
                guard !wet[index], ground[index] > 25, !reserved(x: x, z: z),
                    signatureTrees.allSatisfy({ (x - $0.0) * (x - $0.0) + (z - $0.1) * (z - $0.1) >= 100 })
                else { continue }
                tree(&volume, x: x, z: z, groundY: ground[index], kind: (x / 18 + z / 18) % 3)
            }
        }
        for (x, z, kind) in signatureTrees { tree(&volume, x: x, z: z, groundY: ground[z * size + x], kind: kind) }
    }

    private static func tree(_ volume: inout BlockhavenVolume, x: Int, z: Int, groundY: Int, kind: Int) {
        let trunk = kind == 0 ? 6 : kind == 1 ? 9 : 8
        if kind == 1 {
            for level in 0...6 {
                let radius = min(3, (level + 1) / 2)
                for dz in -radius...radius {
                    for dx in -radius...radius where abs(dx) + abs(dz) <= radius + 1 {
                        volume.set(x + dx, groundY - 9 + level, z + dz, BlockhavenMaterial.leaves)
                    }
                }
            }
        } else {
            let radius = kind == 0 ? 3 : 2
            let vertical = kind == 0 ? 2 : 3
            for dy in -vertical...vertical {
                for dz in -radius...radius {
                    for dx in -radius...radius where dx * dx + dz * dz <= radius * radius + 1 - abs(dy) {
                        volume.set(x + dx, groundY - trunk + dy, z + dz, BlockhavenMaterial.leaves)
                    }
                }
            }
        }
        for y in (groundY - trunk)..<groundY { volume.set(x, y, z, BlockhavenMaterial.soil) }
    }

    private static func village(_ volume: inout BlockhavenVolume, ground: [Int]) throws {
        for z in 66...140 {
            for x in 50...54 { volume.set(x, ground[z * size + x], z, BlockhavenMaterial.soil) }
        }
        for z in 89...91 {
            for x in 25...78 { volume.set(x, ground[z * size + x], z, BlockhavenMaterial.soil) }
        }
        for z in 58...70 {
            for x in 38...42 { volume.set(x, ground[z * size + x], z, BlockhavenMaterial.soil) }
        }
        for x in 40...52 { volume.set(x, ground[70 * size + x], 70, BlockhavenMaterial.soil) }
        for (x, z, width, depth) in [
            (35, 76, 12, 10), (58, 77, 12, 10), (35, 97, 12, 11), (58, 98, 13, 11), (57, 119, 15, 14),
        ] {
            try Task.checkCancellation()
            house(&volume, x: x, z: z, width: width, depth: depth, floorY: 42, wallTop: 35, stone: false)
        }
        volume.box(x: 49...55, y: 42...42, z: 94...100, glyph: BlockhavenMaterial.stone)
        for z in 95...99 {
            for x in 50...54 {
                let edge = x == 50 || x == 54 || z == 95 || z == 99
                volume.set(x, 41, z, edge ? BlockhavenMaterial.stone : BlockhavenMaterial.water)
                if edge { volume.set(x, 40, z, BlockhavenMaterial.stone) }
            }
        }
        for x in [50, 54] {
            for z in [95, 99] { volume.box(x: x...x, y: 35...39, z: z...z, glyph: BlockhavenMaterial.soil) }
        }
        volume.box(x: 49...55, y: 34...34, z: 94...100, glyph: BlockhavenMaterial.roof)
        for z in 119...134 {
            for x in 29...46 {
                volume.set(x, 43, z, BlockhavenMaterial.soil)
                if [30, 36, 42].contains(x) { volume.set(x, 43, z, BlockhavenMaterial.water) }
                if [33, 34, 39, 40, 45].contains(x), (120...133).contains(z) {
                    volume.set(x, 42, z, BlockhavenMaterial.crop)
                }
            }
        }
        for z in 118...135 {
            for x in 28...47 where x == 28 || x == 47 || z == 118 || z == 135 {
                volume.set(x, 41, z, BlockhavenMaterial.soil)
                if (x + z).isMultiple(of: 3) { volume.set(x, 40, z, BlockhavenMaterial.soil) }
            }
        }
        volume.box(x: 77...109, y: 43...43, z: 89...91, glyph: BlockhavenMaterial.soil)
        for x in 78...108 {
            for z in [89, 91] where !x.isMultiple(of: 5) { volume.set(x, 42, z, BlockhavenMaterial.soil) }
        }
        for x in [84, 96] {
            for z in [89, 91] { volume.box(x: x...x, y: 44...51, z: z...z, glyph: BlockhavenMaterial.stone) }
        }
    }

    private static func house(
        _ volume: inout BlockhavenVolume,
        x: Int,
        z: Int,
        width: Int,
        depth: Int,
        floorY: Int,
        wallTop: Int,
        stone: Bool
    ) {
        let wall = stone ? BlockhavenMaterial.stone : BlockhavenMaterial.soil
        volume.box(x: x...(x + width - 1), y: floorY...floorY, z: z...(z + depth - 1), glyph: wall)
        for dz in 0..<depth {
            for dx in 0..<width {
                guard dx == 0 || dx == width - 1 || dz == 0 || dz == depth - 1 else { continue }
                for y in wallTop..<floorY {
                    let window =
                        (y == wallTop + 2 || y == wallTop + 3)
                        && ((dx == 0 || dx == width - 1) ? dz == 3 || dz == 6 : dx == 2 || dx == width - 3)
                    volume.set(x + dx, y, z + dz, window ? BlockhavenMaterial.water : wall)
                }
            }
        }
        for dx in -1...width {
            let rise = max(0, min(dx, width - dx - 1))
            let roofY = wallTop - 1 - rise
            for dz in -1...depth { volume.set(x + dx, roofY, z + dz, BlockhavenMaterial.roof) }
            if (0..<width).contains(dx), roofY < wallTop - 1 {
                for y in (roofY + 1)..<wallTop {
                    for dz in [0, depth - 1] { volume.set(x + dx, y, z + dz, wall) }
                }
            }
        }
        for y in (floorY - 3)..<floorY { volume.set(x + width / 2, y, z + depth - 1, Sculpture.empty) }
        volume.set(x + width / 2 - 1, floorY - 4, z + depth - 1, BlockhavenMaterial.crop)
    }

    private static func castle(_ volume: inout BlockhavenVolume) {
        volume.box(x: 24...56, y: 32...32, z: 24...56, glyph: BlockhavenMaterial.stone)
        for z in 24...56 {
            for x in 24...56 where x <= 25 || x >= 55 || z <= 25 || z >= 55 {
                volume.box(x: x...x, y: 23...31, z: z...z, glyph: BlockhavenMaterial.stone)
                if (x + z) % 4 < 2 { volume.box(x: x...x, y: 21...22, z: z...z, glyph: BlockhavenMaterial.stone) }
            }
        }
        for (cx, cz) in [(26, 26), (54, 26), (26, 54), (54, 54)] {
            volume.box(x: (cx - 3)...(cx + 3), y: 17...17, z: (cz - 3)...(cz + 3), glyph: BlockhavenMaterial.stone)
            for z in (cz - 3)...(cz + 3) {
                for x in (cx - 3)...(cx + 3) where abs(x - cx) == 3 || abs(z - cz) == 3 {
                    volume.box(x: x...x, y: 18...31, z: z...z, glyph: BlockhavenMaterial.stone)
                    if (x + z) % 3 != 1 { volume.box(x: x...x, y: 15...16, z: z...z, glyph: BlockhavenMaterial.stone) }
                    if x == cx || z == cz {
                        volume.box(x: x...x, y: 24...25, z: z...z, glyph: BlockhavenMaterial.water)
                    }
                }
            }
        }
        house(&volume, x: 35, z: 35, width: 11, depth: 13, floorY: 31, wallTop: 22, stone: true)
        volume.box(x: 38...42, y: 27...31, z: 55...56, glyph: Sculpture.empty)
        volume.box(x: 39...41, y: 26...26, z: 55...56, glyph: Sculpture.empty)
        for x in [37, 43] { volume.set(x, 28, 56, BlockhavenMaterial.crop) }
        volume.box(x: 54...54, y: 8...14, z: 26...26, glyph: BlockhavenMaterial.soil)
        volume.box(x: 55...58, y: 8...10, z: 26...26, glyph: BlockhavenMaterial.crop)
        for x in 55...58 { volume.set(x, 10, 26, BlockhavenMaterial.roof) }
    }

    private static func ruin(_ volume: inout BlockhavenVolume, ground: [Int]) {
        for z in 154...162 {
            for x in 149...159 where x == 149 || x == 159 || z == 154 || z == 162 {
                let top = ground[z * size + x]
                let wallHeight = 2 + (x + z) % 4
                volume.box(x: x...x, y: (top - wallHeight)..<top, z: z...z, glyph: BlockhavenMaterial.stone)
            }
        }
        let top = ground[162 * size + 154]
        volume.box(x: 153...155, y: (top - 3)..<top, z: 162...162, glyph: Sculpture.empty)
        volume.box(x: 152...156, y: (top - 4)...(top - 4), z: 162...162, glyph: BlockhavenMaterial.stone)
    }
}

private struct BlockhavenVolume {
    private static let width = 192
    private static let height = 64
    private(set) var layers = Array(repeating: Array(repeating: Sculpture.empty, count: 192 * 64), count: 192)

    mutating func set(_ x: Int, _ y: Int, _ z: Int, _ glyph: UInt8) {
        guard (0..<Self.width).contains(x), (0..<Self.height).contains(y), layers.indices.contains(z) else { return }
        layers[z][y * Self.width + x] = glyph
    }

    mutating func box<X: Sequence, Y: Sequence, Z: Sequence>(x: X, y: Y, z: Z, glyph: UInt8)
    where X.Element == Int, Y.Element == Int, Z.Element == Int {
        for depth in z { for row in y { for column in x { set(column, row, depth, glyph) } } }
    }

    func chunk(x: Int, z: Int) throws -> Sculpture {
        let layers = try (0..<32).map { localZ in
            try Task.checkCancellation()
            let source = self.layers[z * 32 + localZ]
            var cells: [UInt8] = []
            cells.reserveCapacity(32 * Self.height)
            for y in 0..<Self.height {
                let start = y * Self.width + x * 32
                cells.append(contentsOf: source[start..<(start + 32)])
            }
            return cells
        }
        return try Sculpture(
            title: "Blockhaven chunk \(x + 1),\(z + 1)",
            width: 32,
            height: Self.height,
            layers: layers
        )
    }
}
