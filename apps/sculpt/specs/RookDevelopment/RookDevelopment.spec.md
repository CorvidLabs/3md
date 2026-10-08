---
module: RookDevelopment
version: 21
status: active
files:
  - Sources/RookTool/SculptureVolumeStudy.swift
  - Sources/RookTool/SculptureVolumeStudyWorldExport.swift
  - Sources/RookTool/SculpturePortableTool.swift
  - Sources/RookTool/main.swift
  - Sources/RookTool/SculptureExampleExport.swift
  - Sources/RookTool/SculptureMathExampleExport.swift
  - Sources/RookTool/SculptureCommandTool.swift
  - Sources/RookTool/SculptureReferenceModelTool.swift
  - Sources/RookTool/SculptureInsertTool.swift
  - Sources/RookTool/SculptureLinkedInput.swift
  - Sources/RookTooling/RookTooling.swift
  - Sources/RookTooling/CommandRunner.swift
  - Sources/RookTooling/SourceBoundaries.swift
  - Sources/RookTooling/AppPackaging.swift
  - Sources/RookVerification/TestLogAssessment.swift
  - Sources/RookVerification/SwiftTestLog.swift
  - Sources/RookVerification/SwiftTestRunner.swift
db_tables: []
depends_on: [RookSculpture, RookRendering]
---

# RookDevelopment

## Purpose

Swift-only repository development tools, separate from the product dependency graph. Product targets are RookApp, RookCore, RookSculpture, and RookRendering. The RookTool `examples` and `blockhaven` commands may use the sculpture libraries to write fixtures. Intent: LOCAL-1, SHELL-1, SCULPTURE-10, GALLERY-11, GALLERY-17, SCULPTURE-20, CUBES-23, GALLERY-24, GALLERY-26, CUBES-27, EXPORT-28, RENDER-29, COMPOSITION-30, WORLD-31, GALLERY-32.

## Public API

WORLD-36 adds explicit development commands `volume-study --output /absolute/new-directory --dense-1024` and `volume-worlds --output /absolute/new-directory`. The former requires a release build, physically initializes and verifies a literal 1 GiB buffer, uses bounded streaming LZFSE scratch, guards conservative available-memory observations and emits experimental raw voxel payload plus a phase/checksum/memory receipt. That payload is not a ThreeMD format. The latter writes solid/landscape 1024-domain worlds as native readable and explicit portable text/uncompressed binary, verifies exact round trips, and reports unique bytes, repeated occupancy, instance counts and CPU encode/decode times. Both refuse existing output directories. A separate opt-in release native Metal test reports scene preparation, camera submission and synchronized snapshot timings with actual culling/detail/proxy/omission/mesh counts. Ordinary tests use small dense buffers, and product capacities/entitlements remain unchanged.

EXPORT-35 adds `RookTool sculpture portable inspect INPUT`, `export INPUT OUTPUT` and `apply INPUT REQUEST OUTPUT`. Input detection accepts supported native and portable scene contents. Export explicitly chooses portable text or uncompressed binary from the new output's .3md/.3mdb extension. Apply's strict version-1 request names `modelID`, an explicit `expectedScene` and a validated existing edit `batch`; its expected-scene file supplies an exact canonical revision. References and exact world anchors stay intact. Inspection reports scene kind, revision byte count and bounded structured diagnostics. Output uses the existing atomic publication contract and refuses an existing destination. No command controls the running app.

COMPOSITION-39 adds `RookTool sculpture portable insert INPUT REQUEST.json OUTPUT.3md|OUTPUT.3mdb` and `RookTool sculpture reference insert INPUT.3md REQUEST.json NEW.3md`. A strict version-1 request of at most 256 KiB lists `files` relative to the request file, exactly one of a composition `cell` or a world `focus` given as canonical decimal Int64 strings, optional `replaceOccupied` (default false) and, for portable insert only, an `expectedScene` whose exact revision must match. Files are placed in request order, read as regular files without following symlinks, and checked for count, cells, glyphs, fit, size and native reopen budget, with each refusal naming the file. World or generic Markdown children are refused. Portable insert keeps portable data and refuses rather than dropping it; a native INPUT is captured as a parent without portable data, and when no portable data is carried and the result exceeds the portable limit, the refusal suggests reference insert. Reference insert writes native readable output from scene values, refuses a portable parent, and its receipt lists inputs whose portable data the native result does not carry. Output is published only as a new file, and the JSON receipt lists placed models with titles and targets or exact origins, replaced glyphs and, when portable, the revision size and diagnostics. No command controls the running app.

