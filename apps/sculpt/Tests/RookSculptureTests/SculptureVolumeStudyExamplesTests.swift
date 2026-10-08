import Foundation
import RookSculpture
import Testing

struct SculptureVolumeStudyExamplesTests {
    @Test func denseEquivalentUsesOneSharedSolidModelToFillExactly1024Cubed() throws {
        let world = try VolumeStudyFixture.dense.get()
        #expect(world.instances.count == 4_096)
        #expect(world.library.models.count == 2)
        #expect(Set(world.instances.map(\.modelID)) == ["solid"])
        let solid = try leaf("solid", in: world)
        #expect(solid.width == 64 && solid.height == 64 && solid.depth == 64)
        #expect(solid.occupiedCount == 262_144)
        #expect(try occupiedCells(in: world) == 1_073_741_824)
        #expect(uniqueLeafBytes(in: world) == 262_144)
        try expectDisjointAlignedDomain(world)
        let axes = Set((0..<16).map { Int64($0 * 64) })
        #expect(Set(world.instances.map(\.origin.x)) == axes)
        #expect(Set(world.instances.map(\.origin.y)) == axes)
        #expect(Set(world.instances.map(\.origin.z)) == axes)
    }

    @Test func landscapeSeparatesItsSparseOccupancyFromItsAddressDomain() throws {
        let world = try VolumeStudyFixture.landscape.get()
        #expect(world.instances.count == 280)
        #expect(world.library.models.count == 9)
        let identifiers = Set(world.instances.map(\.modelID))
        #expect(identifiers == ["meadow", "forest", "river", "castle", "mountain", "terraces", "island", "citadel"])
        #expect(world.instances.filter { $0.origin.y == 960 }.count == 256)
        #expect(world.instances.filter { $0.origin.y < 960 }.count == 24)
        #expect(Set(world.instances.map(\.origin.y)) == [0, 256, 512, 768, 960])
        let occupied = try occupiedCells(in: world)
        #expect(occupied > 10_000_000 && occupied < 30_000_000)
        #expect(occupied < 1_073_741_824 / 20)
        #expect(uniqueLeafBytes(in: world) == 8 * 262_144)
        try expectDisjointAlignedDomain(world)
        let citadel = try leaf("citadel", in: world)
        #expect(citadel.glyph(at: SculptureCell(x: 32, y: 0, z: 32)) != Sculpture.empty)
        let ground = try #require(world.instances.first { $0.origin.x == 960 && $0.origin.z == 960 })
        let edge = try leaf(ground.modelID, in: world)
        #expect(edge.glyph(at: SculptureCell(x: 63, y: 63, z: 63)) != Sculpture.empty)
    }

    @Test func landscapeContainsNavigableCastlesWaterTerracesAndForestAirGaps() throws {
        let world = try VolumeStudyFixture.landscape.get()
        let castle = try leaf("castle", in: world)
        #expect(castle.glyph(at: SculptureCell(x: 10, y: 28, z: 24)) == 64)
        #expect(castle.glyph(at: SculptureCell(x: 32, y: 38, z: 52)) == Sculpture.empty)
        #expect(castle.glyph(at: SculptureCell(x: 32, y: 30, z: 32)) == Sculpture.empty)
        let river = try leaf("river", in: world)
        #expect(river.glyph(at: SculptureCell(x: 32, y: 43, z: 12)) == 43)
        #expect(river.glyph(at: SculptureCell(x: 32, y: 36, z: 32)) == 64)
        let forest = try leaf("forest", in: world)
        #expect(forest.glyph(at: SculptureCell(x: 12, y: 26, z: 12)) == 58)
        #expect(forest.glyph(at: SculptureCell(x: 22, y: 26, z: 22)) == Sculpture.empty)
        let terraces = try leaf("terraces", in: world)
        #expect(terraces.glyph(at: SculptureCell(x: 32, y: 28, z: 32)) == 43)
        #expect(terraces.glyph(at: SculptureCell(x: 33, y: 28, z: 32)) == 42)
        let island = try leaf("island", in: world)
        #expect(island.glyph(at: SculptureCell(x: 0, y: 63, z: 0)) == Sculpture.empty)
        #expect(island.glyph(at: SculptureCell(x: 32, y: 60, z: 32)) == 64)
    }

