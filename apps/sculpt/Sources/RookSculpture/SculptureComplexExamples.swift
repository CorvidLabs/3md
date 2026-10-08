import Foundation

extension SculptureExamples {
    /// Recipes for the eight 64-cubed examples and the 256-cubed solar system, in `all` order.
    internal static let complexRecipes: [SculptureExampleRecipe] = [
        complexRecipe(
            "wandering-cartographer",
            "Wandering cartographer",
            "A posed explorer with a face, coat, boots, map and walking staff.",
            category: "Characters",
            build: cartographer
        ),
        complexRecipe(
            "clockwork-dragon",
            "Clockwork dragon",
            "Raised membrane wings, horns, an open jaw, four clawed feet and a curling tail.",
            category: "Creatures",
            build: dragon
        ),
        complexRecipe(
            "woodland-fox",
            "Woodland fox",
            "Pointed ears, a long muzzle, separated paws and a sweeping pale-tipped tail.",
            category: "Creatures",
            build: fox
        ),
        complexRecipe(
            "deep-sea-whale",
            "Deep sea whale",
            "A broad whale with flippers, a notched fluke, throat pleats and a branching spout.",
            category: "Creatures",
            build: whale
        ),
        complexRecipe(
            "citadel-of-arches",
            "Citadel of arches",
            "A moated castle with four towers, battlements, an open gate, keep and courtyard.",
            category: "Architecture",
            build: citadel
        ),
        complexRecipe(
            "sky-island-village",
            "Sky island village",
            "Three floating islands, rope bridges, roofed homes, trees and a windmill.",
            category: "Worlds",
            build: skyVillage
        ),
        complexRecipe(
            "canyon-waterfall",
            "Canyon waterfall",
            "Layered canyon cliffs, a waterfall, river, hollow stone arch, cave and watchtower.",
            category: "Worlds",
            build: canyon
        ),
        complexRecipe(
            "moonlit-harbor",
            "Moonlit harbor",
            "A crescent moon above a coastal village, lighthouse, wooden piers and sailboats.",
            category: "Worlds",
            build: harbor
        ),
        complexRecipe(
            "grand-solar-system",
            "Grand solar system",
            "Eight planets, rings, moons and a comet at artistic scale with compressed distances.",
            category: "Space",
            dimension: 256,
            build: solarSystem
        ),
    ]

    private static func complexRecipe(
        _ id: String,
        _ title: String,
        _ summary: String,
        category: String,
        dimension: Int = 64,
        build: @escaping @Sendable (inout ComplexVolume) -> Void
    ) -> SculptureExampleRecipe {
        SculptureExampleRecipe(id: id, title: title, summary: summary, category: category) {
            var volume = ComplexVolume(dimension: dimension)
            build(&volume)
            // Fixed bounded dimensions and palette-only primitives satisfy the sculpture schema.
            return try! Sculpture(title: title, width: dimension, height: dimension, layers: volume.layers)
        }
    }

    private static func cartographer(_ volume: inout ComplexVolume) {
        volume.ellipsoid(center: V(32, 1, 32), radii: V(22, 1, 15), glyph: M.rock)
        volume.segment(V(28, 24, 31), V(25, 6, 34), radius: 3, glyph: M.cloth)
        volume.segment(V(36, 24, 31), V(38, 6, 29), radius: 3, glyph: M.cloth)
        volume.box(x: 20...28, y: 3...7, z: 31...39, glyph: M.stone)
        volume.box(x: 34...42, y: 3...7, z: 26...34, glyph: M.stone)
        volume.ellipsoid(center: V(32, 31, 31), radii: V(9, 12, 6), glyph: M.beam)
        volume.box(x: 27...37, y: 25...37, z: 23...26, glyph: M.stone, hollow: true)
        volume.segment(V(32, 39, 32), V(32, 44, 32), radius: 2.5, glyph: M.pale)
        volume.ellipsoid(center: V(32, 48, 32), radii: V(7, 8, 6), glyph: M.pale)
        volume.segment(V(23, 37, 31), V(15, 33, 34), radius: 2.5, glyph: M.beam)
        volume.segment(V(15, 33, 34), V(12, 40, 37), radius: 2, glyph: M.beam)
        volume.ellipsoid(center: V(12, 40, 38), radii: V(2.5, 2.5, 2), glyph: M.pale)
        volume.segment(V(41, 37, 31), V(47, 30, 32), radius: 2.5, glyph: M.beam)
        volume.segment(V(47, 30, 32), V(50, 38, 35), radius: 2, glyph: M.beam)
        volume.ellipsoid(center: V(50, 38, 35), radii: V(2, 2, 2), glyph: M.pale)
        volume.segment(V(51, 8, 36), V(51, 49, 36), radius: 0.8, glyph: M.stone)
        volume.ellipsoid(center: V(51, 50, 36), radii: V(1.5, 2, 1.5), glyph: M.light)
        volume.box(x: 4...14, y: 38...46, z: 40...40, glyph: M.water)
        volume.box(x: 9...9, y: 38...46, z: 41...41, glyph: M.beam)
        volume.box(x: 5...13, y: 42...42, z: 41...41, glyph: M.beam)
        volume.segment(V(26, 38, 37), V(38, 24, 36), radius: 0.8, glyph: M.stone)
        for y in [27, 31, 35] { volume.set(32, y, 38, M.metal) }
        volume.box(x: 28...30, y: 50...51, z: 38...38, glyph: M.metal)
        volume.box(x: 34...36, y: 50...51, z: 38...38, glyph: M.metal)
        volume.box(x: 31...33, y: 47...49, z: 38...40, glyph: M.pale)
        volume.box(x: 30...34, y: 44...44, z: 37...38, glyph: M.beam)
        volume.ellipsoid(center: V(32, 55, 32), radii: V(11, 1, 8), glyph: M.stone)
        volume.box(x: 27...37, y: 56...61, z: 28...36, glyph: M.stone, hollow: true)
        volume.box(x: 27...37, y: 56...56, z: 37...37, glyph: M.metal)
    }