### REQUIREMENT REQ-RookDevelopment-013

For EXPORT-35, explicit-file development commands SHALL inspect portable and legacy scenes and export or apply validated upstream-backed shared edits to a new selected output, with bounded structured diagnostics and exact revision guards. Invalid, stale or cancelled inputs produce no output, and existing destinations are never replaced. Native and tool adapters share the same core rules. Meaningful semantic/native/tool tests and the full pinned Swift lane record actual evidence; product targets do not import development tools or launch processes or network connections.

COMPOSITION-34 adds `sculpture reference inspect INPUT.3md [MODEL_ID]` and `sculpture reference apply INPUT.3md REQUEST.json NEW.3md`. Inspection reports shared model facts and exact world coordinates; optional voxel inspection exposes readable model source for preparing an expected snapshot. Strict version-1 editModel requests name an expected model snapshot and existing typed voxel batch; makeUnique requests name an expected full source snapshot and one world instance/new model ID. Explicit snapshot paths resolve relative to the request. Exact model equality or exact input bytes reject stale work. The adapter uses the same `SculptureModelEditing` values as native UI and publishes a new bounded readable composition/world atomically, refusing existing outputs. It adds no app service or dependency.

COMPOSITION-30 adds explicit composition commands. `sculpture compose MANIFEST.json NEW.3md` reads only bounded regular model files named by the chosen manifest, embeds their definitions with private remapped nested IDs, validates the complete graph and publishes a new self-contained composition without replacing existing output. `sculpture expand COMPOSITION.3md NEW.3md|3mdb` explicitly creates a detached voxel file. Composition inspection reports the graph and expanded facts; normal apply refuses reference documents and asks for explicit expansion first. Native runtime targets do not call these commands. The examples generator also writes a separate nested courtyard composition and expanded PNG/GIF/MP4/OBJ/3mdb fixtures under `Examples/Compositions`, without changing the original gallery manifest.

COMPOSITION-40 adds source boundary checks for exactly the two current entitlements, the single `rook.appearance` defaults key and the absence of file watcher and bookmark APIs in product sources. RookTool names a linked root and says it needs its project folder instead of reporting a generic decode failure; `sculpture portable inspect` reads a self-contained bundle as a composition.

GALLERY-41 adds `RookTool math-ladder`, which takes no arguments and writes only `Examples/Math`: readable 3md and a PNG preview for the 16, 32, 64 and 128 cell math models, a PNG preview of the 256 cell model and a `sculpt-math-ladder-1` manifest written last. Each manifest record lists the ladder entry's id, title, kind, extent, formula, occupied cells, PNG preview settings, the committed files' byte counts and the explicit write command. `RookTool examples` also writes this folder after Blockhaven; `math-ladder` does not read or write the other example folders. `RookTool sculpture math ENTRY_ID NEW.3md|NEW.3mdb` generates any of the five ladder models through the gallery catalog and publishes it as a new file, readable 3md or compact storage by extension. It refuses an unknown entry, a missing output directory and an existing output or symbolic link before generating, reports progress in tenths on standard error, requires the encoded document to reopen to the generated scene, and publishes through the existing exclusive new-file contract, returning a JSON receipt. The 256 cell model is not committed as a file.

GALLERY-32 adds original Blockhaven content through `RookTool blockhaven`, which takes no arguments and generates only `Examples/Blockhaven`. The existing `examples` route also generates this separate set after the original gallery and courtyard. A 37-definition composition holds thirty-six 32 × 64 × 32 chunks and one root map; the matching sparse world contains thirty-six exact chunk anchors. Explicit expansion is 192 × 64 × 192. Its own manifest and seven artifacts do not change `Examples/manifest.json` or the original twenty-one-example, 105-artifact catalog. These are Sculpt.3md composition, world and voxel files, without a Minecraft runtime or native Minecraft-format contract.

### Exported Symbols

