import Foundation

/// A built-in, editable document with a stable identity for the example gallery.
public struct SculptureExample: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let summary: String
    public let category: String
    public let sculpture: Sculpture

    public init(id: String, title: String, summary: String, category: String, sculpture: Sculpture) {
        self.id = id
        self.title = title
        self.summary = summary
        self.category = category
        self.sculpture = sculpture
    }
}

/// One authored example's metadata and the builder of its volume, so one example can be built alone.
internal struct SculptureExampleRecipe: Sendable {
    // MARK: - Properties

    internal let id: String
    internal let title: String
    internal let summary: String
    internal let category: String
    private let sculpture: @Sendable () -> Sculpture

    // MARK: - Initializers

    internal init(
        id: String,
        title: String,
        summary: String,
        category: String,
        sculpture: @escaping @Sendable () -> Sculpture
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.category = category
        self.sculpture = sculpture
    }

    // MARK: - Internal Methods

    /// Builds this example's volume and no other.
    /// - Returns: The example with its freshly built volume.
    internal func build() -> SculptureExample {
        SculptureGenerationProbe.record(id)
        return SculptureExample(id: id, title: title, summary: summary, category: category, sculpture: sculpture())
    }
}

/// Deterministic starter volumes. Maps use Y for elevation and Z for spatial depth.
public enum SculptureExamples {
    /// Small reusable models without initializing the larger gallery volumes.
    public static let compositionStarters: [SculptureExample] =
        ["moon-gate", "little-rocket", "pixel-bonsai"].compactMap(example(id:))

    /// Every authored example in catalog order. The first read builds all twenty-one volumes, including the
    /// 256-cubed solar system, and keeps them; `example(id:)` builds one example without the others.
    public static var all: [SculptureExample] {
        SculptureGenerationProbe.record("SculptureExamples.all")
        return built
    }

    /// One recipe per element of `all`, in its order. Reading the recipes builds nothing.
    internal static let recipes: [SculptureExampleRecipe] =
        [
            SculptureExampleRecipe(
                id: "character-orb",
                title: "Character orb",
                summary: "A hollow shell with a readable interior.",
                category: "Sculptures",
                sculpture: { .orb() }
            ),
            sampled("woven-torus", "Woven torus", "Follow the striped ring around its open center.", torus),
            sampled("moon-gate", "Moon gate", "A freestanding arch, stepped plinth and lanterns.", gate),
            sampled("spiral-tower", "Spiral tower", "A helix climbing around a slender central mast.", spiral),
            sampled("crystal-garden", "Crystal garden", "Faceted crystals growing from a low rocky bed.", crystals),
            sampled("little-rocket", "Little rocket", "A hollow hull, round window, fins and a bright plume.", rocket),
            sampled("pixel-bonsai", "Pixel bonsai", "A branching trunk and cloudlike canopy in a shallow pot.", bonsai),
            sampled("orbital-rings", "Orbital rings", "Three perpendicular hoops around a small star.", rings),
            sampled(
                "hill-observatory",
                "Hill observatory",
                "A domed tower on a stepped hill, with a winding stair.",
                observatory
            ),
            sampled(
                "terraced-island",
                "Terraced island",
                "Raised land, a winding stream, tiny trees and a bridge.",
                island,
                category: "Maps"
            ),
            sampled(
                "canal-city",
                "Canal city",
                "A canal divides roofed blocks, quays and a central bridge.",
                city,
                category: "Maps"
            ),
            sampled(
                "alpine-valley",
                "Alpine valley",
                "Snowy peaks frame a river, a cabin and a forest.",
                valley,
                category: "Maps"
            ),
        ] + complexRecipes

    // MARK: - Internal Methods

    /// Builds only the authored example with this identity, never the rest of the catalog.
    /// - Parameter id: A stable identity listed in `all`.
    /// - Returns: An example equal to the matching element of `all`, or nil for an unknown identity.
    internal static func example(id: String) -> SculptureExample? {
        recipes.first { $0.id == id }?.build()
    }

    // MARK: - Private

    private static let built: [SculptureExample] = recipes.map { $0.build() }

    private static let empty = Sculpture.empty
    private static let hash: UInt8 = 35
    private static let at: UInt8 = 64
    private static let star: UInt8 = 42
    private static let plus: UInt8 = 43
    private static let circle: UInt8 = 111
    private static let cross: UInt8 = 120
    private static let colon: UInt8 = 58
    private static let equal: UInt8 = 61

    private static func sampled(
        _ id: String,
        _ title: String,
        _ summary: String,
        _ sample: @escaping @Sendable (Int, Int, Int) -> UInt8,
        category: String = "Sculptures"
    ) -> SculptureExampleRecipe {
        SculptureExampleRecipe(id: id, title: title, summary: summary, category: category) {
            let size = 24
            // Raise low terrain within its volume so orbit previews frame the land and structures together.
            let rowOffset = category == "Maps" ? 6 : 0
            let layers = (0..<size).map { z in
                (0..<size * size).map { sample($0 % size, $0 / size + rowOffset, z) }
            }
            // Fixed dimensions, printable titles and the palette constants make these valid by construction.
            return try! Sculpture(title: title, width: size, height: size, layers: layers)
        }
    }