    private static func dragon(_ volume: inout ComplexVolume) {
        volume.ellipsoid(center: V(32, 23, 31), radii: V(11, 8, 15), glyph: M.stone)
        volume.segment(V(32, 23, 39), V(32, 33, 46), radius: 4.5, glyph: M.stone)
        volume.ellipsoid(center: V(32, 34, 48), radii: V(7, 6, 7), glyph: M.stone)
        volume.box(x: 27...37, y: 30...34, z: 51...59, glyph: M.stone)
        volume.box(x: 28...36, y: 26...27, z: 51...59, glyph: M.beam)
        volume.box(x: 29...35, y: 28...29, z: 55...59, glyph: Sculpture.empty)
        for x in [27, 37] { volume.set(x, 36, 53, M.metal) }
        volume.segment(V(27, 38, 47), V(24, 46, 45), radius: 1.5, tipRadius: 0.5, glyph: M.beam)
        volume.segment(V(37, 38, 47), V(40, 46, 45), radius: 1.5, tipRadius: 0.5, glyph: M.beam)
        for x in [22, 42] {
            for z in [23, 38] {
                let footX = x < 32 ? 19 : 45
                volume.segment(
                    V(Double(x), 21, Double(z)),
                    V(Double(footX), 6, Double(z + 4)),
                    radius: 3,
                    glyph: M.stone
                )
                for offset in [-2, 0, 2] {
                    volume.segment(
                        V(Double(footX + offset), 5, Double(z + 4)),
                        V(Double(footX + offset), 5, Double(z + 8)),
                        radius: 0.8,
                        glyph: M.metal
                    )
                }
            }
        }
        volume.segment(V(32, 21, 16), V(42, 18, 8), radius: 4, tipRadius: 3, glyph: M.stone)
        volume.segment(V(42, 18, 8), V(51, 24, 4), radius: 3, tipRadius: 2, glyph: M.stone)
        volume.segment(V(51, 24, 4), V(55, 31, 10), radius: 2, tipRadius: 1, glyph: M.stone)
        volume.triangle(V(55, 30, 10), V(59, 37, 12), V(51, 35, 14), glyph: M.light)
        for mirrored in [false, true] {
            func point(_ x: Double, _ y: Double, _ z: Double) -> V { V(mirrored ? 64 - x : x, y, z) }
            let shoulder = point(25, 29, 31)
            let elbow = point(10, 44, 25)
            let tip = point(3, 53, 16)
            let outer = point(5, 40, 38)
            let lower = point(14, 28, 44)
            volume.triangle(shoulder, elbow, outer, glyph: M.cloth)
            volume.triangle(elbow, tip, outer, glyph: M.cloth)
            volume.triangle(shoulder, outer, lower, glyph: M.cloth)
            for (start, end) in [(shoulder, elbow), (elbow, tip), (tip, outer), (outer, lower), (shoulder, outer)] {
                volume.segment(start, end, radius: 0.9, glyph: M.beam)
            }
        }
        for z in stride(from: 17, through: 41, by: 4) {
            volume.triangle(V(30, 30, Double(z)), V(32, 37, Double(z + 1)), V(34, 30, Double(z + 2)), glyph: M.metal)
        }
    }

    private static func fox(_ volume: inout ComplexVolume) {
        volume.ellipsoid(center: V(32, 1, 33), radii: V(21, 1, 17), glyph: M.rock)
        volume.ellipsoid(center: V(29, 20, 30), radii: V(9, 15, 10), glyph: M.cloth)
        volume.ellipsoid(center: V(29, 26, 38), radii: V(7, 10, 3), glyph: M.pale)
        volume.ellipsoid(center: V(28, 38, 35), radii: V(9, 8, 8), glyph: M.cloth)
        volume.segment(V(28, 36, 40), V(23, 35, 49), radius: 4, tipRadius: 2, glyph: M.pale)
        volume.ellipsoid(center: V(23, 35, 51), radii: V(2, 1.5, 1.5), glyph: M.metal)
        for (x, outward) in [(21, -1), (35, 1)] {
            for y in 43...55 {
                let center = x + outward * (y - 43) / 4
                let radius = max(0, (55 - y) / 3)
                volume.box(x: center - radius...center + radius, y: y...y, z: 33...36, glyph: M.stone)
                if y < 53, radius > 0 { volume.set(center, y, 37, M.beam) }
            }
        }
        for x in [22, 34] { volume.set(x, 40, 42, M.metal) }
        for x in [25, 33] {
            volume.segment(V(Double(x), 20, 39), V(Double(x), 5, 40), radius: 2.3, glyph: M.stone)
            volume.box(x: x - 3...x + 2, y: 3...5, z: 37...45, glyph: M.stone)
        }
        volume.ellipsoid(center: V(24, 8, 29), radii: V(6, 5, 7), glyph: M.cloth)
        volume.ellipsoid(center: V(35, 8, 29), radii: V(5, 5, 7), glyph: M.cloth)
        volume.segment(V(36, 10, 26), V(46, 15, 24), radius: 5, tipRadius: 6, glyph: M.cloth)
        volume.segment(V(46, 15, 24), V(52, 25, 32), radius: 6, tipRadius: 7, glyph: M.cloth)
        volume.segment(V(52, 25, 32), V(48, 35, 40), radius: 7, tipRadius: 5, glyph: M.cloth)
        volume.segment(V(48, 35, 40), V(39, 40, 44), radius: 5, tipRadius: 2, glyph: M.pale)
    }

