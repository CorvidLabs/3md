import RookSculpture
import Testing

@testable import RookApp

@Suite("Reference save snapshots", .serialized)
@MainActor
struct SculptureGraphSaveJobTests {
    @Test func compositionPreparationRetainsReferencesAndLeavesVoxelBaselineAlone() async throws {
        let workspace = SculptureWorkspace()
        workspace.replace(with: .orb(), opened: true)
        let document = try SculptureCompositionExamples.courtyard()
        let job = SculptureGraphSaveJob()
        job.start(.composition(document))
        for _ in 0..<100_000 where job.isRunning { await Task.yield() }
        let result = try #require(job.result)
        #expect(try SculptureCompositionCodec.decode(result.data) == document)
        #expect(result.document == .composition(document))
        #expect(!workspace.isDirty)
        #expect(workspace.sculpture == .orb())
    }

    @Test func cancellationAndReplacementCannotPublishAnOldGraph() async throws {
        let world = try SculptureWorldExamples.wideWorld()
        let composition = try SculptureCompositionExamples.courtyard()
        let job = SculptureGraphSaveJob()
        job.start(.world(world))
        job.cancel()
        job.start(.composition(composition))
        for _ in 0..<100_000 where job.isRunning { await Task.yield() }
        #expect(job.result?.document == .composition(composition))
        #expect(job.error == nil)
        job.cancel()
        for _ in 0..<100 { await Task.yield() }
        #expect(job.result == nil)
        #expect(!job.isRunning)
    }

    @Test func worldPreparationPreservesExactSparseCoordinates() async throws {
        let world = try SculptureWorldExamples.wideWorld()
        let job = SculptureGraphSaveJob()
        job.start(.world(world))
        for _ in 0..<100_000 where job.isRunning { await Task.yield() }
        let prepared = try #require(job.result)
        #expect(try SculptureWorldCodec.decode(prepared.data) == world)
        #expect(prepared.document == .world(world))
        #expect(prepared.data.count < 100_000)
    }
}