    @Test func studyFactoriesAreDeterministicAndPreserveFiniteProductionLimits() throws {
        let dense = try VolumeStudyFixture.dense.get()
        let landscape = try VolumeStudyFixture.landscape.get()
        #expect(try SculptureVolumeStudyExamples.denseEquivalentWorld() == dense)
        #expect(try SculptureVolumeStudyExamples.landscapeWorld() == landscape)
        #expect(Sculpture.maximumDimension == 256)
        #expect(SculptureExamples.all.count == 21)
        for world in [dense, landscape] {
            #expect(world.library.models.count <= SculptureComposition.maximumModels)
            let resolvedBytes = world.library.models.values.reduce(0) { total, model in
                switch model {
                case .sculpture(let sculpture): total + sculpture.width * sculpture.height * sculpture.depth
                case .tiles(let map):
                    total + map.width * map.height * map.depth * map.tileSize.width * map.tileSize.height
                        * map.tileSize.depth
                }
            }
            #expect(resolvedBytes <= SculptureComposition.maximumResolvedVoxelBytes)
            #expect(world.instances.count <= SculptureWorld.maximumInstances)
            #expect(Set(world.instances.map(\.id)).count == world.instances.count)
            #expect(world.instances.allSatisfy { $0.quarterTurns == 0 && $0.modelID != world.library.rootID })
            let encoded = try SculptureWorldCodec.encode(world)
            #expect(encoded.count < SculptureWorldCodec.maximumBytes)
            #expect(try SculptureWorldCodec.decode(encoded) == world)
        }
    }

    @Test func studyFactoriesRespectCancelledTasksBeforeConstructingTheirLibraries() async throws {
        let factories: [@Sendable () throws -> SculptureWorld] = [
            SculptureVolumeStudyExamples.denseEquivalentWorld,
            SculptureVolumeStudyExamples.landscapeWorld,
        ]
        for factory in factories {
            let gate = VolumeStudyCancellationGate()
            let task = Task {
                await gate.wait()
                return try factory()
            }
            task.cancel()
            await gate.release()
            do {
                _ = try await task.value
                Issue.record("A cancelled study unexpectedly constructed its world.")
            } catch is CancellationError {
                // Cancellation remains distinct from model validation and capacity errors.
            }
        }
    }

    private func leaf(_ identifier: String, in world: SculptureWorld) throws -> Sculpture {
        let model = try #require(world.library.models[identifier])
        guard case .sculpture(let sculpture) = model else { throw VolumeStudyTestError.expectedLeaf }
        return sculpture
    }

    private func occupiedCells(in world: SculptureWorld) throws -> Int64 {
        try world.instances.reduce(Int64(0)) { total, instance in
            total + Int64(try leaf(instance.modelID, in: world).occupiedCount)
        }
    }

    private func uniqueLeafBytes(in world: SculptureWorld) -> Int {
        world.library.models.values.reduce(0) { total, model in
            guard case .sculpture(let sculpture) = model else { return total }
            return total + sculpture.width * sculpture.height * sculpture.depth
        }
    }

    private func expectDisjointAlignedDomain(_ world: SculptureWorld) throws {
        #expect(Set(world.instances.map(\.origin)).count == world.instances.count)
        var minimum = SculptureWorldPoint(x: Int64.max, y: Int64.max, z: Int64.max)
        var maximum = SculptureWorldPoint(x: Int64.min, y: Int64.min, z: Int64.min)
        for instance in world.instances {
            let sculpture = try leaf(instance.modelID, in: world)
            #expect(sculpture.width == 64 && sculpture.height == 64 && sculpture.depth == 64)
            let origin = instance.origin
            #expect([origin.x, origin.y, origin.z].allSatisfy { $0.isMultiple(of: 64) && (0..<1024).contains($0) })
            minimum = SculptureWorldPoint(
                x: min(minimum.x, origin.x),
                y: min(minimum.y, origin.y),
                z: min(minimum.z, origin.z)
            )
            maximum = SculptureWorldPoint(
                x: max(maximum.x, origin.x + 64),
                y: max(maximum.y, origin.y + 64),
                z: max(maximum.z, origin.z + 64)
            )
        }
        #expect(minimum == SculptureWorldPoint(x: 0, y: 0, z: 0))
        #expect(maximum == SculptureWorldPoint(x: 1024, y: 1024, z: 1024))
    }
}

private enum VolumeStudyFixture {
    static let dense = Result { try SculptureVolumeStudyExamples.denseEquivalentWorld() }
    static let landscape = Result { try SculptureVolumeStudyExamples.landscapeWorld() }
}

private enum VolumeStudyTestError: Error { case expectedLeaf }

private actor VolumeStudyCancellationGate {
    private var released = false
    private var waiter: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { continuation in waiter = continuation }
    }

    func release() {
        released = true
        waiter?.resume()
        waiter = nil
    }
}
