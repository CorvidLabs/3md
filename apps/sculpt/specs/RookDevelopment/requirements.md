---
spec: RookDevelopment.spec.md
---

# Requirements

### REQ-RookDevelopment-011

For GALLERY-32, `RookTool blockhaven` SHALL take no arguments and SHALL generate only the original landscape's separate `Examples/Blockhaven` set. The existing `examples` route SHALL also produce this set without changing its twenty-one gallery entries or original manifest schema. Output SHALL include `blockhaven.3md` with reusable composition references, `blockhaven-world.3md` with exact sparse chunk placements, detached expanded `blockhaven.3mdb`, PNG, GIF, MP4 and OBJ, plus a `sculpt-blockhaven-example-1` manifest. PNG SHALL be 1152 × 1296; cube animations SHALL be 576 × 648, four seconds, ten frames per second and forty frames. Cube rendering SHALL use opacity 0.8 and camera yaw -0.6, pitch 0.75, zoom 0.9. The manifest SHALL record document dimensions, model/instance counts, occupancy, render configuration and file byte sizes. Encoding SHALL complete in an owned temporary directory before destination preflight and per-file atomic publication, with the manifest last; staging SHALL be cleaned up after cancellation or failure. Symlink directories, symlink targets and nonregular file destinations SHALL be refused. Cache reuse SHALL require canonical composition/world/compact bytes, matching configuration and document facts, and the complete regular-file set at recorded sizes. Image, animation and mesh caching SHALL NOT claim cryptographic content validation. No Minecraft runtime, assets or native Minecraft file-format interoperability is required.

Acceptance Criteria

- The seven named artifacts and independent manifest can be generated without rewriting the original gallery or courtyard by using the standalone route. Reference sources round-trip with their shared chunk definitions and exact positions; the compact copy has the same expanded cells. The PNG and forty-frame animations use the declared dimensions and style, and OBJ remains within its existing exposed-face budget.
- A repeated matching run retains unchanged outputs. Invalid arguments and unsafe destination entries are refused; cancellation or encoding failure cleans up staging without publishing incomplete encoded payloads. Completed individual files may remain after a later publication failure, and that behavior SHALL NOT be described as whole-set atomicity. New runtime and visual verification remain separate evidence.

### REQ-RookDevelopment-010

For WORLD-31, sparse-world inspection SHALL distinguish the reference document and encode exact Int64 coordinates as decimal strings. An explicit model extraction command SHALL resolve only the requested bounded library definition and atomically publish a new readable or compact voxel file. Missing models, wrong document types, existing outputs and invalid formats SHALL publish nothing. Whole-world expansion and ordinary voxel apply SHALL require extraction rather than silently losing positions/references. Sparse example generation SHALL preserve distant placements in self-contained source without allocating their intervening space.

Acceptance Criteria

- Inspection preserves positions beyond binary64 integer precision, explicit extraction round-trips the selected model, and the original world bytes remain unchanged. Missing/model/type/no-clobber failures leave the output absent.

### REQ-RookDevelopment-009

For COMPOSITION-30, explicit `sculpture compose` and `expand` commands SHALL validate bounded regular inputs and publish a new output atomically without clobbering existing files or symlinks. A strict version-1 manifest SHALL name the model files; imported references SHALL be embedded and remapped, not retained as paths. Inspection SHALL distinguish compositions; regular command apply SHALL require an explicit voxel expansion first. Malformed graph/manifest/input or expansion failure SHALL leave output absent. The existing examples command SHALL generate the courtyard's reusable source and five expanded formats separately from the original gallery manifest.

Acceptance Criteria

- CLI compose/inspect/expand retain shared bindings and exact resolved cells. Unknown manifest fields/versions, missing models, invalid bounds and an existing output fail without publication. Runtime target boundaries remain unchanged.

### REQ-RookDevelopment-001

