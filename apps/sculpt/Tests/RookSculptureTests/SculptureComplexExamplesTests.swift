import Foundation
import RookSculpture
import Testing

private let complexExampleIDs = [
    "wandering-cartographer", "clockwork-dragon", "woodland-fox", "deep-sea-whale", "citadel-of-arches",
    "sky-island-village", "canyon-waterfall", "moonlit-harbor",
]

@Test func complexCatalogAddsCharactersCreaturesArchitectureAndWorlds() throws {
    let examples = SculptureExamples.all.filter { complexExampleIDs.contains($0.id) }
    #expect(examples.count == 8)
    #expect(examples.filter { $0.category == "Characters" }.count == 1)
    #expect(examples.filter { $0.category == "Creatures" }.count == 3)
    #expect(examples.filter { $0.category == "Architecture" }.count == 1)
    #expect(examples.filter { $0.category == "Worlds" }.count == 3)
    for example in examples {
        #expect(!example.summary.isEmpty)
        #expect(example.title == example.sculpture.title)
    }
}

@Test(arguments: complexExampleIDs)
func largeExamplesStayEditableAndBoundedForMeshAndMediaExport(id: String) throws {
    let sculpture = try complexSculpture(id)
    #expect(sculpture.width == 64)
    #expect(sculpture.height == 64)
    #expect(sculpture.depth == 64)
    #expect(sculpture.occupiedCount > 1_000)
    // Detailed shells and shaped bodies must remain substantially smaller than a filled 64³ block.
    #expect(sculpture.occupiedCount < 64 * 64 * 16)
    let materials = Set(sculpture.layers.flatMap { $0 }.filter { $0 != Sculpture.empty })
    #expect(materials.count >= 4)
    #expect(materials.isSubset(of: Set(Sculpture.palette)))
    #expect(exposedFaceCount(sculpture) < 150_000)
    let encoded = SculptureCodec.encode(sculpture)
    #expect(encoded.count < SculptureCodec.maximumBytes)
    #expect(try SculptureCodec.decode(encoded) == sculpture)
}

@Test func cartographerHasFaceMapStaffAndSeparatedLegs() throws {
    let figure = try complexSculpture("wandering-cartographer")
    #expect(worldGlyph(figure, x: 29, y: 50, z: 38) == 64)
    #expect(worldGlyph(figure, x: 35, y: 50, z: 38) == 64)
    #expect(worldGlyph(figure, x: 32, y: 48, z: 40) == 111)
    #expect(worldGlyph(figure, x: 25, y: 4, z: 35) == 35)
    #expect(worldGlyph(figure, x: 38, y: 4, z: 30) == 35)
    #expect(worldGlyph(figure, x: 4, y: 40, z: 40) == 61)
    #expect(worldGlyph(figure, x: 51, y: 30, z: 36) == 35)
    #expect(worldGlyph(figure, x: 32, y: 12, z: 32) == Sculpture.empty)
    #expect(worldGlyph(figure, x: 18, y: 40, z: 31) == Sculpture.empty)
    #expect(worldGlyph(figure, x: 32, y: 59, z: 32) == Sculpture.empty)
}

