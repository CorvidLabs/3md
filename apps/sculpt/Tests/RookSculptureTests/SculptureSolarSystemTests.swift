import Foundation
import RookSculpture
import Testing

@Test func solarSystemExtendsTheGalleryWithoutReplacingExistingExamples() throws {
    let preservedIDs = [
        "character-orb", "woven-torus", "moon-gate", "spiral-tower", "crystal-garden", "little-rocket", "pixel-bonsai",
        "orbital-rings", "hill-observatory", "terraced-island", "canal-city", "alpine-valley", "wandering-cartographer",
        "clockwork-dragon", "woodland-fox", "deep-sea-whale", "citadel-of-arches", "sky-island-village",
        "canyon-waterfall", "moonlit-harbor",
    ]
    #expect(Array(SculptureExamples.all.prefix(20)).map(\.id) == preservedIDs)
    let example = try #require(SculptureExamples.all.last)
    #expect(example.id == "grand-solar-system")
    #expect(example.title == "Grand solar system")
    #expect(example.category == "Space")
    #expect(example.summary.contains("artistic scale"))
    #expect(example.summary.contains("compressed distances"))
}

@Test func solarSystemUsesTheFullEditableVolumeAndRoundTripsThroughThreeMD() throws {
    let scene = try solarScene()
    #expect(scene.width == 256)
    #expect(scene.height == 256)
    #expect(scene.depth == 256)
    #expect(scene.occupiedCount > 120_000)
    #expect(scene.occupiedCount < 250_000)
    #expect(solarExposedFaceCount(scene) < 150_000)
    let encoded = SculptureCodec.encode(scene)
    #expect(encoded.count < SculptureCodec.maximumBytes)
    #expect(try SculptureCodec.decode(encoded) == scene)

    // The curved limb is sampled at native resolution, rather than repeated four-cell blocks.
    #expect(solarGlyph(scene, x: 156, y: 120, z: 128) != Sculpture.empty)
    #expect(solarGlyph(scene, x: 156, y: 121, z: 128) == Sculpture.empty)
    #expect(solarGlyph(scene, x: 157, y: 120, z: 128) == Sculpture.empty)
    #expect(solarGlyph(scene, x: 160, y: 116, z: 126) == Sculpture.empty)
}

@Test func solarSystemHasEightSolidSeparatedPlanetsWithDistinctSurfaceFeatures() throws {
    let scene = try solarScene()
    let bodies: [(x: Int, y: Int, z: Int, radius: Double)] = [
        (172, 116, 124, 6.4), (92, 116, 84, 10.4), (168, 116, 72, 11.2), (112, 116, 200, 8.8),
        (40, 116, 128, 19.2), (184, 116, 208, 15.2), (204, 116, 44, 12.4), (64, 116, 32, 13.2),
    ]
    for body in bodies {
        let center = solarGlyph(scene, x: body.x, y: body.y, z: body.z)
        #expect(center != nil && center != Sculpture.empty)
        #expect(solarGlyph(scene, x: body.x, y: body.y + Int(body.radius * 0.6), z: body.z) != Sculpture.empty)
        #expect(solarGlyph(scene, x: body.x, y: body.y + Int(ceil(body.radius)) + 8, z: body.z) == Sculpture.empty)
    }
    // Mercury's mottled rock, Venus's clouds, and Mars's red body and dark crater.
    #expect(solarGlyph(scene, x: 172, y: 116, z: 124) == 61)
    #expect(solarGlyph(scene, x: 172, y: 120, z: 124) == 58)
    #expect(solarGlyph(scene, x: 92, y: 116, z: 84) == 42)
    #expect(solarGlyph(scene, x: 92, y: 120, z: 84) == 61)
    #expect(solarGlyph(scene, x: 112, y: 116, z: 200) == 120)
    #expect(solarGlyph(scene, x: 107, y: 120, z: 206) == 58)
    // Earth has separate ocean, continent, and polar-cap regions.
    #expect(solarGlyph(scene, x: 168, y: 116, z: 83) == 43)
    #expect(solarGlyph(scene, x: 165, y: 120, z: 80) == 111)
    #expect(solarGlyph(scene, x: 168, y: 127, z: 72) == 45)
    // Jupiter's bands and storm, cyan Uranus, and Neptune's dark storm and upper blue atmosphere.
    #expect(solarGlyph(scene, x: 40, y: 104, z: 128) == 42)
    #expect(solarGlyph(scene, x: 40, y: 116, z: 128) == 61)
    #expect(solarGlyph(scene, x: 36, y: 112, z: 144) == 120)
    #expect(solarGlyph(scene, x: 204, y: 124, z: 44) == 45)
    #expect(solarGlyph(scene, x: 204, y: 116, z: 44) == 43)
    #expect(solarGlyph(scene, x: 64, y: 124, z: 32) == 43)
    #expect(solarGlyph(scene, x: 60, y: 112, z: 42) == 58)
}