    private static func whale(_ volume: inout ComplexVolume) {
        volume.ellipsoid(center: V(32, 29, 33), radii: V(12, 10, 20), glyph: M.pale)
        volume.ellipsoid(center: V(32, 30, 49), radii: V(10, 9, 10), glyph: M.pale)
        volume.ellipsoid(center: V(32, 25, 38), radii: V(11, 6, 13), glyph: M.beam)
        for z in stride(from: 40, through: 54, by: 3) {
            for x in 22...42 {
                for y in 22...25 where volume.glyph(x, y, z) != Sculpture.empty { volume.set(x, y, z, M.water) }
            }
        }
        for mirrored in [false, true] {
            func point(_ x: Double, _ y: Double, _ z: Double) -> V { V(mirrored ? 64 - x : x, y, z) }
            volume.triangle(point(21, 28, 38), point(3, 20, 28), point(11, 23, 45), thickness: 0.9, glyph: M.stone)
            volume.triangle(point(32, 35, 6), point(8, 40, 3), point(15, 34, 13), thickness: 0.9, glyph: M.stone)
        }
        volume.segment(V(32, 30, 17), V(32, 32, 9), radius: 6, tipRadius: 3, glyph: M.pale)
        volume.segment(V(32, 32, 9), V(32, 35, 6), radius: 3, tipRadius: 2, glyph: M.pale)
        volume.triangle(V(32, 38, 24), V(32, 46, 18), V(32, 38, 17), thickness: 1, glyph: M.stone)
        for x in [23, 41] { volume.set(x, 33, 53, M.metal) }
        volume.set(32, 38, 45, M.metal)
        volume.segment(V(32, 39, 45), V(31, 50, 45), radius: 0.7, glyph: M.water)
        volume.segment(V(31, 50, 45), V(23, 57, 42), radius: 0.7, glyph: M.light)
        volume.segment(V(31, 50, 45), V(39, 55, 48), radius: 0.7, glyph: M.light)
        for z in [10, 22, 43, 55] {
            for x in 8...55 { volume.set(x, 7 + Int((sin(Double(x) * 0.25) * 1.5).rounded()), z, M.water) }
        }
    }

    private static func citadel(_ volume: inout ComplexVolume) {
        volume.box(x: 8...55, y: 7...8, z: 8...53, glyph: M.rock)
        for z in 3...60 {
            for x in 3...60 where !(13...50).contains(x) || !(14...48).contains(z) { volume.set(x, 5, z, M.water) }
        }
        volume.box(x: 11...52, y: 9...22, z: 12...50, glyph: M.stone, hollow: true)
        // Hollow walls, rather than a solid fortress block, leave a real courtyard.
        volume.box(x: 13...50, y: 9...23, z: 14...48, glyph: Sculpture.empty)
        for x in 11...52 where x % 4 < 2 {
            volume.box(x: x...x, y: 23...25, z: 12...13, glyph: M.stone)
            volume.box(x: x...x, y: 23...25, z: 49...50, glyph: M.stone)
        }
        for z in 12...50 where z % 4 < 2 {
            volume.box(x: 11...12, y: 23...25, z: z...z, glyph: M.stone)
            volume.box(x: 51...52, y: 23...25, z: z...z, glyph: M.stone)
        }
        for x in 27...36 {
            let height = 15 + Int(sqrt(max(0, 25 - pow(Double(x) - 31.5, 2))))
            volume.box(x: x...x, y: 9...height, z: 49...51, glyph: Sculpture.empty)
        }
        for (x, z) in [(12, 13), (51, 13), (12, 49), (51, 49)] {
            volume.cylinder(x: x, z: z, y: 8...33, radius: 5.8, wall: 1.4, glyph: M.stone)
            volume.cylinder(x: x, z: z, y: 10...33, radius: 4.3, glyph: Sculpture.empty)
            for y in [9, 19, 29] { volume.cylinder(x: x, z: z, y: y...y, radius: 5.8, glyph: M.beam) }
            volume.box(x: x - 1...x + 1, y: 21...24, z: z + 4...z + 6, glyph: Sculpture.empty)
            for dx in -6...6 {
                for dz in -6...6 where (4.4...6.2).contains(hypot(Double(dx), Double(dz))) && (dx + dz) % 3 != 0 {
                    volume.box(x: x + dx...x + dx, y: 34...36, z: z + dz...z + dz, glyph: M.stone)
                }
            }
            volume.cone(x: x, z: z, base: 37, height: 8, radius: 6, hollow: true, glyph: M.metal)
            volume.segment(V(Double(x), 45, Double(z)), V(Double(x), 55, Double(z)), radius: 0.6, glyph: M.beam)
            volume.box(x: x + 1...x + 6, y: 51...55, z: z...z, glyph: M.light)
            volume.box(x: x + 5...x + 6, y: 52...53, z: z...z, glyph: Sculpture.empty)
        }
        volume.house(x: 24...40, z: 23...36, base: 9, wallHeight: 24, roofRise: 9)
        volume.cylinder(x: 32, z: 29, y: 43...53, radius: 2.8, wall: 1, glyph: M.beam)
        volume.cone(x: 32, z: 29, base: 54, height: 5, radius: 4, glyph: M.metal)
        volume.box(x: 28...35, y: 9...9, z: 49...62, glyph: M.beam)
        for x in [27, 36] {
            volume.box(x: x...x, y: 11...11, z: 51...62, glyph: M.beam)
            for z in [52, 57, 62] { volume.box(x: x...x, y: 5...11, z: z...z, glyph: M.stone) }
        }
        volume.cylinder(x: 44, z: 37, y: 9...12, radius: 3.2, wall: 1, glyph: M.stone)
        volume.cylinder(x: 44, z: 37, y: 9...9, radius: 2.2, glyph: M.water)
        volume.tree(x: 20, z: 40, base: 9, height: 10)
    }