The guarded complete Swift test command SHALL run native suites sequentially and SHALL require actual upstream success plus a positive completed summary with no issues. Product targets SHALL be RookApp, RookCore, RookSculpture, and RookRendering. All four SHALL exclude development targets and network or process sources. RookCore SHALL also exclude AppKit pasteboard and workspace bridges and SHALL have no package dependencies. RookSculpture SHALL NOT depend on the app, core, or rendering targets. RookRendering SHALL depend on RookSculpture and SHALL NOT depend on the app or core. Repository inventory SHALL refuse `.py`, `.sh`, and `.metal` files outside dependency checkouts. Packaging SHALL build Rook with `--configuration release` and SHALL copy `.build/release/Rook` with no debug fallback, implementing RENDER-29. A failed release build or missing release executable SHALL leave an existing bundle unchanged. Packaging SHALL retain ad-hoc signing, strict verification, entitlement display, owned-bundle validation, symbolic-link refusal, and staged replacement; it SHALL copy no resource payload. The development run command SHALL NOT pass `--open-launcher`.

Acceptance Criteria

- Swift-only inventory, source, and graph guards cover all four product targets. The previous network and process tokens still fail the scan. Premature-exit probes remain enforced. The normal guarded command accepts no filter or status override. The product app includes no development runtime. The packaged bundle has no Resources payload.
- A packaging invocation builds release and copies its bytes when a distinct debug executable also exists. A failed release build preserves the prior bundle without signing; missing release input is refused rather than substituted from debug. Signing failure still preserves the prior bundle and removes staging.

### REQ-RookDevelopment-002

The RookTool command `examples` SHALL take no arguments. It SHALL produce `Examples/<id>.3md`, `.png`, `.gif`, `.mp4`, and `.obj` for each of twenty-one `SculptureExamples.all` ids, then `Examples/manifest.json` with schema `sculpt-examples-1`, columns 64, rows 36, pixel width 576, pixel height 648, duration 4 seconds, and 10 frames per second. Original examples SHALL use ASCII images and animations; the eight 64-cubed examples and the native 256-cubed Grand solar system SHALL use cubes at default opacity 0.35. Each record SHALL include `renderStyle`, `ascii` or `cubes`. Generation SHALL reuse cached formats only when configuration, style, occupancy, canonical 3md, and recorded regular-file sizes match, preserving unchanged original artifacts. Cameras SHALL use yaw -0.6, pitch 0.7 for Maps, Worlds, or Space and 0.35 otherwise, and zoom 0.9 for Space, 1.05 for other cubes, or 1.3 for ASCII. It SHALL refuse a symlink at `Examples`, at a target file, or at `Examples/manifest.json`. The app target SHALL NOT import or launch this command. RookTool MAY depend on RookSculpture and RookRendering for this fixture generation.

Acceptance Criteria

- The twenty-one ids and five extensions form 105 artifacts. The manifest records format sizes and style. Matching earlier sets remain unchanged; the solar-system cube set renders at 576 by 648 pixels with standard four-second animation. Product targets still exclude the development targets, network clients, and process launches. This requirement does not claim a completed test run.

### REQ-RookDevelopment-003

The development CLI SHALL inspect an explicitly chosen readable `.3md` or native compact `.3mdb` sculpture as JSON and SHALL apply a versioned batch of structured document edits to a new output file, implementing EXPORT-28. Input formats SHALL be detected by content through `SculptureDocumentCodec`. Apply output SHALL select readable or compact storage from a case-insensitive `.3md` or `.3mdb` extension; unsupported or absent extensions SHALL be refused without creating output. Input files SHALL be regular files. Sculpture files in either format SHALL be bounded at 20_971_520 bytes (20 MiB), and command JSON SHALL remain bounded at 262_144 bytes (256 KiB). A rejected command, compact validation error, or encoding error SHALL leave the input unchanged and create no output. Publication SHALL be atomic and SHALL refuse existing files, directories, and output symlinks. The route SHALL run without development-tool subprocess probes and SHALL NOT control the running app or add a product entitlement.

Acceptance Criteria

- Inspect reports dimensions through 256 cells per axis, title, occupancy, palette, and zero-based axes equally for readable and compact contents. Successful apply emits the selected format and JSON metadata. Invalid batches, malformed compact streams/checksums, unsupported output extensions, command JSON beyond 256 KiB, sculpture data beyond 20 MiB, and existing destinations preserve all input and destination bytes.

### REQ-RookDevelopment-012

