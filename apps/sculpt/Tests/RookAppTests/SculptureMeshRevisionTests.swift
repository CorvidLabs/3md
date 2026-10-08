import RookSculpture
import Testing

@testable import RookApp

@Test @MainActor func cameraMotionDoesNotInvalidateVoxelMesh() {
    let workspace = SculptureWorkspace()
    let revision = workspace.sculptureRevision
    workspace.camera.yaw += 0.5
    workspace.camera.pitch += 0.2
    workspace.camera.zoom = 1.4
    workspace.layer = 2
    workspace.cubeOpacity = 0.7
    workspace.paintsIn3D = true
    #expect(workspace.sculptureRevision == revision)
}

@Test @MainActor func editsUndoRedoAndReplacementInvalidateVoxelMesh() {
    let workspace = SculptureWorkspace()
    workspace.replace(with: .blank())
    let revision = workspace.sculptureRevision
    workspace.paint(SculptureCell(x: 0, y: 0, z: 0), start: true)
    workspace.endStroke()
    let painted = workspace.sculptureRevision
    #expect(painted != revision)
    workspace.undo()
    let undone = workspace.sculptureRevision
    #expect(undone != painted)
    workspace.redo()
    #expect(workspace.sculptureRevision != undone)
    let beforeReplacement = workspace.sculptureRevision
    workspace.replace(with: .blank())
    #expect(workspace.sculptureRevision != beforeReplacement)
}

@Test @MainActor func titleEditsAndTheirUndoKeepGeometryButRemainDirty() {
    let workspace = SculptureWorkspace()
    workspace.replace(with: .blank(), opened: true)
    let revision = workspace.sculptureRevision
    workspace.titleDraft = "New title"
    #expect(workspace.commitTitle())
    #expect(workspace.sculpture.title == "New title")
    #expect(workspace.isDirty)
    #expect(workspace.sculptureRevision == revision)
    workspace.undo()
    #expect(workspace.sculpture.title == "Untitled")
    #expect(!workspace.isDirty)
    #expect(workspace.sculptureRevision == revision)
    workspace.redo()
    #expect(workspace.isDirty)
    #expect(workspace.sculptureRevision == revision)
}