    private static func skyVillage(_ volume: inout ComplexVolume) {
        volume.floatingIsland(x: 32, z: 34, top: 27, bottom: 6, radiusX: 23, radiusZ: 21)
        volume.floatingIsland(x: 7, z: 12, top: 23, bottom: 14, radiusX: 6, radiusZ: 7)
        volume.floatingIsland(x: 55, z: 13, top: 20, bottom: 12, radiusX: 7, radiusZ: 7)
        volume.house(x: 18...28, z: 24...34, base: 30, wallHeight: 7, roofRise: 5)
        volume.house(x: 34...43, z: 30...39, base: 30, wallHeight: 9, roofRise: 5)
        volume.house(x: 28...35, z: 42...50, base: 28, wallHeight: 6, roofRise: 4)
        volume.ropeBridge(V(18, 29, 26), V(9, 25, 14))
        volume.ropeBridge(V(43, 29, 25), V(55, 22, 14))
        volume.cylinder(x: 33, z: 22, y: 30...49, radius: 2.8, wall: 1, glyph: M.stone)
        volume.cone(x: 33, z: 22, base: 50, height: 5, radius: 4, glyph: M.metal)
        let hub = V(33, 47, 26)
        for tip in [V(21, 55, 26), V(41, 59, 26), V(45, 39, 26), V(25, 35, 26)] {
            volume.segment(hub, tip, radius: 0.8, glyph: M.beam)
        }
        volume.triangle(hub, V(21, 55, 26), V(25, 57, 26), glyph: M.pale)
        volume.triangle(hub, V(41, 59, 26), V(43, 55, 26), glyph: M.pale)
        volume.triangle(hub, V(45, 39, 26), V(41, 37, 26), glyph: M.pale)
        volume.triangle(hub, V(25, 35, 26), V(23, 39, 26), glyph: M.pale)
        volume.ellipsoid(center: hub, radii: V(1.4, 1.4, 1.4), glyph: M.metal)
        volume.tree(x: 44, z: 47, base: 27, height: 10)
        volume.tree(x: 12, z: 35, base: 27, height: 8)
        volume.ellipsoid(center: V(7, 47, 51), radii: V(5, 2, 3), glyph: M.rock)
        volume.ellipsoid(center: V(56, 51, 49), radii: V(5, 2, 3), glyph: M.rock)
        volume.segment(V(49, 27, 43), V(49, 12, 43), radius: 0.9, glyph: M.water)
        for z in 17...24 { volume.set(32, 31, z, M.water) }
    }

    private static func canyon(_ volume: inout ComplexVolume) {
        for z in 5...58 {
            let center = canyonCenter(z)
            for x in 4...59 where x <= center - 7 || x >= center + 7 {
                let top = canyonHeight(x, z)
                volume.box(x: x...x, y: top - 1...top, z: z...z, glyph: M.beam)
                if abs(x - center) <= 8 || x == 4 || x == 59 || z == 5 || z == 58 {
                    for y in 7..<top { volume.set(x, y, z, y % 6 < 2 ? M.stone : M.rock) }
                }
            }
            for x in center - 2...center + 2 { volume.set(x, 8, z, M.water) }
        }
        let fallX = canyonCenter(13)
        volume.box(x: fallX - 7...fallX + 7, y: 9...42, z: 11...13, glyph: M.stone)
        volume.box(x: fallX - 2...fallX + 2, y: 10...41, z: 14...14, glyph: M.water)
        volume.box(x: fallX - 3...fallX + 3, y: 42...43, z: 8...13, glyph: M.water)
        let bridgeX = canyonCenter(34)
        for x in bridgeX - 14...bridgeX + 14 {
            for y in 12...25 where (11.5...14).contains(hypot(Double(x - bridgeX), Double(y - 11))) {
                volume.box(x: x...x, y: y...y, z: 33...35, glyph: M.stone)
            }
        }
        volume.box(x: bridgeX - 14...bridgeX + 14, y: 25...25, z: 32...36, glyph: M.beam)
        for z in [32, 36] {
            volume.box(x: bridgeX - 14...bridgeX + 14, y: 28...28, z: z...z, glyph: M.beam)
            for x in stride(from: bridgeX - 14, through: bridgeX + 14, by: 4) {
                volume.box(x: x...x, y: 26...28, z: z...z, glyph: M.stone)
            }
        }
        let caveX = canyonCenter(44) - 7
        volume.ellipsoid(center: V(Double(caveX), 17, 44), radii: V(4, 4, 3), glyph: Sculpture.empty)
        for (x, z) in [(9, 19), (16, 45), (53, 22)] { volume.tree(x: x, z: z, base: canyonHeight(x, z), height: 10) }
        let watchBase = canyonHeight(49, 46)
        volume.cylinder(x: 49, z: 46, y: watchBase...watchBase + 12, radius: 3, wall: 1, glyph: M.stone)
        volume.cone(x: 49, z: 46, base: watchBase + 13, height: 5, radius: 4, glyph: M.metal)
        volume.box(x: 47...51, y: watchBase + 7...watchBase + 8, z: 49...49, glyph: M.pale)
    }

    private static func canyonCenter(_ z: Int) -> Int { 32 + Int((sin(Double(z) * 0.15) * 5).rounded()) }