    private static func torus(_ x: Int, _ y: Int, _ z: Int) -> UInt8 {
        let dx = Double(x) - 11.5
        let dy = Double(y) - 11.5
        let dz = Double(z) - 11.5
        let ring = hypot(dx, dy) - 7.0
        let shell = hypot(ring, dz)
        guard (1.4...2.7).contains(shell) else { return empty }
        return (x + z + y) % 5 < 2 ? at : hash
    }

    private static func gate(_ x: Int, _ y: Int, _ z: Int) -> UInt8 {
        if (3...20).contains(x), (7...16).contains(z), (20...21).contains(y) { return equal }
        if (8...15).contains(z) {
            if (16...19).contains(y), (5...7).contains(x) || (16...18).contains(x) { return hash }
            let dx = Double(x) - 11.5
            let dy = Double(y) - 15.0
            if y <= 15, (4.6...7.0).contains(hypot(dx, dy)) { return hash }
        }
        if (x == 4 || x == 19), (10...13).contains(z), (14...18).contains(y) {
            return y < 17 ? star : plus
        }
        return empty
    }

    private static func spiral(_ x: Int, _ y: Int, _ z: Int) -> UInt8 {
        if (10...13).contains(x), (10...13).contains(z), (3...21).contains(y) { return plus }
        if (4...19).contains(x), (4...19).contains(z), y == 21 { return equal }
        guard (3...20).contains(y) else { return empty }
        let angle = Double(20 - y) * .pi / 5
        let centerX = 11.5 + cos(angle) * 6.5
        let centerZ = 11.5 + sin(angle) * 6.5
        guard hypot(Double(x) - centerX, Double(z) - centerZ) <= 1.7 else { return empty }
        return y % 4 < 2 ? at : hash
    }

    private static func crystals(_ x: Int, _ y: Int, _ z: Int) -> UInt8 {
        let crystals = [(6, 7, 14, 3), (17, 10, 18, 3), (6, 17, 9, 3), (17, 18, 8, 2)]
        for (centerX, centerZ, height, radius) in crystals {
            let elevation = 21 - y
            guard elevation >= 1, elevation <= height else { continue }
            let taper = min(radius, min(elevation + 1, (height - elevation) / 2 + 1))
            if abs(x - centerX) + abs(z - centerZ) <= taper {
                return elevation >= height - 3 ? star : (x < centerX ? at : plus)
            }
        }
        if y == 21, hypot(Double(x) - 11.5, Double(z) - 11.5) < 9 { return colon }
        return empty
    }

    private static func rocket(_ x: Int, _ y: Int, _ z: Int) -> UInt8 {
        let dx = Double(x) - 11.5
        let dz = Double(z) - 11.5
        let radius = hypot(dx, dz)
        if (4...16).contains(y) {
            let outer = y < 8 ? Double(y - 3) * 0.9 : 4.1
            if radius <= outer, radius >= max(0, outer - 1.2) {
                if (10...12).contains(y), z >= 14, (10...13).contains(x) { return circle }
                return y < 8 ? at : hash
            }
        }
        if (13...17).contains(y) {
            let reach = Double(y - 10)
            if (abs(dx) <= 1 && abs(dz) <= reach) || (abs(dz) <= 1 && abs(dx) <= reach) {
                return plus
            }
        }
        if (18...21).contains(y), radius <= Double(22 - y) * 0.6 { return star }
        return empty
    }

    private static func bonsai(_ x: Int, _ y: Int, _ z: Int) -> UInt8 {
        if (18...20).contains(y), (5...18).contains(x), (6...17).contains(z) {
            let border = x == 5 || x == 18 || z == 6 || z == 17
            if y == 20 || border { return equal }
            if y == 19 { return colon }
        }
        if (10...18).contains(y) {
            let trunkX = 11 + (18 - y) / 3
            if abs(x - trunkX) <= 1, (10...12).contains(z) { return hash }
            if (10...13).contains(y), x >= 7, x <= trunkX, z == 11 { return hash }
        }
        let canopies = [(8.0, 9.0, 10.0, 4.0), (15.0, 7.0, 12.0, 4.6), (13.0, 10.0, 16.0, 3.0)]
        for (cx, cy, cz, radius) in canopies {
            let dx = Double(x) - cx
            let dy = (Double(y) - cy) * 1.6
            let dz = Double(z) - cz
            if sqrt(dx * dx + dy * dy + dz * dz) < radius { return circle }
        }
        return empty
    }