Sparse-world inspection implements WORLD-31. `sculpture inspect WORLD.3md` reports mode `sparse-world`, model/instance counts and exact coordinates as signed Int64 decimal strings so clients with binary64 JSON numbers can preserve them. `sculpture model WORLD.3md MODEL_ID NEW.3md|3mdb` resolves one explicitly named bounded definition and publishes it without replacing existing files. Whole sparse-world flattening or ordinary voxel apply is refused with an extract-model-first explanation. Example generation adds `Examples/Compositions/wide-world.3md` with four shared-model placements including trillion-cell separation; it does not invent a whole-world bitmap, movie or mesh export.

| Symbol | Role |
| --- | --- |
| `ToolingCommand` | Typed repository commands. |
| `format` | Check formatting. |
| `intent` | Run pinned structural intent check. |
| `spec` | Run pinned specification check. |
| `boundaries` | Check all product sources and dependency paths. |
| `releaseFixture` | Scan release executable for fixture markers. |
| `package` | Build the Rook product in release configuration and package the optimized executable as a recognized app bundle. |
| `run` | Run a development command or app. |
| `build` | Build a product. |
| `ToolingError` | Typed development failures. |
| `unexpectedArguments` | Unsupported invocation. |
| `missingFile` | Required file absent. |
| `versionMismatch` | Pinned version refusal. |
| `forbiddenSource` | Product capability boundary violation. |
| `toolingDependency` | Development target reachable from product graph. |
| `invalidPackageDescription` | Malformed manifest description. |
| `invalidFileInventory` | Invalid inventory input. |
| `nonSwiftProgram` | Repository-owned Python or shell program refused. |
| `releaseMarker` | Development fixture in release refused. |
| `unsafeBundle` | Unrecognized or symlink bundle replacement refused. |
| `invalidEntitlements` | Entitlements file is not a property list dictionary. |
| `unexpectedEntitlement` | Entitlement key outside the app sandbox and user-selected read-write pair refused. |
| `requiredEntitlement` | Required entitlement missing or not Boolean true. |
| `storedDefaultsKey` | Stored defaults key other than `rook.appearance` in a product source refused. |
| `description` | Development failure explanation. |
| `RookTooling` | Native repository operation dispatcher. |
| `SwiftTestLog` | Pure test log assessment. |
| `maximumLogBytes` | Maximum accepted raw log bytes. |
| `assess` | Compute evidence from real status and bounded log. |
| `TestLogFailure` | Recorded test issue location. |
| `line` | One-based log line. |
| `text` | Retained diagnostic text from tests. |
| `TestRunSummary` | Positive final Swift Testing summary. |
| `tests` | Completed count. |
| `suites` | Optional suite count. |
| `durationSeconds` | Reported duration. |
| `TestLogIssue` | Verification refusal. |
| `upstreamFailure` | Nonzero child status. |
| `recordedFailures` | Failure lines detected. |
| `missingSummary` | Final Swift Testing summary absent. |
| `incompleteRun` | Later unfinished run. |
| `zeroTests` | Empty verification refused. |
| `unexpectedCount` | Exact expected count differs. |
| `invalidExpectedCount` | Nonpositive expectation refused. |
| `message` | Refusal explanation. |
| `TestLogAssessment` | Immutable evidence, never independent human review. |
| `upstreamExitCode` | Actual child status. |
| `expectedTests` | Optional caller expectation. |
| `issues` | All refusal reasons. |
| `failureLines` | Recorded failures. |
| `successfulSummaries` | All observed valid summaries. |
| `passed` | Derived acceptance. |
| `reasons` | Readable assessment issues. |
| `init` | Decode or construct typed contracts. |
| `encode` | Encode structured evidence. |
| `SwiftTestRunResult` | Retained log and receipt for owned process. |
| `executable` | Executed program. |
| `arguments` | Actual argument array, no shell interpolation. |
| `workingDirectory` | Child working directory. |
| `logPath` | Raw retained output. |
| `receiptPath` | Structured assessment path. |
| `terminationSignal` | Observed signal. |
| `assessment` | Evidence interpretation. |
| `exitCode` | Preserve child failure or reject false success. |
| `SwiftTestRunnerError` | Evidence retention failure. |
| `retainedEvidenceExists` | Refuse overwriting prior receipts. |
| `oversizedLog` | Bound exceeded. |
| `invalidLogEncoding` | Cannot interpret output. |
| `cannotCreateLog` | Cannot retain evidence. |
| `SwiftTestRunner` | Own, await, and assess child execution. |