@Test func dragonHasMirroredRaisedWingsHornsAndAnOpenJaw() throws {
    let dragon = try complexSculpture("clockwork-dragon")
    #expect(worldGlyph(dragon, x: 3, y: 53, z: 16) == 43)
    #expect(worldGlyph(dragon, x: 61, y: 53, z: 16) == 43)
    #expect(worldGlyph(dragon, x: 24, y: 46, z: 45) == 43)
    #expect(worldGlyph(dragon, x: 40, y: 46, z: 45) == 43)
    #expect(worldGlyph(dragon, x: 32, y: 32, z: 57) == 35)
    #expect(worldGlyph(dragon, x: 32, y: 26, z: 57) == 43)
    #expect(worldGlyph(dragon, x: 32, y: 28, z: 57) == Sculpture.empty)
    #expect(worldGlyph(dragon, x: 32, y: 44, z: 47) == Sculpture.empty)
    for x in [19, 45] {
        for z in [31, 46] { #expect(worldGlyph(dragon, x: x, y: 5, z: z) == 64) }
    }
}

@Test func foxHasTwoEarTipsLongMuzzleAndSeparatedFrontPaws() throws {
    let fox = try complexSculpture("woodland-fox")
    #expect(worldGlyph(fox, x: 18, y: 55, z: 34) == 35)
    #expect(worldGlyph(fox, x: 38, y: 55, z: 34) == 35)
    #expect(worldGlyph(fox, x: 29, y: 52, z: 34) == Sculpture.empty)
    #expect(worldGlyph(fox, x: 23, y: 35, z: 51) == 64)
    #expect(worldGlyph(fox, x: 22, y: 40, z: 42) == 64)
    #expect(worldGlyph(fox, x: 34, y: 40, z: 42) == 64)
    #expect(worldGlyph(fox, x: 25, y: 4, z: 42) == 35)
    #expect(worldGlyph(fox, x: 33, y: 4, z: 42) == 35)
    #expect(worldGlyph(fox, x: 29, y: 8, z: 41) == Sculpture.empty)
    #expect(worldGlyph(fox, x: 52, y: 25, z: 32) == 120)
    #expect(worldGlyph(fox, x: 39, y: 40, z: 44) == 111)
}

@Test func whaleHasWideNotchedFlukeFlippersAndBranchingSpout() throws {
    let whale = try complexSculpture("deep-sea-whale")
    #expect(worldGlyph(whale, x: 8, y: 40, z: 3) == 35)
    #expect(worldGlyph(whale, x: 56, y: 40, z: 3) == 35)
    #expect(worldGlyph(whale, x: 32, y: 39, z: 3) == Sculpture.empty)
    #expect(worldGlyph(whale, x: 3, y: 20, z: 28) == 35)
    #expect(worldGlyph(whale, x: 61, y: 20, z: 28) == 35)
    #expect(worldGlyph(whale, x: 23, y: 57, z: 42) == 42)
    #expect(worldGlyph(whale, x: 39, y: 55, z: 48) == 42)
    #expect(worldGlyph(whale, x: 23, y: 33, z: 53) == 64)
    #expect(worldGlyph(whale, x: 41, y: 33, z: 53) == 64)
    #expect(worldGlyph(whale, x: 32, y: 24, z: 46) == 61)
}

@Test func citadelHasTraversableGateCourtyardAndHollowTowerRooms() throws {
    let castle = try complexSculpture("citadel-of-arches")
    #expect(worldGlyph(castle, x: 32, y: 12, z: 50) == Sculpture.empty)
    #expect(worldGlyph(castle, x: 32, y: 9, z: 58) == 43)
    #expect(worldGlyph(castle, x: 20, y: 15, z: 30) == Sculpture.empty)
    #expect(worldGlyph(castle, x: 32, y: 20, z: 29) == Sculpture.empty)
    #expect(worldGlyph(castle, x: 12, y: 22, z: 18) == Sculpture.empty)
    #expect(worldGlyph(castle, x: 12, y: 23, z: 13) == Sculpture.empty)
    #expect(worldGlyph(castle, x: 6, y: 5, z: 30) == 61)
    #expect(worldGlyph(castle, x: 44, y: 9, z: 37) == 61)
    #expect(worldGlyph(castle, x: 14, y: 54, z: 13) == 42)
    #expect(worldGlyph(castle, x: 32, y: 59, z: 29) == 64)
}

@Test func skyVillageHasSuspendedTerrainBridgesAndWindmillAboveHomes() throws {
    let village = try complexSculpture("sky-island-village")
    #expect(worldGlyph(village, x: 32, y: 30, z: 34) == 43)
    #expect(worldGlyph(village, x: 32, y: 6, z: 34) == 58)
    #expect(worldGlyph(village, x: 32, y: 1, z: 34) == Sculpture.empty)
    #expect(worldGlyph(village, x: 7, y: 26, z: 12) == 43)
    #expect(worldGlyph(village, x: 16, y: 12, z: 13) == Sculpture.empty)
    #expect(worldGlyph(village, x: 33, y: 47, z: 26) == 64)
    #expect(worldGlyph(village, x: 49, y: 15, z: 43) == 61)
    #expect(worldGlyph(village, x: 9, y: 25, z: 14) == 61)
    #expect(worldGlyph(village, x: 38, y: 35, z: 34) == Sculpture.empty)
}

@Test func canyonHasFlowingWaterOpenArchAndCarvedCave() throws {
    let canyon = try complexSculpture("canyon-waterfall")
    #expect(worldGlyph(canyon, x: 27, y: 8, z: 30) == 61)
    #expect(worldGlyph(canyon, x: 37, y: 25, z: 14) == 61)
    #expect(worldGlyph(canyon, x: 27, y: 25, z: 34) == 43)
    #expect(worldGlyph(canyon, x: 27, y: 15, z: 34) == Sculpture.empty)
    #expect(worldGlyph(canyon, x: 27, y: 17, z: 44) == Sculpture.empty)
    #expect(worldGlyph(canyon, x: 4, y: 20, z: 30) != Sculpture.empty)
    #expect(worldGlyph(canyon, x: 49, y: 42, z: 46) == Sculpture.empty)
    #expect(worldGlyph(canyon, x: 49, y: 54, z: 46) == 64)
}

@Test func harborHasSailsLightedLanternOpenHomesAndCrescentMoon() throws {
    let harbor = try complexSculpture("moonlit-harbor")
    #expect(worldGlyph(harbor, x: 27, y: 32, z: 44) == 43)
    #expect(worldGlyph(harbor, x: 30, y: 25, z: 44) == 111)
    #expect(worldGlyph(harbor, x: 10, y: 12, z: 38) == 43)
    #expect(worldGlyph(harbor, x: 54, y: 49, z: 32) == 42)
    #expect(worldGlyph(harbor, x: 54, y: 30, z: 32) == Sculpture.empty)
    #expect(worldGlyph(harbor, x: 13, y: 17, z: 15) == Sculpture.empty)
    #expect(worldGlyph(harbor, x: 13, y: 13, z: 20) == Sculpture.empty)
    #expect(worldGlyph(harbor, x: 10, y: 52, z: 12) == 42)
    #expect(worldGlyph(harbor, x: 18, y: 54, z: 15) == Sculpture.empty)
}

private func complexSculpture(_ id: String) throws -> Sculpture {
    try #require(SculptureExamples.all.first { $0.id == id }).sculpture
}

/// Semantic anchors use upward world elevation, independently converted to the file's downward row axis.
private func worldGlyph(_ sculpture: Sculpture, x: Int, y: Int, z: Int) -> UInt8? {
    sculpture.glyph(at: SculptureCell(x: x, y: sculpture.height - 1 - y, z: z))
}

private func exposedFaceCount(_ sculpture: Sculpture) -> Int {
    let offsets = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]
    var faces = 0
    for z in 0..<sculpture.depth {
        for y in 0..<sculpture.height {
            for x in 0..<sculpture.width where sculpture.layers[z][y * sculpture.width + x] != Sculpture.empty {
                for (dx, dy, dz) in offsets {
                    let neighbor = sculpture.glyph(at: SculptureCell(x: x + dx, y: y + dy, z: z + dz))
                    if neighbor == nil || neighbor == Sculpture.empty { faces += 1 }
                }
            }
        }
    }
    return faces
}
