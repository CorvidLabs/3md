import Foundation
import Testing

@testable import RookSculpture

@Test func exampleCatalogOffersDistinctSculpturesAndSpatialMaps() {
    let examples = SculptureExamples.all
    #expect(examples.count == 21)
    let originalIDs: Set<String> = [
        "character-orb", "woven-torus", "moon-gate", "spiral-tower", "crystal-garden", "little-rocket", "pixel-bonsai",
        "orbital-rings", "hill-observatory", "terraced-island", "canal-city", "alpine-valley",
    ]
    #expect(Set(examples.map(\.id)).isSuperset(of: originalIDs))
    #expect(Set(examples.map(\.id)).count == examples.count)
    #expect(Set(examples.map(\.title)).count == examples.count)
    #expect(Set(examples.map { SculptureCodec.encode($0.sculpture) }).count == examples.count)
    #expect(examples.filter { $0.category == "Maps" }.count == 3)
    #expect(examples.allSatisfy { !$0.summary.isEmpty && $0.title == $0.sculpture.title })
}

@Test func eachExampleBuiltAloneEqualsTheCatalogElementAndBuildsNothingElse() {
    let examples = SculptureExamples.all
    #expect(SculptureExamples.recipes.map(\.id) == examples.map(\.id))
    for expected in examples {
        let recorder = SculptureGenerationRecorder()
        let built = SculptureGenerationProbe.$recorder.withValue(recorder) {
            SculptureExamples.example(id: expected.id)
        }
        #expect(recorder.names == [expected.id])
        guard let built else {
            Issue.record("\(expected.id) is missing from the per-identity builders")
            continue
        }
        #expect(built.id == expected.id)
        #expect(built.title == expected.title)
        #expect(built.summary == expected.summary)
        #expect(built.category == expected.category)
        #expect(built.sculpture.layers == expected.sculpture.layers, "\(expected.id)")
        #expect(built.sculpture == expected.sculpture, "\(expected.id)")
    }
    #expect(SculptureExamples.example(id: "missing-example") == nil)
    let starters = SculptureExamples.compositionStarters
    #expect(starters.map(\.id) == ["moon-gate", "little-rocket", "pixel-bonsai"])
    for starter in starters {
        #expect(examples.first { $0.id == starter.id }?.sculpture == starter.sculpture)
    }
}

@Test(arguments: SculptureExamples.all.map(\.id))
func everyExampleOpensThroughTheRealThreeMDCodec(id: String) throws {
    let example = try #require(SculptureExamples.all.first { $0.id == id })
    let sculpture = example.sculpture
    let data = SculptureCodec.encode(sculpture)
    #expect(data.count < SculptureCodec.maximumBytes)
    #expect((1...Sculpture.maximumDimension).contains(sculpture.width))
    #expect((1...Sculpture.maximumDimension).contains(sculpture.height))
    #expect((2...Sculpture.maximumDimension).contains(sculpture.depth))
    #expect(sculpture.occupiedCount > 100)
    #expect(sculpture.occupiedCount < sculpture.width * sculpture.height * sculpture.depth / 2)
    #expect(sculpture.layers.filter { $0.contains(where: { $0 != Sculpture.empty }) }.count > 1)
    #expect(try SculptureCodec.decode(data) == sculpture)
}

@Test(arguments: SculptureExamples.all.map(\.id))
func shippedThreeMDExamplesMatchTheEditableCatalog(id: String) throws {
    let example = try #require(SculptureExamples.all.first { $0.id == id })
    let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let file = repository.appendingPathComponent("Examples/\(example.id).3md")
    let data = try Data(contentsOf: file)
    #expect(try SculptureCodec.decode(data) == example.sculpture)
    #expect(data == SculptureCodec.encode(example.sculpture))
}

@Test func exampleShapesKeepTheirCharacteristicOpenSpaces() throws {
    let torus = try #require(SculptureExamples.all.first { $0.id == "woven-torus" }).sculpture
    #expect(torus.glyph(at: SculptureCell(x: 11, y: 11, z: 11)) == Sculpture.empty)
    #expect(torus.glyph(at: SculptureCell(x: 20, y: 11, z: 11)) != Sculpture.empty)
    let gate = try #require(SculptureExamples.all.first { $0.id == "moon-gate" }).sculpture
    #expect(gate.glyph(at: SculptureCell(x: 11, y: 14, z: 11)) == Sculpture.empty)
    #expect(gate.glyph(at: SculptureCell(x: 6, y: 17, z: 11)) == 35)
    #expect(gate.glyph(at: SculptureCell(x: 11, y: 9, z: 11)) == 35)
    let city = try #require(SculptureExamples.all.first { $0.id == "canal-city" }).sculpture
    #expect(city.glyph(at: SculptureCell(x: 11, y: 15, z: 4)) == 61)
    #expect(city.glyph(at: SculptureCell(x: 11, y: 11, z: 11)) == 43)
    #expect(city.glyph(at: SculptureCell(x: 11, y: 12, z: 11)) == Sculpture.empty)
}

@Test func mapExamplesHaveElevationAndUseCharacterMaterials() {
    for example in SculptureExamples.all where example.category == "Maps" {
        let sculpture = example.sculpture
        let occupiedRows = Set(
            sculpture.layers.flatMap { layer in
                layer.enumerated().compactMap { $0.element == Sculpture.empty ? nil : $0.offset / sculpture.width }
            }
        )
        let materials = Set(sculpture.layers.flatMap { $0 }.filter { $0 != Sculpture.empty })
        #expect(occupiedRows.count >= 8)
        #expect(materials.count >= 5)
        #expect(materials.contains(61))
    }
}