    private static func canyonHeight(_ x: Int, _ z: Int) -> Int {
        if x < 32 { return 30 + Int((sin(Double(z) * 0.12) * 5).rounded()) + max(0, 22 - x) / 2 }
        return 29 + Int((cos(Double(z) * 0.13) * 4).rounded()) + max(0, x - 40) / 3
    }

    private static func harbor(_ volume: inout ComplexVolume) {
        volume.box(x: 5...58, y: 9...10, z: 5...28, glyph: M.rock)
        for z in 29...59 {
            for x in 4...59 { volume.set(x, 9, z, (x + z) % 7 == 0 ? M.light : M.water) }
        }
        volume.box(x: 5...58, y: 8...13, z: 28...29, glyph: M.stone)
        volume.house(x: 8...18, z: 9...20, base: 11, wallHeight: 9, roofRise: 6)
        volume.house(x: 22...33, z: 9...20, base: 11, wallHeight: 12, roofRise: 5)
        volume.house(x: 40...52, z: 10...22, base: 11, wallHeight: 9, roofRise: 7)
        for xRange in [9...14, 43...49] {
            volume.box(x: xRange, y: 12...12, z: 29...46, glyph: M.beam)
            for x in [xRange.lowerBound, xRange.upperBound] {
                for z in [33, 39, 45] { volume.box(x: x...x, y: 5...13, z: z...z, glyph: M.stone) }
            }
        }
        volume.cylinder(x: 54, z: 32, y: 10...45, radius: 3.8, wall: 1, glyph: M.pale)
        for y in [18, 27, 36] { volume.cylinder(x: 54, z: 32, y: y...y, radius: 3.9, wall: 1, glyph: M.stone) }
        volume.cylinder(x: 54, z: 32, y: 46...46, radius: 5, glyph: M.stone)
        volume.cylinder(x: 54, z: 32, y: 47...51, radius: 3, wall: 0.7, glyph: M.beam)
        volume.ellipsoid(center: V(54, 49, 32), radii: V(1.5, 2, 1.5), glyph: M.light)
        volume.cone(x: 54, z: 32, base: 52, height: 5, radius: 5, glyph: M.metal)
        volume.sailboat(x: 27, z: 44, base: 11, large: true)
        volume.sailboat(x: 46, z: 54, base: 11, large: false)
        volume.ellipsoid(center: V(15, 52, 12), radii: V(6, 6, 6), glyph: M.light)
        // Cut through the moon's depth so its crescent silhouette survives an oblique viewpoint.
        volume.ellipsoid(center: V(18, 54, 12), radii: V(6, 6, 10), glyph: Sculpture.empty)
        for point in [V(5, 50, 23), V(29, 56, 10), V(38, 48, 18)] {
            volume.segment(point - V(1, 0, 0), point + V(1, 0, 0), radius: 0.1, glyph: M.light)
            volume.segment(point - V(0, 1, 0), point + V(0, 1, 0), radius: 0.1, glyph: M.light)
        }
    }

