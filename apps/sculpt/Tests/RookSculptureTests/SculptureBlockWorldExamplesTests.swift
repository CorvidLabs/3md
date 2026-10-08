import Foundation
import RookSculpture
import Testing

struct SculptureBlockWorldExamplesTests {
    @Test func chunkLibraryIsDeterministicAndExpandsToTheCompleteLandscape() throws {
        let fixture = try BlockhavenTestFixture.cached.get()
        let repeated = try SculptureBlockWorldExamples.composition()
        let equal = repeated == fixture.composition
        #expect(equal)
        #expect(fixture.composition.title == "Blockhaven valley")
        #expect(fixture.composition.models.count == 37)
        #expect(fixture.sculpture.width == 192 && fixture.sculpture.height == 64 && fixture.sculpture.depth == 192)
        #expect(fixture.sculpture.occupiedCount > 100_000)
        let root = try #require(fixture.composition.models[fixture.composition.rootID])
        guard case .tiles(let map) = root else { Issue.record("Blockhaven needs a tile root"); return }
        #expect(map.width == 6 && map.height == 1 && map.depth == 6)
        #expect(map.bindings.count == 36)
        #expect(map.tileSize.width == 32 && map.tileSize.height == 64 && map.tileSize.depth == 32)
        let canonical = try SculptureCompositionCodec.encode(fixture.composition)
        let reopened = try SculptureCompositionCodec.decode(canonical)
        let roundTrip = reopened == fixture.composition
        #expect(roundTrip)
        let canonicalAgain = try SculptureCompositionCodec.encode(reopened)
        #expect(canonical.elementsEqual(canonicalAgain))
    }

