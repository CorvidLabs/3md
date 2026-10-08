import RookSculpture
import Testing

@Suite("Composition example")
struct SculptureCompositionExampleTests {
    @Test func startersAreBoundedAndIndependent() {
        let starters = SculptureExamples.compositionStarters
        #expect(starters.map(\.id) == ["moon-gate", "little-rocket", "pixel-bonsai"])
        #expect(
            starters.allSatisfy { $0.sculpture.width == 24 && $0.sculpture.height == 24 && $0.sculpture.depth == 24 }
        )
    }

    @Test func repeatedNestedReferencesRoundTripAndExpandExactly() throws {
        let composition = try SculptureCompositionExamples.courtyard()
        #expect(composition.models.count == 4)
        let data = try SculptureCompositionCodec.encode(composition)
        #expect(try SculptureCompositionCodec.decode(data) == composition)
        let expanded = try composition.expanded()
        #expect(expanded.title == "Courtyard of courtyards")
        #expect(expanded.width == 144 && expanded.height == 24 && expanded.depth == 144)
        let starters = SculptureExamples.compositionStarters
        #expect(
            expanded.occupiedCount == 16 * (starters[0].sculpture.occupiedCount + starters[2].sculpture.occupiedCount)
        )
        let compact = try SculptureBinaryCodec.encode(expanded)
        #expect(try SculptureBinaryCodec.decode(compact) == expanded)
    }

    @Test func sparseWorldExamplePreservesTrillionCellDistancesWithoutDenseAllocation() throws {
        let world = try SculptureWorldExamples.wideWorld()
        #expect(world.instances.count == 4)
        #expect(world.instances.last?.origin == SculptureWorldPoint(x: 1_000_000_000_000, y: 0, z: -1_000_000_000_000))
        let data = try SculptureWorldCodec.encode(world)
        #expect(data.count < 100_000)
        #expect(try SculptureWorldCodec.decode(data) == world)
    }
}