    private static func solarSystem(_ volume: inout ComplexVolume) {
        let scale = Double(volume.dimension) / 64
        let sun = V(32, 30, 32)
        let planets: [(center: V, radius: Double)] = [
            (V(43, 29, 31), 1.6), (V(23, 29, 21), 2.6), (V(42, 29, 18), 2.8), (V(28, 29, 50), 2.2),
            (V(10, 29, 32), 4.8), (V(46, 29, 52), 3.8), (V(51, 29, 11), 3.1), (V(16, 29, 8), 3.3),
        ]

        // Sparse guides occupy a lower plane, so they do not connect the separate planetary bodies.
        for radius in [11.0, 14, 17, 19, 22, 25, 28, 30.5] {
            for step in 0..<224 where step % 8 < 3 {
                let angle = Double(step) * 2 * .pi / 224
                let center = V(32 + cos(angle) * radius, 23, 32 + sin(angle) * radius) * scale
                volume.ellipsoid(center: center, radii: V(repeating: 0.28 * scale), glyph: M.rock)
            }
        }

        // Deterministic irregular stones form a belt with actual air gaps between individual asteroids.
        for step in 0..<88 {
            let angle = Double(step) * 2 * .pi / 88
            let radius = 20.5 + sin(angle * 7) * 0.45
            let center = V(32 + cos(angle) * radius, 26 + sin(angle * 5) * 0.8, 32 + sin(angle) * radius)
            let size = 0.48 + Double(step % 4) * 0.08
            guard
                planets.allSatisfy({ body in
                    let delta = body.center - center
                    return dot(delta, delta) > pow(body.radius + size + 0.8, 2)
                })
            else { continue }
            volume.ellipsoid(
                center: center * scale,
                radii: V(size, size * 0.8, size * 0.7) * scale,
                glyph: step % 3 == 0 ? M.stone : M.rock
            )
        }

        volume.patternedSphere(center: sun * scale, radius: 7 * scale) { offset in
            let local = offset / scale
            let longitude = atan2(local.z, local.x)
            let granules = sin(local.y * 1.2 + longitude * 4) + cos(local.x * 0.9 - local.z * 0.6)
            if granules > 1.1 { return M.cloth }
            return granules < -0.3 ? M.water : M.light
        }
        for points in [
            [V(31, 37, 33), V(26, 41, 32), V(23, 38, 32), V(25, 34, 33)],
            [V(35, 28, 38), V(38, 24, 41), V(37, 21, 37), V(34, 25, 36)],
        ] {
            for index in 1..<points.count {
                volume.segment(points[index - 1] * scale, points[index] * scale, radius: 0.4 * scale, glyph: M.cloth)
            }
        }

        // Colors and surface markings distinguish bodies without requiring text labels in the geometry.
        volume.patternedSphere(center: planets[0].center * scale, radius: planets[0].radius * scale) { offset in
            Int(abs((offset / scale).y + (offset / scale).z)) % 3 == 0 ? M.water : M.rock
        }
        volume.patternedSphere(center: planets[1].center * scale, radius: planets[1].radius * scale) { offset in
            let local = offset / scale
            return Int(floor(local.y + sin(local.x * 0.9))) % 3 == 0 ? M.light : M.water
        }
        volume.patternedSphere(center: planets[2].center * scale, radius: planets[2].radius * scale) { offset in
            let local = offset / scale
            if abs(local.y) > 2 { return 45 }
            let continent =
                (local.x < 0 && local.z > 0 && local.y >= 0)
                || (local.x > 1 && local.z < -0.5 && local.y < 1)
            return continent ? M.pale : M.beam
        }
        volume.patternedSphere(center: planets[3].center * scale, radius: planets[3].radius * scale) { offset in
            let local = offset / scale
            if abs(local.y) > 1.9 { return M.water }
            return local.x < -0.7 && local.y > 0.3 && local.z > 1 ? M.rock : M.cloth
        }
        volume.patternedSphere(center: planets[4].center * scale, radius: planets[4].radius * scale) { offset in
            let local = offset / scale
            if local.z > 3, pow((local.x + 1) / 2, 2) + pow((local.y + 1) / 1.2, 2) < 1 {
                return M.cloth
            }
            let band = Int(floor(local.y + 4.8)) % 5
            return band < 2 ? M.light : band == 2 ? M.cloth : M.water
        }
        volume.patternedSphere(center: planets[5].center * scale, radius: planets[5].radius * scale) { offset in
            Int(floor((offset / scale).y + 3.8)) % 3 == 0 ? M.light : M.water
        }
        volume.patternedSphere(center: planets[6].center * scale, radius: planets[6].radius * scale) { offset in
            abs((offset / scale).y) < 0.6 ? M.beam : 45
        }
        volume.patternedSphere(center: planets[7].center * scale, radius: planets[7].radius * scale) { offset in
            let local = offset / scale
            if local.x < -0.3, local.y < 0, local.z > 2 { return M.rock }
            return local.y > 1 ? M.beam : M.metal
        }

        let saturnAxis = V(0, 0.25, sqrt(1 - 0.25 * 0.25))
        solarRing(
            &volume,
            center: planets[5].center * scale,
            radius: 6.1 * scale,
            thickness: 0.5 * scale,
            u: V(1, 0, 0),
            v: saturnAxis,
            glyph: M.water
        )
        solarRing(
            &volume,
            center: planets[5].center * scale,
            radius: 8 * scale,
            thickness: 0.5 * scale,
            u: V(1, 0, 0),
            v: saturnAxis,
            glyph: M.light
        )
        solarRing(
            &volume,
            center: planets[6].center * scale,
            radius: 5.2 * scale,
            thickness: 0.35 * scale,
            u: V(cos(70 * .pi / 180), sin(70 * .pi / 180), 0),
            v: V(0, 0, 1),
            glyph: M.metal
        )

        // Earth's Moon and four separated Galilean-style moons remain individually editable volumes.
        volume.ellipsoid(center: V(47, 33, 19) * scale, radii: V(repeating: scale), glyph: M.water)
        for (index, center) in [V(4, 30, 28), V(7, 35, 35), V(16, 30, 35), V(12, 24, 28)].enumerated() {
            volume.ellipsoid(
                center: center * scale,
                radii: V(repeating: (index % 2 == 0 ? 0.9 : 0.8) * scale),
                glyph: index % 2 == 0 ? M.water : M.metal
            )
        }
        volume.ellipsoid(center: V(55, 35, 55) * scale, radii: V(repeating: 1.1 * scale), glyph: M.cloth)

        // The comet's fan and ion trail point away from the central Sun and span elevated empty space.
        volume.triangle(
            V(9, 47, 51) * scale,
            V(1.5, 59, 61) * scale,
            V(6, 61, 57) * scale,
            thickness: 0.22 * scale,
            glyph: M.light
        )
        volume.segment(V(9, 47, 51) * scale, V(6, 52, 56) * scale, radius: 0.45 * scale, glyph: 45)
        volume.segment(V(6, 52, 56) * scale, V(3, 59, 61) * scale, radius: 0.3 * scale, glyph: 45)
        volume.ellipsoid(center: V(9, 47, 51) * scale, radii: V(1.5, 1.8, 1.5) * scale, glyph: M.beam)
        volume.ellipsoid(center: V(9, 47, 51) * scale, radii: V(repeating: 0.7 * scale), glyph: 45)
        for center in [V(5, 52, 9), V(58, 49, 43), V(12, 44, 55), V(47, 59, 30), V(30, 6, 7), V(6, 14, 56)] {
            for axis in [V(1, 0, 0), V(0, 1, 0), V(0, 0, 1)] {
                volume.segment(
                    (center - axis * 1.2) * scale,
                    (center + axis * 1.2) * scale,
                    radius: 0.22 * scale,
                    glyph: M.light
                )
            }
        }
    }

    private static func solarRing(
        _ volume: inout ComplexVolume,
        center: V,
        radius: Double,
        thickness: Double,
        u: V,
        v: V,
        glyph: UInt8
    ) {
        let steps = 192
        for step in 0..<steps {
            let from = Double(step) * 2 * .pi / Double(steps)
            let to = Double(step + 1) * 2 * .pi / Double(steps)
            volume.segment(
                center + (u * cos(from) + v * sin(from)) * radius,
                center + (u * cos(to) + v * sin(to)) * radius,
                radius: thickness,
                glyph: glyph
            )
        }
    }
}

private typealias V = SIMD3<Double>