For COMPOSITION-34, explicit-file reference-edit tooling SHALL use the same pure validated model replacement and unique-instance operations as the native app, read only supplied files, reject stale source preconditions and publish a new output atomically without replacing an existing file.

Acceptance Criteria
- CLI operations preserve composition/world references and unrelated definitions.
- Failed, stale or canceled operations create no output.
- The app gains no process, service, network or additional entitlement and retains ThreeMD1.8.1 until a separately verified upstream release is available.

### REQ-RookDevelopment-013

For EXPORT-35, explicit-file development commands SHALL inspect portable and legacy scenes and export or apply validated upstream-backed shared edits to a new selected output, with bounded structured diagnostics and exact revision guards.

Acceptance Criteria
- Content detection and format selection are explicit and do not silently replace existing destinations.
- Machines receive scene kind, revision and bounded diagnostic code/path data from the same core value rules as native UI.
- Meaningful semantic/tool/native tests, current hi/contracts and the full pinned Swift lane record actual verification.
- Product targets do not import development tooling or start a process or network connection.

### REQ-RookDevelopment-014

For WORLD-36, an explicit opt-in development study SHALL physically initialize, hash and stream-compress a literal 1024-cubed one-byte volume, fully decode and verify all bytes, guard available memory, report wall time and process memory observations, and label its experimental raw payload separately from supported ThreeMD formats. Small ordinary tests SHALL cover correctness and refusal paths. Opt-in release Metal measurements SHALL record actual visible, detailed, proxy, omitted and culled counts, camera submission time, synchronized offscreen frame time and geometry reuse without asserting on-screen FPS.

Acceptance Criteria
- Dense phases touch and verify exactly1,073,741,824 bytes with bounded streaming scratch, a full original/decoded checksum and explicit host/memory facts.
- Missing opt-in, insufficient memory, unsafe output, corruption, truncation and cancellation fail without a complete receipt or replacement of existing output.
- Ordinary CI tests remain small; the explicit release study records real measurements and qualifying render counts.
- Production editing/format/render limits, runtime target boundaries and historical evidence remain unchanged.

### REQ-RookDevelopment-015

`RookTool sculpture portable insert INPUT REQUEST.json OUTPUT.3md|OUTPUT.3mdb` and `RookTool sculpture reference insert INPUT REQUEST.json NEW.3md` SHALL insert explicitly listed supported files into the input composition or world using the app's insertion rules. Requests SHALL be strict and bounded, name files relative to the request, choose a cell or exact Int64 focus, require explicit permission to replace occupied cells and check the exact expected scene revision where the portable path applies. Refusals SHALL name the file and reason, and output SHALL be published only as a new file. The tool SHALL NOT control the running app.

Acceptance Criteria
- Inserting files into a composition and a world writes a new file that reopens with the placements.
- Occupied targets, world or generic Markdown children, stale revisions and existing outputs are refused without writing.

### REQ-RookDevelopment-016

Source boundary checks SHALL require that `App/Rook.entitlements` holds exactly the app sandbox and user-selected read-write keys, that product sources use no stored defaults key other than `rook.appearance`, and that product sources contain no file watcher or security-scoped bookmark APIs. RookTool SHALL report that a linked composition needs its project folder instead of a generic decode failure, and SHALL inspect a self-contained bundle through the shared codec.

Acceptance Criteria
- Boundary tests fail on an added entitlement, an extra defaults key, a watcher token and a bookmark API, and pass on the current sources.
- RookTool tests cover a linked root and a bundle.

### REQ-RookDevelopment-017

`RookTool examples` SHALL also write the math ladder to `Examples/Math/`: a readable `.3md` and a PNG preview for each model from 16 to 128 cells, a PNG preview of the 256-cell model, and a manifest with each entry's kind, extent, formula, occupied cells and byte counts. The 256-cell model SHALL NOT be committed as a `.3md`, to keep the repository small; an explicit RookTool command SHALL write any ladder model to a new output file chosen by the caller. Existing gallery artifacts SHALL be unchanged.

Acceptance Criteria
- Tool tests check the manifest, the committed files and writing a model entry to a new output that reopens.
- The existing gallery manifest and artifacts are unchanged.

