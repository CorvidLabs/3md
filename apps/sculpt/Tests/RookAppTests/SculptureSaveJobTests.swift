import Foundation
import RookSculpture
import Testing

@testable import RookApp

@MainActor
private func preparedResult(_ job: SculptureSaveJob) async throws -> SculpturePreparedSave {
    for _ in 0..<400 {
        if let result = job.result { return result }
        if let error = job.error {
            Issue.record("\(error)")
            break
        }
        try await Task.sleep(for: .milliseconds(5))
    }
    return try #require(job.result)
}

@MainActor @Test(arguments: SculptureStorageFormat.allCases)
func asyncSavePreservesSnapshotAndLaterEditsStayDirty(format: SculptureStorageFormat) async throws {
    let workspace = SculptureWorkspace()
    workspace.replace(with: .orb(), opened: true)
    let snapshot = workspace.sculpture
    let job = SculptureSaveJob()
    job.start(snapshot, format: format, documentGeneration: workspace.documentGeneration)
    workspace.titleDraft = "Edited after Save"
    #expect(workspace.commitTitle())
    workspace.paint(SculptureCell(x: 0, y: 0, z: 0), start: true)
    let prepared = try await preparedResult(job)
    #expect(prepared.sculpture == snapshot)
    #expect(prepared.format == format)
    #expect(try SculptureDocumentCodec.decode(prepared.data) == snapshot)
    workspace.markSaved(prepared)
    #expect(workspace.isDirty)
    #expect(workspace.sculpture.title == "Edited after Save")
    #expect(workspace.sculpture.occupiedCount == snapshot.occupiedCount + 1)
    #expect(!job.isRunning)
}

@MainActor @Test
func replacedDocumentCannotBeMarkedSavedByAnEarlierSave() async throws {
    let workspace = SculptureWorkspace()
    let job = SculptureSaveJob()
    job.start(workspace.sculpture, format: .compact, documentGeneration: workspace.documentGeneration)
    let prepared = try await preparedResult(job)
    workspace.replace(with: .blank(), opened: true)
    let message = workspace.message
    workspace.markSaved(prepared)
    #expect(!workspace.isDirty)
    #expect(workspace.message == message)
    workspace.paint(SculptureCell(x: 0, y: 0, z: 0), start: true)
    #expect(workspace.isDirty)
    workspace.undo()
    #expect(!workspace.isDirty)
}

@MainActor @Test
func cancelledSaveDoesNotPublishAndCanBeRetried() async throws {
    let workspace = SculptureWorkspace()
    workspace.paint(SculptureCell(x: 0, y: 0, z: 0), start: true)
    let job = SculptureSaveJob()
    job.start(workspace.sculpture, format: .compact, documentGeneration: workspace.documentGeneration)
    job.cancel()
    #expect(job.result == nil)
    #expect(!job.isRunning)
    #expect(workspace.isDirty)
    job.start(.blank(), format: .readable, documentGeneration: workspace.documentGeneration)
    let result = try await preparedResult(job)
    #expect(result.sculpture == .blank())
    #expect(result.format == .readable)
    #expect(try SculptureDocumentCodec.decode(result.data) == .blank())
    #expect(job.error == nil)
    #expect(workspace.isDirty)
}