private enum M {
    static let stone: UInt8 = 35
    static let metal: UInt8 = 64
    static let light: UInt8 = 42
    static let beam: UInt8 = 43
    static let pale: UInt8 = 111
    static let cloth: UInt8 = 120
    static let rock: UInt8 = 58
    static let water: UInt8 = 61
}

/// Builder coordinates use upward elevation. Stored rows use the document's downward Y axis.
private struct ComplexVolume {
    let dimension: Int
    var layers: [[UInt8]]

    init(dimension: Int = 64) {
        self.dimension = dimension
        layers = Array(repeating: Array(repeating: Sculpture.empty, count: dimension * dimension), count: dimension)
    }

    mutating func set(_ x: Int, _ y: Int, _ z: Int, _ glyph: UInt8) {
        guard (0..<dimension).contains(x), (0..<dimension).contains(y), (0..<dimension).contains(z) else { return }
        layers[z][(dimension - 1 - y) * dimension + x] = glyph
    }

    func glyph(_ x: Int, _ y: Int, _ z: Int) -> UInt8 {
        guard (0..<dimension).contains(x), (0..<dimension).contains(y), (0..<dimension).contains(z) else {
            return Sculpture.empty
        }
        return layers[z][(dimension - 1 - y) * dimension + x]
    }

    mutating func box(x: ClosedRange<Int>, y: ClosedRange<Int>, z: ClosedRange<Int>, glyph: UInt8, hollow: Bool = false)
    {
        for depth in z {
            for elevation in y {
                for column in x {
                    if !hollow || column == x.lowerBound || column == x.upperBound || elevation == y.lowerBound
                        || elevation == y.upperBound || depth == z.lowerBound || depth == z.upperBound
                    {
                        set(column, elevation, depth, glyph)
                    }
                }
            }
        }
    }

    mutating func ellipsoid(center: V, radii: V, glyph: UInt8) {
        for z in bounds(center.z - radii.z, center.z + radii.z) {
            for y in bounds(center.y - radii.y, center.y + radii.y) {
                for x in bounds(center.x - radii.x, center.x + radii.x) {
                    let point = (V(Double(x), Double(y), Double(z)) - center) / radii
                    if dot(point, point) <= 1 { set(x, y, z, glyph) }
                }
            }
        }
    }

    mutating func patternedSphere(center: V, radius: Double, pattern: (V) -> UInt8) {
        let squaredRadius = radius * radius
        for z in bounds(center.z - radius, center.z + radius) {
            for y in bounds(center.y - radius, center.y + radius) {
                for x in bounds(center.x - radius, center.x + radius) {
                    let offset = V(Double(x), Double(y), Double(z)) - center
                    if dot(offset, offset) <= squaredRadius { set(x, y, z, pattern(offset)) }
                }
            }
        }
    }

    mutating func segment(_ start: V, _ end: V, radius: Double, tipRadius: Double? = nil, glyph: UInt8) {
        let delta = end - start
        let squaredLength = dot(delta, delta)
        let maximumRadius = max(radius, tipRadius ?? radius)
        for z in bounds(min(start.z, end.z) - maximumRadius, max(start.z, end.z) + maximumRadius) {
            for y in bounds(min(start.y, end.y) - maximumRadius, max(start.y, end.y) + maximumRadius) {
                for x in bounds(min(start.x, end.x) - maximumRadius, max(start.x, end.x) + maximumRadius) {
                    let point = V(Double(x), Double(y), Double(z))
                    let t = squaredLength == 0 ? 0 : max(0, min(1, dot(point - start, delta) / squaredLength))
                    let distance = point - (start + delta * t)
                    let size = radius + ((tipRadius ?? radius) - radius) * t
                    if dot(distance, distance) <= size * size { set(x, y, z, glyph) }
                }
            }
        }
    }

    mutating func triangle(_ a: V, _ b: V, _ c: V, thickness: Double = 0.7, glyph: UInt8) {
        let u = b - a
        let v = c - a
        let normal = cross(u, v)
        let normalLength = sqrt(dot(normal, normal))
        let uu = dot(u, u)
        let uv = dot(u, v)
        let vv = dot(v, v)
        let denominator = uu * vv - uv * uv
        guard normalLength > 0, denominator > 0 else { return }
        for z in bounds(min(a.z, b.z, c.z) - thickness, max(a.z, b.z, c.z) + thickness) {
            for y in bounds(min(a.y, b.y, c.y) - thickness, max(a.y, b.y, c.y) + thickness) {
                for x in bounds(min(a.x, b.x, c.x) - thickness, max(a.x, b.x, c.x) + thickness) {
                    let offset = V(Double(x), Double(y), Double(z)) - a
                    guard abs(dot(offset, normal)) / normalLength <= thickness else { continue }
                    let wu = dot(offset, u)
                    let wv = dot(offset, v)
                    let s = (wu * vv - wv * uv) / denominator
                    let t = (wv * uu - wu * uv) / denominator
                    if s >= 0, t >= 0, s + t <= 1 { set(x, y, z, glyph) }
                }
            }
        }
    }

    mutating func cylinder(x: Int, z: Int, y: ClosedRange<Int>, radius: Double, wall: Double? = nil, glyph: UInt8) {
        let extent = Int(ceil(radius))
        for dz in -extent...extent {
            for dx in -extent...extent {
                let distance = hypot(Double(dx), Double(dz))
                guard distance <= radius, wall.map({ distance >= radius - $0 }) ?? true else { continue }
                for height in y { set(x + dx, height, z + dz, glyph) }
            }
        }
    }