`SculptureExampleExport` is internal to RookTool. It is not a product export. `generate(in:)` writes `Examples/<id>.3md`, `.png`, `.gif`, `.mp4`, and `.obj` for every one of twenty-one `SculptureExamples.all` entries, then `Examples/manifest.json`: 105 artifacts plus the manifest. The manifest schema is `sculpt-examples-1`, with columns 64, rows 36, pixel width 576, pixel height 648, duration 4 seconds, and 10 frames per second. Each example record contains `renderStyle`, `ascii` for the original twelve or `cubes` for the eight 64-cubed scenes and 256-cubed solar system. Prior records missing style are read as ASCII. Matching cached fixture sets are reused rather than re-encoded. The RookTool command is `examples` and it accepts no arguments. A symlink at `Examples`, at a target file, or at `Examples/manifest.json` is refused.

## Invariants

The `sculpture` CLI route runs before the development-tool version probes. `sculpture inspect INPUT` returns a JSON inspection of readable `.3md` or native compact `.3mdb`, detected by content through `SculptureDocumentCodec`. `sculpture apply INPUT COMMANDS.json OUTPUT` validates a version-1 command batch, applies it to a copy, and atomically publishes a new sculpture file. The output extension selects readable `.3md` or compact `.3mdb`, case-insensitively; an unsupported or absent extension is refused before publication. Both inputs must be regular files. A sculpture input is bounded at `SculptureDocumentCodec.maximumBytes`, 20_971_520 bytes (20 MiB). Readable decoding also rejects more than 100,000 physical lines before ThreeMD parsing; compact decoding validates its bounded stream, complete lengths, and checksum. Command JSON remains bounded at 262_144 bytes (256 KiB). Existing outputs and dangling output symlinks are refused. Publication uses an exclusive hard link in the pinned destination directory and fails safely on filesystems that do not support it. Explicit directory aliases are permitted; the destination entry itself is never followed or replaced. This development command does not control the running app, start a subprocess, or change product entitlements.

1. RookApp, RookCore, RookSculpture, and RookRendering cannot transitively depend on these development targets. RookCore's dependency set is empty. RookSculpture does not depend on RookApp, RookCore, or RookRendering. RookRendering depends on RookSculpture and does not depend on RookApp or RookCore. RookApp depends on RookCore, RookSculpture, and RookRendering. RookTool depends on RookTooling, RookVerification, RookSculpture, and RookRendering. An external product such as ThreeMD is allowed. The product targets do not import the development targets, start a process, or open a network connection.
2. Product source scans reject network and process capability tokens in every product target. RookCore also rejects NSPasteboard, NSWorkspace, and imports of the app or sculpture modules. RookSculpture rejects imports of RookApp, RookCore, and RookRendering. RookRendering rejects imports of RookApp and RookCore. Tooling can launch pinned processes using argument arrays. Packaging first invokes `swift build --product Rook --configuration release`, stops on a failed build, and copies `.build/release/Rook` plus Info.plist into a bundle with no Resources payload. It never falls back to an older debug executable. Ad-hoc signing, strict signature verification, entitlement display, owned-bundle validation, symbolic-link refusal, and staged replacement remain required before publishing the local bundle. The development run command does not pass `--open-launcher`.
3. Guarded test commands require a positive final Swift Testing summary, zero upstream status, and no failure or unfinished later run. XCTest's zero-test pass alone is rejected.
4. Raw logs and receipts are retained without replacing previous evidence. Repository-owned `.py`, `.sh`, and `.metal` files are refused.
5. `examples` generates five formats for all twenty-one gallery ids and does not take arguments. Original examples use ASCII PNG/GIF/MP4; eight 64-cubed scenes and the 256-cubed solar system use Cubes at default opacity 0.35. GIF and MP4 use `SculptureTurntableConfiguration.standard`: four seconds, ten frames per second, and 576 by 648 pixels. OBJ uses `SculptureOBJExporter.data(for:)`. The preview camera yaw is -0.6 and pitch is 0.7 for Maps, Worlds, or Space and 0.35 otherwise. Space uses zoom 0.9 to frame the comet tail; other cube fixtures use 1.05 and ASCII fixtures use 1.3. The published outputs stay under `Examples/` in the working directory, with temporary encoding staging owned by the generator. A symlink at `Examples`, at a target file, or at `manifest.json` is refused.
6. A cached set is reused only when previous manifest columns 64, rows 36, duration 4, and frame rate 10 match; its render style and occupied count match the example; canonical 3md bytes match; and its five files are regular, nonsymlink files with the recorded byte sizes. The original twelve therefore retain their existing ASCII artifacts when unchanged. This is canonical document and file-metadata validation, not a cryptographic content check of all five formats. The rewritten manifest includes a style field for reused records.
7. Blockhaven has a separate `sculpt-blockhaven-example-1` manifest under `Examples/Blockhaven`. Its seven artifacts are `blockhaven.3md` (reusable composition), `blockhaven-world.3md` (sparse placements), `blockhaven.3mdb` (detached expanded voxels), and `blockhaven.png`, `.gif`, `.mp4`, and `.obj`. PNG is 1152 by 1296 pixels; GIF and MP4 are 576 by 648 pixels, four seconds, ten frames per second and forty frames. Images and animations use cubes, opacity 0.8, and camera yaw -0.6, pitch 0.75, zoom 0.9. The manifest records dimensions, model and instance counts, occupancy, rendering configuration, and the seven file byte sizes. The generator completes encoding in its owned temporary directory, checks cancellation, then preflights every destination and publishes individual files atomically with the manifest last. It refuses directory or target-file symlinks and nonregular file destinations, and cleans up staging on cancellation or failure. This is per-file publication; it does not promise a transactional directory replacement. A cache hit requires matching configuration and document facts, canonical composition/world/compact bytes, and all seven regular nonsymlink files at their recorded sizes; it is not a content hash of the image, animation, or OBJ outputs. The standalone route leaves gallery and courtyard outputs untouched.

