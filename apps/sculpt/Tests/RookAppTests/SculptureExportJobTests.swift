import Foundation
import RookSculpture
import Testing

@testable import RookApp

@Test("Export names cannot introduce paths or hidden files")
@MainActor
func safeExportNames() {
    #expect(SculptureExportJob.filename(title: "../My / sculpture", kind: .mesh) == "My-sculpture.obj")
    #expect(SculptureExportJob.filename(title: "***", kind: .gif) == "Sculpture.gif")
    #expect(SculptureExportJob.filename(title: "Moon gate", kind: .movie) == "Moon-gate.mp4")
}

@Test("Preparing a mesh export keeps the source and cleans up its private staging folder")
@MainActor
func exportJobSnapshotAndCleanup() async throws {
    let original = Sculpture.orb()
    let job = SculptureExportJob()
    job.start(
        sculpture: original,
        camera: SculptureCamera(),
        kind: .mesh,
        duration: 4,
        framesPerSecond: 10,
        columns: 64,
        rows: 36
    )
    let deadline = ContinuousClock.now + .seconds(5)
    while job.isRunning, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(!job.isRunning)
    #expect(job.error == nil)
    let output = try #require(job.output)
    let folder = output.deletingLastPathComponent()
    #expect(FileManager.default.fileExists(atPath: output.path))
    #expect(original == Sculpture.orb())
    #expect(job.progress == 1)
    job.cleanup()
    #expect(!FileManager.default.fileExists(atPath: folder.path))
    #expect(job.output == nil)
}