    mutating func cone(x: Int, z: Int, base: Int, height: Int, radius: Double, hollow: Bool = false, glyph: UInt8) {
        for y in base...base + height {
            let size = max(0.5, radius * (1 - Double(y - base) / Double(height)))
            cylinder(x: x, z: z, y: y...y, radius: size, wall: hollow ? 1 : nil, glyph: glyph)
        }
    }

    mutating func house(x: ClosedRange<Int>, z: ClosedRange<Int>, base: Int, wallHeight: Int, roofRise: Int) {
        let center = (x.lowerBound + x.upperBound) / 2
        let halfWidth = max(1, (x.upperBound - x.lowerBound) / 2)
        box(x: x, y: base...base, z: z, glyph: M.beam)
        for column in x.lowerBound - 1...x.upperBound + 1 {
            let roof = base + wallHeight + roofRise - abs(column - center) * roofRise / halfWidth
            for depth in z.lowerBound - 1...z.upperBound + 1 {
                set(column, roof, depth, M.metal)
                if x.contains(column), z.contains(depth),
                    column == x.lowerBound || column == x.upperBound || depth == z.lowerBound || depth == z.upperBound
                {
                    for y in base + 1..<roof { set(column, y, depth, M.stone) }
                }
            }
        }
        for column in [x.lowerBound + 2, x.upperBound - 2] {
            box(
                x: column...column + 1,
                y: base + wallHeight / 2...base + wallHeight / 2 + 2,
                z: z.upperBound...z.upperBound,
                glyph: M.pale
            )
        }
        box(x: center - 1...center + 1, y: base + 1...base + 4, z: z.upperBound...z.upperBound, glyph: Sculpture.empty)
    }

    mutating func tree(x: Int, z: Int, base: Int, height: Int) {
        cylinder(x: x, z: z, y: base...base + height - 2, radius: 0.8, glyph: M.stone)
        cone(x: x, z: z, base: base + 3, height: height - 2, radius: 4, glyph: M.cloth)
        cone(x: x, z: z, base: base + 5, height: height - 3, radius: 3, glyph: M.cloth)
    }

    mutating func floatingIsland(x: Int, z: Int, top: Int, bottom: Int, radiusX: Double, radiusZ: Double) {
        for depth in bounds(Double(z) - radiusZ, Double(z) + radiusZ) {
            for column in bounds(Double(x) - radiusX, Double(x) + radiusX) {
                let distance = hypot(Double(column - x) / radiusX, Double(depth - z) / radiusZ)
                guard distance <= 1 else { continue }
                let surface = top + Int((1 - distance) * 3)
                let underside = bottom + Int(pow(distance, 1.6) * Double(top - bottom))
                box(x: column...column, y: surface - 1...surface, z: depth...depth, glyph: M.beam)
                let undersideTop = min(surface - 2, underside + 1)
                if underside <= undersideTop {
                    box(x: column...column, y: underside...undersideTop, z: depth...depth, glyph: M.rock)
                }
                if distance > 0.9, underside < surface - 1 {
                    box(x: column...column, y: underside...surface - 2, z: depth...depth, glyph: M.rock)
                }
            }
        }
    }

    mutating func ropeBridge(_ from: V, _ to: V) {
        for step in 0...40 {
            let t = Double(step) / 40
            var point = from + (to - from) * t
            point.y -= sin(t * .pi) * 3
            let x = Int(point.x.rounded())
            let y = Int(point.y.rounded())
            let z = Int(point.z.rounded())
            for offset in -1...1 { set(x + offset, y, z, M.water) }
            for offset in [-2, 2] {
                set(x + offset, y + 3, z, M.beam)
                if step % 8 == 0 { box(x: x + offset...x + offset, y: y + 1...y + 3, z: z...z, glyph: M.stone) }
            }
        }
    }

    mutating func sailboat(x: Int, z: Int, base: Int, large: Bool) {
        let radius = large ? 7.0 : 5.0
        ellipsoid(center: V(Double(x), Double(base + 1), Double(z)), radii: V(radius, 2, 4), glyph: M.stone)
        ellipsoid(
            center: V(Double(x), Double(base + 3), Double(z)),
            radii: V(radius - 1, 1.5, 3),
            glyph: Sculpture.empty
        )
        let mastTop = large ? base + 28 : base + 18
        segment(
            V(Double(x), Double(base + 3), Double(z)),
            V(Double(x), Double(mastTop), Double(z)),
            radius: 0.6,
            glyph: M.beam
        )
        triangle(
            V(Double(x + 1), Double(mastTop - 2), Double(z)),
            V(Double(x + (large ? 13 : 9)), Double(base + 7), Double(z)),
            V(Double(x + 1), Double(base + 7), Double(z)),
            glyph: M.pale
        )
        triangle(
            V(Double(x - 1), Double(mastTop - 4), Double(z)),
            V(Double(x - (large ? 9 : 6)), Double(base + 10), Double(z)),
            V(Double(x - 1), Double(base + 10), Double(z)),
            glyph: M.light
        )
        segment(
            V(Double(x - 9), Double(base + 7), Double(z)),
            V(Double(x + 13), Double(base + 7), Double(z)),
            radius: 0.5,
            glyph: M.stone
        )
    }

    private func bounds(_ lower: Double, _ upper: Double) -> ClosedRange<Int> {
        max(0, min(dimension - 1, Int(floor(lower))))...max(0, min(dimension - 1, Int(ceil(upper))))
    }
}

private func dot(_ lhs: V, _ rhs: V) -> Double { lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z }

private func cross(_ lhs: V, _ rhs: V) -> V {
    V(lhs.y * rhs.z - lhs.z * rhs.y, lhs.z * rhs.x - lhs.x * rhs.z, lhs.x * rhs.y - lhs.y * rhs.x)
}