## Behavioral Examples

- A test process exits zero after reporting a failure: the guarded command exits nonzero.
- A product target imports RookTooling, RookCore reaches an AppKit pasteboard or workspace bridge, RookRendering imports RookApp, or a `.metal` path is in the inventory: the boundary command refuses the source, the graph, or the inventory.
- `examples` with an extra argument is refused. A successful run produces five files for each of twenty-one ids and a `sculpt-examples-1` manifest. The app target does not call that command.
- A matching original ASCII record is kept without regenerating its image or animation; a new 64-cubed example is encoded as cubes and recorded with `renderStyle: cubes`.
- An accepted 256-cubed 3md file can be inspected within the 20 MiB limit, while command JSON beyond 256 KiB is still refused.
- Compact and readable inputs produce the same inspection. An apply output ending in .3MDB is compact; .3MD is readable. Another extension fails without creating output, and existing destinations remain unchanged in either format.
- Packaging with distinct release and debug inputs copies the release bytes. A failed release build leaves an existing bundle unchanged and never invokes signing; a missing release executable is refused even when a debug executable exists.
- `blockhaven` with no arguments generates the reusable chunk map, sparse world, detached compact voxels and four expanded export formats under `Examples/Blockhaven`; an extra argument is refused. Opening the composition or world preserves references, while opening the compact expansion edits a separate voxel copy. Matching unchanged outputs are reused; an unsafe destination is refused. Content verification is recorded separately from this specification.

## Error Cases

Tool pin mismatches, incomplete test runs, unsafe bundle replacement, unsupported arguments, and missing evidence cause explicit failure rather than inferred success.

## Dependencies

RookTooling and RookVerification use Foundation and development tool binaries. RookTool also links RookSculpture and RookRendering so `examples` can render fixtures in process. The product does not embed Fledge, hi, SpecSync, Python, shell scripts, or a hosted model, and it does not link these development targets.

## Change Log

- Version 14: portable scene inspection/export and exact-revision shared-model edits for EXPORT-35. New verification is separate from historical CLI and lifecycle evidence.

- Shared-model preparation: explicit-file reference inspection/editing with exact preconditions and preserved graph/schema rules for COMPOSITION-34. Verification is separate from historical CLI receipts.