    private static func rings(_ x: Int, _ y: Int, _ z: Int) -> UInt8 {
        let dx = Double(x) - 11.5
        let dy = Double(y) - 11.5
        let dz = Double(z) - 11.5
        if abs(dy) < 1, (7.8...8.9).contains(hypot(dx, dz)) { return at }
        if abs(dx) < 1, (7.8...8.9).contains(hypot(dy, dz)) { return plus }
        if abs(dz) < 1, (7.8...8.9).contains(hypot(dx, dy)) { return hash }
        if abs(dx) + abs(dy) + abs(dz) < 3.5 { return star }
        return empty
    }

    private static func observatory(_ x: Int, _ y: Int, _ z: Int) -> UInt8 {
        let dx = Double(x) - 11.5
        let dz = Double(z) - 11.5
        let radius = hypot(dx, dz)
        if (18...21).contains(y), radius < Double(y - 11) { return colon }
        if (10...17).contains(y), radius <= 4.5, radius >= 3.2 {
            if y == 13, (x == 8 || x == 15 || z == 8 || z == 15) { return circle }
            return hash
        }
        if y <= 10 {
            let dy = Double(y) - 10
            let dome = sqrt(dx * dx + dy * dy + dz * dz)
            if (3.2...4.6).contains(dome) {
                if (11...12).contains(x), z >= 12 { return empty }
                return at
            }
        }
        if (15...20).contains(y), (11...12).contains(z), x == 15 + (y - 15) { return equal }
        return empty
    }

    private static func island(_ x: Int, _ y: Int, _ z: Int) -> UInt8 {
        let dx = Double(x) - 11.5
        let dz = Double(z) - 11.5
        let distance = hypot(dx * 0.9, dz)
        let ground = distance < 5 ? 16 : (distance < 8 ? 18 : 20)
        if distance < 10, y >= ground, y <= 21 {
            let streamX = 12 + Int((sin(Double(z) * 0.5) * 2).rounded())
            if abs(x - streamX) <= 1, y == ground { return equal }
            return y == ground ? plus : colon
        }
        if z == 11, (8...15).contains(x), y == 15 { return hash }
        for (treeX, treeZ) in [(5, 10), (16, 6), (17, 16), (8, 17)] {
            let treeGround = hypot((Double(treeX) - 11.5) * 0.9, Double(treeZ) - 11.5) < 8 ? 18 : 20
            if x == treeX, z == treeZ, y == treeGround - 1 { return hash }
            if abs(x - treeX) + abs(z - treeZ) <= 1, (treeGround - 4...treeGround - 2).contains(y) {
                return circle
            }
        }
        return empty
    }

    private static func city(_ x: Int, _ y: Int, _ z: Int) -> UInt8 {
        guard (2...21).contains(x), (2...21).contains(z) else { return empty }
        if y == 21 { return (10...13).contains(x) ? equal : colon }
        if (y == 20 || y == 19), (x == 9 || x == 14) { return hash }
        if (11...12).contains(z), (8...15).contains(x), y == 17 { return plus }
        let buildings = [(4, 4, 6), (16, 4, 9), (4, 14, 8), (16, 14, 5)]
        for (originX, originZ, height) in buildings {
            guard (originX...originX + 3).contains(x), (originZ...originZ + 5).contains(z) else { continue }
            let roof = 20 - height + abs(x - originX - 1)
            if y == roof { return at }
            if y > roof, y <= 20 {
                if y % 3 == 0, z % 2 == 0, (x == originX || x == originX + 3) { return circle }
                if x == originX || x == originX + 3 || z == originZ || z == originZ + 5 { return hash }
            }
        }
        return empty
    }

    private static func valley(_ x: Int, _ y: Int, _ z: Int) -> UInt8 {
        guard (2...21).contains(x), (2...21).contains(z) else { return empty }
        let left = max(0, 11 - abs(x - 5) * 2 - abs(z - 8))
        let right = max(0, 14 - abs(x - 18) * 2 - abs(z - 15))
        let ground = 21 - max(left, right)
        if y >= ground, y <= 21 {
            if y == ground, ground <= 11 { return star }
            if (11...12).contains(x), y == 21 { return equal }
            return y == ground ? plus : colon
        }
        if (6...9).contains(x), (17...20).contains(z) {
            let roof = 17 + abs(x - 7)
            if y == roof { return at }
            if y > roof, y < 21 { return hash }
        }
        for (treeX, treeZ) in [(8, 13), (7, 15), (15, 5), (17, 4), (15, 8)] {
            let elevation = max(
                max(0, 11 - abs(treeX - 5) * 2 - abs(treeZ - 8)),
                max(0, 14 - abs(treeX - 18) * 2 - abs(treeZ - 15))
            )
            let treeGround = 21 - elevation
            if x == treeX, z == treeZ, y == treeGround - 1 { return hash }
            if abs(x - treeX) + abs(z - treeZ) <= 1, (treeGround - 4...treeGround - 2).contains(y) {
                return cross
            }
        }
        return empty
    }
}
