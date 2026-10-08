# Editing shared models

Shared voxel editing is in the current app. [Verification](evidence/shared-model-editing/verification-notes.md) records that slice's 321-test lane and packaged Apply, Cancel, Make Unique, Save, and Undo checks. Later pins are recorded in [dependencies](dependencies.md). This page describes the behavior. It does not publish a release.

## Shared edit workflow

In a composition or sparse world, select a reusable voxel model and choose **Edit shared model**. The existing cube/slice editing tools work on an isolated edit session. The session clearly identifies the shared model. **Apply shared edit** validates and replaces that one definition in the original library; every placement that refers to it, including references through nested maps, receives the updated model. **Cancel** returns to the original reference workspace without source changes.

The parent composition/world remains a reusable graph. Applying does not flatten it into voxels. All unchanged definitions, reference bindings, rotations and exact world coordinates remain. An invalid edit, canceled preparation or stale source does not publish a partial graph. Save during a model-edit session must not silently save a detached child as the source scene.

The first slice edits voxel leaf definitions. A tile-map definition retains its map semantics and is outside this voxel-session workflow. Opening an expanded voxel copy remains the separate existing action for detached painting and export.

## Make Unique

For a selected sparse-world instance of a voxel leaf, **Make Unique** creates a separate model definition and changes only that instance's model reference. Its instance ID, exact origin and rotation remain. Other placements continue using the original definition. Choose a new safe model ID; exhausted model capacity, a duplicate ID or an unsupported nested tile model fails without changes.

This slice does not claim deep isolation of a nested map or a single occurrence inside a repeated nested map. Cloning only the outer map would leave children shared, so the app must refuse that interpretation rather than call it unique.

## Undo and saving

Successful Apply and Make Unique each create one parent graph Undo step. Composition and world snapshots include the model library as well as layout fields. Child-session painting Undo remains local until Apply. Undo/Redo restores the complete reference document, and dirty-state comparison includes shared model content. Camera, focus and render distance remain presentation state.

Existing composition/world readable codecs and capacity limits remain. User-selected save paths, cancellation and snapshot baselines keep their existing protections. EXPORT-35 adopted the landed ThreeMD candidate `9dfbdb6` and now pins the published ThreeMD 2.0.0 release exactly, using retained upstream identities and revision-checked transactions. The new [portable workflow](3md-2-adoption.md) documents explicit copy exports and capacity differences. There is no silent migration of existing files or new runtime service/entitlement. The earlier verification record remains evidence of the preceding native editing slice.

## File tools and agents

Explicit-file tooling applies the same pure shared-model operations as the native app and writes a new output. It accepts only supplied paths, requires an expected source/model precondition, and refuses an existing destination. It does not control the running app.

```text
RookTool sculpture reference inspect scene.3md
RookTool sculpture reference inspect scene.3md leaf
RookTool sculpture reference apply scene.3md edit.json edited-scene.3md
```

Inspection with a model ID returns its readable `modelSource`, which can be saved as the expected snapshot file. An edit request uses the existing sculpture command batch:

```json
{
  "version": 1,
  "action": "editModel",
  "modelID": "leaf",
  "expectedModel": "expected-leaf.3md",
  "batch": {"version": 1, "commands": [{"action": "rename", "title": "New leaf"}]}
}
```

The expected model path is explicit and relative paths resolve beside the request. Complete model content must still match; equal dimensions and voxel counts are insufficient. Make Unique instead uses `instanceID`, `newModelID` and `expectedSource`, requiring the complete world file bytes to match. Unknown fields, an invalid later command, cancellation or a changed snapshot produce no output. Only regular files within the existing byte limits are accepted, and atomic publication refuses existing files or symlinks.