- Version 1: document the existing native development contracts and extend guards to all product modules. No lifecycle completion or independent human review is claimed.
- Version 3: limit the product scan to RookApp and RookCore, package a resource-free bundle, and stop passing `--open-launcher`. No review or finalization is claimed.
| 2026-10-03 | unify-searchable-home-with-everyday-applets-native-design-intake-and-typed-local-sentence-playground: Unify searchable home with everyday applets, native design intake, and typed local sentence playground |
- Version 4: scan RookSculpture and RookRendering, keep the network and process tokens, and refuse an authored `.metal` file. No review or finalization is claimed.
- Version 5: RookTool `examples` writes five formats for all twelve gallery sculptures. `SculptureExampleExport` stays internal. No review or finalization is claimed. Codex's later verify lane is recorded in `docs/evidence/sculpture-enhancements/verification-notes.md`. grok-build did not run it.
- Correction, same version: `examples` also refuses a symlink at `manifest.json`. No review or finalization is claimed.
- Version 6: JSON sculpture inspection and atomic structured batches to new files, with bounded regular input files and machine-readable results. No lifecycle approval or independent review is claimed.
- Version 7: twenty-example five-format generation with explicit render-style records and reuse of unchanged fixtures, detailed cube fixture cameras, and separate 1 MiB sculpture and 256 KiB command-JSON bounds. No lifecycle approval or independent review is claimed.
- Version 8: twenty-one examples and 105 artifacts, including the 256-cubed Space scene with its higher fixture viewpoint; sculpture input bounds are 20 MiB and command JSON remains 256 KiB. Earlier artifacts and verification remain historical. No lifecycle approval or independent review is claimed.
- Correction, same version: Space fixtures use zoom 0.9 to retain the comet tail; other cube and ASCII fixtures keep their prior framing. Sculpture input decoding also applies the private 100,000-physical-line preparse cap. New verification remains pending separately.
- Version 9: CLI inspection detects readable and native compact sculpture contents; apply selects .3md or .3mdb from a case-insensitive output extension while preserving bounded inputs and atomic refusal of existing destinations. The five-format readable gallery remains unchanged. Compact verification is pending separately; no lifecycle approval, review, or finalization is claimed.
- Version 10: package builds and copies the optimized release executable, with no debug fallback, while preserving signing and staged owned-bundle replacement. Packaging and live-rendering verification are recorded in `docs/evidence/camera-performance/`; no lifecycle approval, review, or finalization is claimed.
- Version 12: document the standalone Blockhaven generator and its separate seven-artifact manifest, reusable chunk sources, expanded exports, staging and cache protections for GALLERY-32. The original twenty-one-entry gallery and historical verification remain unchanged. New content verification is pending separately; no lifecycle approval, independent review, or finalization is claimed.
| 2026-10-05 | edit-shared-sculpture-models-in-place-with-transactional-undo-and-unique-world-placements: Edit shared sculpture models in place with transactional undo and unique world placements |
| 2026-10-05 | adopt-threemd-2-portable-scene-interchange-and-transactional-shared-model-editing-in-sculpt: Adopt ThreeMD 2 portable scene interchange and transactional shared model editing in Sculpt |
| 2026-10-05 | measure-a-real-1024-cubed-dense-volume-and-reusable-sparse-worlds-without-raising-production-editing-limits: Measure a real 1024 cubed dense volume and reusable sparse worlds without raising production editing limits |
| 2026-10-06 | make-3md-file-and-folder-insertion-discoverable-and-reliable-for-people-and-explicit-file-agent-tools: Make 3md file and folder insertion discoverable and reliable for people and explicit-file agent tools |
| 2026-10-07 | open-and-resolve-linked-3md-compositions-from-a-chosen-project-folder-and-import-self-contained-bundles: Open and resolve linked 3md compositions from a chosen project folder and import self-contained bundles |
| 2026-10-07 | show-every-example-in-one-gallery-and-add-a-math-generated-size-ladder-from-16-to-10-240-cells: Show every example in one gallery and add a math-generated size ladder from 16 to 10,240 cells |
| 2026-10-07 | drop-math-ladder-worlds-1024-and-10240: Drop the 1,024-wide and 10,240-wide math-ladder worlds; the ladder is five voxel models |