@Test func solarSystemRingsMoonsAndOrbitGuidesRetainRealAirGaps() throws {
    let scene = try solarScene()
    // Saturn's two ring bands have both a body-to-ring opening and a gap between the rings.
    #expect(solarGlyph(scene, x: 208, y: 116, z: 208) == 61)
    #expect(solarGlyph(scene, x: 216, y: 116, z: 208) == 42)
    #expect(solarGlyph(scene, x: 204, y: 116, z: 208) == Sculpture.empty)
    #expect(solarGlyph(scene, x: 212, y: 116, z: 208) == Sculpture.empty)
    #expect(solarGlyph(scene, x: 204, y: 116, z: 64) == 64)
    #expect(solarGlyph(scene, x: 204, y: 116, z: 60) == Sculpture.empty)
    #expect(solarGlyph(scene, x: 188, y: 132, z: 76) == 61)
    #expect(solarGlyph(scene, x: 180, y: 128, z: 76) == Sculpture.empty)
    for moon in [(16, 120, 112), (28, 140, 140), (64, 120, 140), (48, 96, 112)] {
        #expect(solarGlyph(scene, x: moon.0, y: moon.1, z: moon.2) != Sculpture.empty)
    }
    #expect(solarGlyph(scene, x: 28, y: 132, z: 136) == Sculpture.empty)
    // The lower guide is dotted, rather than a filled orbital disk or a connector to Mercury.
    #expect(solarGlyph(scene, x: 172, y: 92, z: 128) == 58)
    #expect(solarGlyph(scene, x: 169, y: 92, z: 143) == Sculpture.empty)
    #expect(solarGlyph(scene, x: 160, y: 92, z: 128) == Sculpture.empty)
}

@Test func solarSystemHasAsteroidBeltCometAndElevatedStars() throws {
    let scene = try solarScene()
    #expect(solarGlyph(scene, x: 210, y: 104, z: 128) == 35)
    #expect(solarGlyph(scene, x: 200, y: 104, z: 128) == Sculpture.empty)
    #expect(solarGlyph(scene, x: 36, y: 188, z: 204) == 45)
    #expect(solarGlyph(scene, x: 36, y: 192, z: 204) == 43)
    #expect(solarGlyph(scene, x: 12, y: 236, z: 244) == 45)
    #expect(solarGlyph(scene, x: 6, y: 236, z: 244) == 42)
    #expect(solarGlyph(scene, x: 188, y: 236, z: 120) == 42)
    #expect(solarGlyph(scene, x: 232, y: 196, z: 172) == 42)
    #expect(solarGlyph(scene, x: 120, y: 24, z: 28) == 42)
    #expect(solarGlyph(scene, x: 128, y: 220, z: 128) == Sculpture.empty)
}

private func solarScene() throws -> Sculpture {
    try #require(SculptureExamples.all.first { $0.id == "grand-solar-system" }).sculpture
}

private func solarGlyph(_ sculpture: Sculpture, x: Int, y: Int, z: Int) -> UInt8? {
    sculpture.glyph(at: SculptureCell(x: x, y: sculpture.height - 1 - y, z: z))
}

private func solarExposedFaceCount(_ sculpture: Sculpture) -> Int {
    let offsets = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]
    var faces = 0
    for (z, layer) in sculpture.layers.enumerated() {
        for (index, glyph) in layer.enumerated() where glyph != Sculpture.empty {
            let x = index % sculpture.width
            let y = index / sculpture.width
            for (dx, dy, dz) in offsets {
                let neighbor = sculpture.glyph(at: SculptureCell(x: x + dx, y: y + dy, z: z + dz))
                if neighbor == nil || neighbor == Sculpture.empty { faces += 1 }
            }
        }
    }
    return faces
}
