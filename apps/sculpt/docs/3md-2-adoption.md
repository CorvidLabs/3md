# ThreeMD 2 adoption in Sculpt

EXPORT-35 adopted the immutable landed ThreeMD candidate
`9ac2454dfec51a9d575a030236f046462059f847` while 2.0.0 was prepared. Sculpt now
pins the published release exactly (`exact: "2.0.0"`, tag `v2.0.0` at
`ca2d1e34f20be3c5100d0fd1474a8ee9cc78d2d4`), whose library sources are identical
to that candidate.

This pin follows Leif's merge of ThreeMD PR66 on 2026-10-06. The landed tree
equals the tested feature head `7f07f0f58866b42b2ed9fc4568a908abc5959dbf`.
The repair adds consistent linked-composition limits and refusal behavior to
the upstream candidate. Sculpt keeps its existing native and portable scene
adapters. [Fresh integration evidence](evidence/landed-3md-integration/README.md)
is separate from the original adoption receipts, which describe the earlier
`9dfbdb6` dependency.

The prepared scope adds explicit portable text and uncompressed binary copies
of voxel scenes, reusable compositions and sparse worlds. Open detects their
contents and routes them into the existing editor. Shared definitions, unused
models, bindings, rotations and exact Int64 anchors remain scene data. Camera,
focus and render distance remain session state.

The core represents scenes through ThreeMD documents and self-contained
compositions. Sparse placements use strict Int64 JSON records, never Double
plane offsets. Upstream snapshots carry stable identities and exact canonical
revisions; atomic shared-model edits validate the whole candidate before native
Apply publishes one parent Undo step. Native parent revision checks remain.

Existing `ascii-sculpture-1`, `ascii-composition-1`, `ascii-world-1` and native
compact files stay readable. Default Save retains the native behavior. Portable
export is an explicit copy and never marks unsaved work saved or automatically
migrates a chosen file.

Portable graph definitions have an upstream 16 MiB canonical-byte ceiling.
Legacy scene storage retains its 20 MiB file bound. Some valid native scenes
therefore require the legacy save path. A portable capacity refusal explains
that difference without modifying the scene. Optional Apple LZFSE is not the
cross-language interchange baseline.

Product modules remain pure Swift with SDK dependencies, a user-selected-file
sandbox and no network or process launches. The development tool may inspect
explicit files and write validated results to new destinations. Generic
ThreeMD Markdown is not automatically a supported Sculpt scene.

File > Export portable ThreeMD in the macOS menu bar offers Readable 3md copy
and Binary 3mdb copy. The copy panel restores the same composition/world draft,
including its history and current selection. Cancel leaves the saved baseline
unchanged. Portable copies use general binary compression none for all three
language implementations. Native compact saves retain the separate Apple
LZFSE container.

The explicit-file development interface is:

```text
RookTool sculpture portable inspect INPUT
RookTool sculpture portable export INPUT OUTPUT.3md|OUTPUT.3mdb
RookTool sculpture portable apply INPUT REQUEST.json OUTPUT.3md|OUTPUT.3mdb
RookTool sculpture portable insert INPUT REQUEST.json OUTPUT.3md|OUTPUT.3mdb
```

Apply requests require exactly version 1, modelID, expectedScene and batch.
expectedScene names an explicit captured source file; relative paths resolve
beside the request. The entire canonical scene revision must still match.
Outputs are new files published atomically, with no overwrite of an existing
file or symlink. The interface does not control the running app.
Insert requests place explicitly listed files into a composition or world with
the app's insertion rules; see [file insertion](file-insertion.md).

All 350 app tests and 31 harness tests pass. After a contract-table correction,
strict current SpecSync reports five specs, 65/65 files and 15,953/15,953 lines,
with zero warnings; source boundaries, release fixtures and packaging pass.
The six deterministic portable files additionally passed 17,091 imports across
nine Swift/TypeScript/Rust pairings. Native observations and receipts are in
[the verification record](evidence/3md-2-adoption/verification-notes.md).

Scoped source review found and verified repairs for unmarked general-binary
voxel adoption and bounded native opened-descriptor reading. Product verification
does not close historical lifecycle gaps. Current publication/lifecycle status
is recorded separately from these results. Historical records are unchanged.
Source coverage is structural evidence; finite tests are not proof of every
input or all operating systems.

## Linked compositions

COMPOSITION-40 uses ThreeMD 2.0.0's file composition API (`DocumentFileComposition` and `DocumentFileSource`) with the same exact pin. Sculpt supplies the bytes of reachable files from a project folder the person chooses and enforces its own interim caps; see [Linked compositions](linked-composition.md).