    @Test func adjacentChunksHaveContinuousGroundAndAConnectedRiverAcrossEveryDepthSeam() throws {
        let fixture = try BlockhavenTestFixture.cached.get()
        let landscape = fixture.sculpture
        for boundary in stride(from: 32, through: 160, by: 32) {
            let westGround = try grassY(in: landscape, x: boundary - 1, z: 0)
            let eastGround = try grassY(in: landscape, x: boundary, z: 0)
            let northGround = try grassY(in: landscape, x: 0, z: boundary - 1)
            let southGround = try grassY(in: landscape, x: 0, z: boundary)
            #expect(abs(westGround - eastGround) <= 1)
            #expect(abs(northGround - southGround) <= 1)
            let upstream = Set((70...110).filter { isWater(glyph(landscape, $0, 46, boundary - 1)) })
            let downstream = Set((70...110).filter { isWater(glyph(landscape, $0, 46, boundary)) })
            #expect(upstream.count >= 9 && downstream.count >= 9)
            #expect(!upstream.intersection(downstream).isEmpty)
        }
        for z in 0..<6 {
            for x in 0..<6 {
                let chunk = try chunk(in: fixture.composition, x: x, z: z)
                #expect(chunk.width == 32 && chunk.height == 64 && chunk.depth == 32)
                for localZ in [0, 31] {
                    for localX in [0, 31] {
                        for y in 55..<64 {
                            #expect(glyph(chunk, localX, y, localZ) != Sculpture.empty)
                            #expect(
                                glyph(chunk, localX, y, localZ) == glyph(landscape, x * 32 + localX, y, z * 32 + localZ)
                            )
                        }
                    }
                }
            }
        }
    }

    @Test func landscapeHasDeepHillsWaterBanksCavesAndThreeDistinctTreeSilhouettes() throws {
        let landscape = try BlockhavenTestFixture.cached.get().sculpture
        let summit = try grassY(in: landscape, x: 153, z: 44)
        let lowland = try grassY(in: landscape, x: 110, z: 165)
        #expect(lowland - summit >= 10)
        #expect(isWater(glyph(landscape, 92, 46, 116)))
        #expect(glyph(landscape, 92, 54, 116) == 61)
        #expect(glyph(landscape, 92, 50, 116) == 43)
        let bank = try grassY(in: landscape, x: 92, z: 144)
        #expect(bank < 46)
        #expect(glyph(landscape, 158, 40, 55) == Sculpture.empty)
        #expect(glyph(landscape, 158, 34, 55) != Sculpture.empty)
        #expect(glyph(landscape, 191, 42, 41) == Sculpture.empty)
        #expect(glyph(landscape, 191, 46, 41) != Sculpture.empty)
        var treeHeights: [Int] = []
        for (x, z) in [(22, 154), (48, 154), (68, 163)] {
            let ground = try grassY(in: landscape, x: x, z: z)
            let top = try #require((0..<ground).first { glyph(landscape, x, $0, z) != Sculpture.empty })
            #expect(glyph(landscape, x, ground - 1, z) == 61)
            #expect((top..<ground).contains { glyph(landscape, x + 1, $0, z) == 58 })
            treeHeights.append(ground - top)
        }
        #expect(treeHeights == [8, 9, 11])
        let materials = Set(landscape.layers.flatMap { $0 }.filter { $0 != Sculpture.empty })
        #expect(materials == Set(Sculpture.palette))
    }

    @Test func villageAndLandmarksHaveUsableInteriorsDoorsWindowsCropsAndRoofs() throws {
        let landscape = try BlockhavenTestFixture.cached.get().sculpture
        #expect(glyph(landscape, 40, 29, 80) == 120)
        #expect(glyph(landscape, 35, 37, 79) == 43)
        #expect(glyph(landscape, 40, 38, 80) == Sculpture.empty)
        #expect(glyph(landscape, 41, 40, 85) == Sculpture.empty)
        #expect(glyph(landscape, 52, 43, 110) == 61)
        #expect(glyph(landscape, 33, 42, 121) == 42)
        #expect(glyph(landscape, 30, 43, 121) == 43)
        #expect(glyph(landscape, 52, 41, 97) == 43)
        #expect(glyph(landscape, 52, 34, 97) == 120)
        #expect(glyph(landscape, 90, 43, 90) == 61)
        #expect(glyph(landscape, 24, 27, 40) == 64)
        #expect(glyph(landscape, 40, 29, 56) == Sculpture.empty)
        #expect(glyph(landscape, 23, 15, 24) == 64)
        #expect(glyph(landscape, 56, 8, 26) == 42)
        #expect(glyph(landscape, 40, 16, 40) == 120)
        let ruinGround = try grassY(in: landscape, x: 149, z: 158)
        #expect(glyph(landscape, 149, ruinGround - 1, 158) == 64)
        #expect(glyph(landscape, 154, 60, 162) != Sculpture.empty)
    }

    @Test func sparsePlacementsUseExactlyAlignedChunkModelsAndStayWithinGeometryBudgets() throws {
        let fixture = try BlockhavenTestFixture.cached.get()
        let world = try SculptureBlockWorldExamples.world()
        let sameLibrary = world.library == fixture.composition
        #expect(sameLibrary)
        #expect(world.instances.count == 36)
        #expect(Set(world.instances.map(\.id)).count == 36)
        #expect(world.instances.allSatisfy { $0.quarterTurns == 0 && $0.origin.y == 0 })
        var chunkFaces = 0
        for z in 0..<6 {
            for x in 0..<6 {
                let instance = try #require(world.instances.first { $0.id == "land-\(x)-\(z)" })
                #expect(instance.modelID == "chunk-\(x)-\(z)")
                #expect(instance.origin == SculptureWorldPoint(x: Int64(x * 32), y: 0, z: Int64(z * 32)))
                chunkFaces += exteriorFaces(try chunk(in: fixture.composition, x: x, z: z))
            }
        }
        let fullFaces = exteriorFaces(fixture.sculpture)
        #expect(fullFaces > 0 && fullFaces <= 250_000)
        #expect(chunkFaces >= fullFaces && chunkFaces <= 500_000)
        let data = try SculptureWorldCodec.encode(world)
        let reopened = try SculptureWorldCodec.decode(data)
        let sameWorld = reopened == world
        #expect(sameWorld)
    }

    @Test func canceledGenerationThrowsInsteadOfReturningAPartialLibraryOrWorld() async {
        for world in [false, true] {
            let gate = BlockhavenCancellationGate()
            let task = Task {
                await gate.wait()
                if world {
                    _ = try SculptureBlockWorldExamples.world()
                } else {
                    _ = try SculptureBlockWorldExamples.composition()
                }
            }
            task.cancel()
            await gate.release()
            await #expect(throws: CancellationError.self) { try await task.value }
        }
    }

    private func glyph(_ sculpture: Sculpture, _ x: Int, _ y: Int, _ z: Int) -> UInt8? {
        sculpture.glyph(at: .init(x: x, y: y, z: z))
    }

    private func isWater(_ glyph: UInt8?) -> Bool { glyph == 43 || glyph == 45 }

    private func grassY(in sculpture: Sculpture, x: Int, z: Int) throws -> Int {
        try #require((0..<sculpture.height).first { glyph(sculpture, x, $0, z) == 111 })
    }

    private func chunk(in composition: SculptureComposition, x: Int, z: Int) throws -> Sculpture {
        let model = try #require(composition.models["chunk-\(x)-\(z)"])
        guard case .sculpture(let sculpture) = model else { throw BlockhavenFixtureError.expectedChunk }
        return sculpture
    }

    private func exteriorFaces(_ sculpture: Sculpture) -> Int {
        let width = sculpture.width
        let height = sculpture.height
        let depth = sculpture.depth
        let layers = sculpture.layers
        var faces = 0
        for z in 0..<depth where sculpture.containsOccupiedCells(inLayer: z) {
            for y in 0..<height where sculpture.containsOccupiedCells(inRow: y, ofLayer: z) {
                for x in 0..<width {
                    let index = y * width + x
                    guard layers[z][index] != Sculpture.empty else { continue }
                    if x == 0 || layers[z][index - 1] == Sculpture.empty { faces += 1 }
                    if x == width - 1 || layers[z][index + 1] == Sculpture.empty { faces += 1 }
                    if y == 0 || layers[z][index - width] == Sculpture.empty { faces += 1 }
                    if y == height - 1 || layers[z][index + width] == Sculpture.empty { faces += 1 }
                    if z == 0 || layers[z - 1][index] == Sculpture.empty { faces += 1 }
                    if z == depth - 1 || layers[z + 1][index] == Sculpture.empty { faces += 1 }
                }
            }
        }
        return faces
    }
}

private struct BlockhavenTestFixture: Sendable {
    let composition: SculptureComposition
    let sculpture: Sculpture

    static let cached = Result {
        let composition = try SculptureBlockWorldExamples.composition()
        return BlockhavenTestFixture(composition: composition, sculpture: try composition.expanded())
    }
}

private enum BlockhavenFixtureError: Error { case expectedChunk }

private actor BlockhavenCancellationGate {
    private var released = false
    private var waiter: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func release() { released = true; waiter?.resume(); waiter = nil }
}
