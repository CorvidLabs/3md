---
spec: RookSculpture.spec.md
---

# Requirements

### REQ-RookSculpture-011

For WORLD-33, `occupiedCount(inLayer:)` SHALL return the existing cached count for a valid slice and zero for an invalid index, without scanning cells. Paint, layer insertion/removal/duplication and rotation SHALL keep this count consistent with the immutable layer bytes and total occupancy. This cache SHALL NOT change file schemas or document equality.

Acceptance Criteria

- Cached counts equal actual nonempty bytes after each supported edit and remain independent between copied documents; negative and past-end indices return zero.

### REQ-RookSculpture-010

For GALLERY-32, `SculptureBlockWorldExamples` SHALL create a deterministic original Blockhaven landscape as both a self-contained `SculptureComposition` and a `SculptureWorld` using the existing model and reference schemas. Thirty-six 32 × 64 × 32 chunks plus their root map SHALL form thirty-seven model definitions. A six-by-one-by-six root tile arrangement SHALL explicitly expand to 192 × 64 × 192 voxel cells. Chunks SHALL be partitioned from one global landscape to preserve cross-boundary terrain continuity. The composition SHALL retain its reusable chunk definitions; thirty-six sparse-world instances SHALL reference them without rotation at exact `(xChunk × 32, 0, zChunk × 32)` anchors. Explicit voxel expansion SHALL produce a detached editable copy rather than replace the reference source. Generated content SHALL use the existing glyph palette and SHALL remain within composition, world, renderer, and export budgets. The twenty-one voxel catalog entries SHALL remain unchanged. No Minecraft runtime, assets, or native Minecraft file-format interoperability is specified.

Acceptance Criteria

- Repeated construction yields equal reference graphs and placements. Composition save/reopen preserves its chunk bindings and explicit expansion retains the expected dimensions and cells. The world preserves exact chunk coordinates and model identities without allocating intervening empty space. The source includes distinct readable terrain and structures, while all content remains editable through the existing Sculpt.3md paths. Completed visual and test evidence is recorded separately.

### REQ-RookSculpture-009

For WORLD-31, SculptureWorld SHALL retain one validated SculptureComposition library and an ordered list of at most 65,536 uniquely named model instances. Its spatial extent SHALL NOT have a fixed cube boundary. Construction, serialization and reopening SHALL NOT allocate voxel cells between placements or expand the library. Each instance SHALL reference an existing model and preserve an exact Int64 X/Y/Z anchor and clockwise X/Y rotation around Z in 0...3. Each anchor component SHALL be at most Int64.max minus 256, reserving headroom for nonnegative local coordinates of any bounded model; negative anchors through Int64.min SHALL be accepted. Instance and model IDs SHALL use 1...48 case-sensitive ASCII letters, digits, underscores or hyphens, starting with a letter or digit. Duplicate instance IDs, unknown models, unsafe origins, invalid titles/IDs/rotations and excess capacity SHALL fail without a world result.

The library SHALL retain the composition's validation and work bounds: at most 64 models, 16 model nodes on a dependency path, 64 MiB summed unique resolved voxel volumes and 65,536 nested placement occurrences summed across unique models. All definitions and bindings SHALL remain validated, including unused entries. Individual voxel models and explicit expanded composition axes SHALL remain within 256 cells. expanded(modelID:) SHALL resolve only the selected model and its dependencies, caching shared children within that call and refusing an unknown model. World construction SHALL NOT invoke dense expansion. Renderer focus, distance culling and detail levels SHALL NOT modify persisted placements or imply that hidden instances were removed.

SculptureWorldCodec SHALL write and read app-specific ascii-world-1 ThreeMD version 1.0 on axis space. Metadata SHALL contain only scene-schema; there SHALL be no preamble. Exactly one Z-zero plane labeled World SHALL contain a fenced JSON envelope with exactly version 1, library and instances. The library SHALL be one embedded complete composition document. Each instance record SHALL contain exactly id, modelID, x, y, z and quarterTurns, with coordinates decoded directly as Int64 integers. Decode SHALL reject unknown/missing/duplicate JSON and frontmatter/directive fields, unsupported versions/planes/fences, invalid libraries and noninteger/overflowing coordinates. Files SHALL be at most 20_971_520 bytes, with a preparse cap of 100,000 physical lines and one plane plus bounded JSON depth/value allocations. Neither codec SHALL read an external file path or URL. Cancellation SHALL throw without complete output. Existing voxel codecs and the twenty-one-item voxel catalog SHALL remain unchanged.

Acceptance Criteria

- Two placements at plus/minus 1_000_000_000_000_000 remain two shared model references, serialize in less than 100,000 bytes for the small fixture, and reopen without allocating intervening space. Neighboring coordinates above 2^53 and adjacent accepted Int64 extreme anchors round-trip exactly.
- Int64.max minus 256 is accepted on every axis; a greater anchor is rejected. Int64.min is accepted. Duplicate instance IDs, missing model IDs, invalid rotations and unsupported envelopes yield no world. Exact 65,536-instance capacity reopens; one additional instance fails construction.
- wideWorld() has four references to the same garden library model, including trillion-cell separation. Composition and world examples remain separate from SculptureExamples.all. The final shared lane passed 252 tests in 15 suites; retained composition/world evidence is in docs/evidence/composition/. This is verification evidence, not lifecycle approval or independent human review.

### REQ-RookSculpture-008

For COMPOSITION-30, a SculptureComposition SHALL contain named voxel or tile models in one self-contained library, with a tile map as its root. Each nonempty tile character SHALL bind to one whole model with a clockwise X/Y quarter-turn rotation in 0...3. Bindings SHALL use unique printable ASCII bytes other than a period. A period SHALL reserve an empty block. Tile dimensions SHALL locate the model and leave padding empty. Odd rotations SHALL swap rectangular child X/Y dimensions; every rotated child SHALL fit its reserved block without clipping or overlap. Missing/duplicate definitions, unbound characters, cycles, excessive depth/work and invalid dimensions SHALL fail. All nodes and bindings SHALL be validated, including unused definitions. Expanded axes SHALL remain within 256 cells. The library SHALL have at most 64 models including the root, 16 model nodes on a dependency path, 64 MiB summed unique resolved voxel volumes and 65,536 nested placement occurrences summed across unique models. Explicit expansion SHALL cache shared resolved models within that call. expanded() SHALL resolve the root, and expanded(modelID:) SHALL resolve the selected model and its dependencies or refuse an unknown ID. Cancellation SHALL throw without returning partial output.

The app-specific ascii-composition-1 ThreeMD version 1.0 schema SHALL store the root map plus a version 1 fenced JSON preamble library of named id/document records, once per non-root model. Nested tile definitions SHALL reference that same global library and SHALL NOT contain another preamble library. Metadata SHALL be exactly scene-schema, root-id, width, height, tile-width, tile-height, tile-depth and declared bind- keys. Printable identifiers SHALL follow the safe case-sensitive 1...48-byte grammar. Space and colon binding keys SHALL use canonical hex suffixes; aliases resolving to a duplicate glyph SHALL fail. Grids SHALL use fenced ASCII normally and fenced JSON row strings for fence-looking literal rows, preserving backticks, tildes and directive-looking characters. Decode SHALL NOT read external paths or URLs and SHALL reject unsupported/missing/duplicate metadata, plane attributes and JSON fields. The codec SHALL bound bytes to 20_971_520, aggregate root/embedded physical lines to 100,000 before ThreeMD parsing, planes to 256 per tile document and JSON nesting/value allocations before decoding. Existing readable/compact voxel schemas SHALL remain unchanged.

Acceptance Criteria

- Repeated and nested characters expand to the exact expected cells, dimensions and occupancy, and save/reopen preserves the graph. All four rectangular rotations work when the child fits its block; smaller children leave empty padding. Period blocks stay empty. Bad references/cycles in unused models, unsupported/duplicate fields, excessive dimensions/depth/volumes/placement work and cancellation yield no complete result. Literal backtick/tilde fences, @plane-looking rows, space and colon bindings survive canonical save/reopen. The courtyard example contains four definitions and expands to sixteen trees and sixteen gates.

### REQ-RookSculpture-001

A sculpture SHALL be a `Sendable` grid of 1...256 columns, 1...256 rows, and 1...256 layers, implementing CUBES-27. A cell SHALL be a period or one of `#@*+ox:=-`. Rows SHALL be Y, columns SHALL be X, and the layer index SHALL be Z. `orb()` SHALL be one deterministic hollow 16-cubed orb. `blank()` SHALL be one empty 16 by 16 layer titled `Untitled`. Quarter-turn rotation SHALL be clockwise and SHALL require a square layer. Adding a layer SHALL insert it after the chosen index. Removing the last layer SHALL fail. The title SHALL be 1...80 printable ASCII bytes. `occupiedCount` SHALL remain a cached count equal to the nonempty grid cells through construction, paint, erase, duplicate, remove, and rotation, without adding document metadata.

Acceptance Criteria

- Round-trip paint, duplicate, rotate, and layer limits stay inside the volume. Invalid glyphs and out-of-range cells do not change it. Four quarter turns restore a square layer.
- Empty-to-occupied and occupied-to-empty paint change occupancy by one; glyph substitution and rotation keep it unchanged. Duplicating and removing slices keep the cache equal to a direct grid count.
- Private row and slice caches stay aligned with the grids through those edits, allowing empty projection regions to be skipped without changing ASCII results.

### REQ-RookSculpture-002

`SculptureCodec` SHALL parse and serialize only an `ascii-sculpture-1` document on axis `space` through ThreeMD 1.8.1. The written 3md version marker SHALL be `1.0`. Metadata SHALL be exactly `scene-schema`, `width`, and `height`. Planes SHALL be contiguous integer Z positions starting at 0, each a fenced rectangular `ascii` grid. The camera SHALL NOT be stored. An unsupported schema or other Markdown document SHALL be rejected, not converted. Files larger than 20_971_520 bytes (20 MiB) SHALL be rejected. A private preparse limit SHALL reject more than 100,000 physical lines before ThreeMD parsing, bounding per-line allocations independently of the byte limit and without adding schema metadata.

Acceptance Criteria

- Encode then decode preserves the volume and title at the 256-cell bound and for existing smaller documents. A time-axis 3md document, a bad fence, a non-integer plane, a payload larger than 20_971_520 bytes, and a payload with more than 100,000 physical lines fail without a substitute sculpture.

### REQ-RookSculpture-003

`SculptureProjection.frame(_:camera:columns:rows:)` SHALL return a PNG-independent frame and SHALL default to 64 columns and 36 rows. Empty cells SHALL NOT invent palette characters. Occlusion SHALL keep the greater depth. `SculptureFrame.text` SHALL use spaces for empty pixels. Picking SHALL return the winning cell or nil outside the frame. Non-finite camera values SHALL be clamped to the finite defaults. The existing nonthrowing API SHALL check cancellation before work, per row, and before returning, and SHALL return a bounded all-nil frame when canceled rather than partial geometry.

Acceptance Criteria

- The blank frame is only spaces and newlines. A stacked column at yaw 0 and pitch 0 picks the higher Z. Orbit changes the frame.

### REQ-RookSculpture-004

`SculptureExamples.all` SHALL preserve the first twelve deterministic sculptures in this order: `character-orb` (`Character orb`), `woven-torus` (`Woven torus`), `moon-gate` (`Moon gate`), `spiral-tower` (`Spiral tower`), `crystal-garden` (`Crystal garden`), `little-rocket` (`Little rocket`), `pixel-bonsai` (`Pixel bonsai`), `orbital-rings` (`Orbital rings`), `hill-observatory` (`Hill observatory`), `terraced-island` (`Terraced island`), `canal-city` (`Canal city`), and `alpine-valley` (`Alpine valley`). `character-orb` SHALL be `Sculpture.orb()`. Each other volume among those original twelve SHALL be 24 by 24 by 24. The catalog SHALL append eight 64-cubed deterministic examples: `wandering-cartographer` (`Characters`), `clockwork-dragon`, `woodland-fox`, `deep-sea-whale` (`Creatures`), `citadel-of-arches` (`Architecture`), `sky-island-village`, `canyon-waterfall`, and `moonlit-harbor` (`Worlds`). `terraced-island`, `canal-city`, and `alpine-valley` SHALL use category `Maps`. The other nine original examples SHALL use category `Sculptures`. A map cell among the original 24-cubed examples at grid Y SHALL be sampled at Y + 6, inside that volume.

Acceptance Criteria

- All twenty-one ids are unique and stay inside the `ascii-sculpture-1` palette, period, dimensions, and title rules. `character-orb` is 16 cubed, an original map example is 24 cubed, the eight detailed character/world examples remain 64 cubed, and the final solar scene is 256 cubed.

### REQ-RookSculpture-005

`SculptureOBJExporter.data(for:)` SHALL return a UTF-8 OBJ mesh of the exposed faces of occupied cells. An occupied neighbor SHALL hide the shared face. The exporter SHALL count exterior faces before allocating mesh arrays and SHALL refuse more than `maximumFaces`, 250_000, with `SculptureOBJExportError.tooManyFaces`. The error SHALL explain the mesh limit and suggest reducing isolated cubes or using another visual export. The object name SHALL be `sculpture`. Each glyph SHALL be a group named `glyph_` plus its byte. Y SHALL point up, Z SHALL follow the slice index, and one cell SHALL be one unit centered on the volume. Cancellation SHALL throw and SHALL NOT return a mesh. The call SHALL NOT mutate the sculpture.

Acceptance Criteria

- An empty volume has no `g` line. One isolated occupied cell has six faces. A face toward an occupied neighbor is absent.
- A sparse document beyond the exterior-face budget is refused before a mesh is returned, and the sculpture remains unchanged. Documents below the budget remain exportable within the 256-cell bounds; expanding dimensions does not remove the face budget.

### REQ-RookSculpture-006

For GALLERY-26, `SculptureExamples.all` SHALL append `grand-solar-system`, title `Grand solar system`, category `Space`, as the final twenty-first entry. It SHALL be a deterministic 256-cubed editable volume with the Sun, all eight planets, Saturn rings, Earth and Jupiter moons, asteroids, a comet, and stars. Its sizes and distances SHALL be artistically compressed into the existing schema bounds. Prior example identities, dimensions, and order SHALL remain unchanged.

Acceptance Criteria

- The final entry has its declared ID, title, category, and 256-cell dimensions. Celestial features occupy valid palette cells, remain distinct and in bounds, and round-trip through 3md. Artistic scene scaling is stated in the gallery; it is not presented as measured astronomical spacing.

### REQ-RookSculpture-007

For EXPORT-28, `SculptureBinaryCodec` SHALL encode validated title and voxel bytes as a native version-1 `.3mdb` container, independently of readable ThreeMD. Its 60-byte little-endian header SHALL identify version 1, LZFSE compression 1, dimensions, title byte count, uncompressed voxel count, compressed stream byte count, and SHA256 of header bytes 0..<28, title, and uncompressed voxels. The reserved byte SHALL be zero. Title and glyph rules SHALL remain the sculpture's existing rules. Dimensions SHALL stay in 1...256, the decoded voxel count SHALL equal their product, and encoded inputs SHALL be bounded at 20_971_520 bytes. The complete LZFSE stream SHALL produce exactly that bounded count with no trailing input. Unknown versions/compression, malformed lengths, corrupt/truncated streams, invalid title/glyphs, and checksum mismatch SHALL fail without a partial sculpture. Cancellation SHALL throw and SHALL clean up initialized compression state. No camera or presentation state SHALL be stored. This is app-specific storage, not an upstream ThreeMD binary standard.

`SculptureStorageFormat` SHALL expose readable `.3md` and compact `.3mdb` choices. `SculptureDocumentCodec` SHALL detect compact storage by its complete eight-byte magic and otherwise validate readable 3md; writing SHALL take an explicit format. Readable output SHALL remain the existing `ascii-sculpture-1` schema. Apple Compression and CryptoKit SHALL be SDK dependencies with no added package, process, or network operation.

Acceptance Criteria

- Both formats round-trip exact title, dimensions, cells, and occupancy for small and 256-cubed documents. Content detection remains independent of a filename extension, and readable output remains consumable by the existing sculpture codec.
- Truncation, appended bytes, a corrupted checksum, unknown version/algorithm, invalid title/dimensions/glyphs, and mismatched or overflowing decoded lengths are refused. Canceling encode or decode returns no complete result and preserves the source model.

### REQ-RookSculpture-012

For COMPOSITION-34, shared voxel model replacement and unique sparse-world instance operations SHALL reconstruct and validate an immutable reference graph atomically, preserve all other references and coordinates, reject stale source snapshots and propagate cancellation without partial output.

Acceptance Criteria
- Replacing a shared voxel definition updates every referring placement including nested parents.
- Make Unique clones a voxel leaf and rebinds one selected world instance while other references retain the old model.
- Nested maps, fit failures, duplicate IDs, capacity failures and missing targets return explicit errors without mutation.
- Existing readable schemas and file round trips remain intact.

### REQ-RookSculpture-013

For EXPORT-35, explicit portable scene encoding and decoding SHALL use ThreeMD2 bounded document/composition storage and immutable identity/revision snapshots, preserve voxel values and shared graph bindings including unused definitions and exact Int64 world instances, and perform atomic stale-checked shared-model edits without partial output.

Acceptance Criteria
- Portable text and uncompressed binary round trips preserve complete scene semantics.
- Upstream graph/file budgets and malformed or inconsistent records fail explicitly without changing existing scene values.
- Legacy app-specific formats and defaults remain usable, including legacy capacity above portable graph limits.
- Snapshot editing preserves canonical revisions, detects stale parents and propagates cancellation.

### REQ-RookSculpture-014

For WORLD-36, deterministic study fixtures SHALL provide a reusable solid world whose 4096 unrotated 64-cubed placements fill coordinates 0 through 1023 on all axes, and a varied original landscape in a 1024-cubed address domain. Fact reports SHALL distinguish unique stored voxel bytes, repeated occupied cells, address extent and actual placements. Existing individual model bounds and world capacities SHALL remain unchanged.

Acceptance Criteria
- The solid world has exactly 1,073,741,824 repeated occupied cells with one uniquely stored solid64-cubed model and a valid library root.
- Landscape facts distinguish its address domain from actual occupancy and preserve reusable definitions.
- Fixtures are deterministic, cancellable and round-trip through supported native and portable formats without a dense world allocation.

### REQ-RookSculpture-042

Pure Swift insertion SHALL namespace imported model graphs, retain internal repeated references and portable identities/opaque attributes, validate the complete new scene, and return it without mutating the input. Composition batch placement SHALL use consecutive row-major cells and world placement SHALL use checked positive-X spacing. Unsupported child schemas and overflow SHALL refuse atomically.

Acceptance Criteria
- Nested and repeated bindings retain internal sharing and namespaced targets.
- Portable IDs and opaque attributes survive insertion and portable reopen.
- Fit, capacity and checked coordinate overflow refuse without partial output.

### REQ-RookSculpture-043

Insertion and native graph saves SHALL refuse a result whose native encoding would exceed the native decode budgets, so every accepted native save reopens. When neither the parent nor any input carries portable ThreeMD data and the portable limit refuses, insertion SHALL use native values with identical remapping, sharing and placement; otherwise it SHALL keep portable data and name the portable limit. Count, cell, glyph, model, fit and size checks SHALL run before decoding every input where possible. Preserved reference attributes SHALL match by glyph and target, and untitled nested definitions SHALL stay untitled.

Acceptance Criteria
- A near-limit native save round-trips, and an over-budget insertion is refused with no change.
- A 256-cubed input without portable data inserts natively; one with portable data is refused by name.
- Early checks refuse an oversized batch before decoding all files.

### REQ-RookSculpture-044

A linked composition SHALL be an app-specific readable ThreeMD document with scene-schema `ascii-linked-composition-1`: tile-map planes like `ascii-composition-1`, metadata exactly `scene-schema`, `width`, `height`, `tile-width`, `tile-height`, `tile-depth`, `3md-files` and an optional `sculpt-turns`, and no embedded library. Detection SHALL be by content within a bounded frontmatter scan, and a binary linked root SHALL be refused by name. The ledger value SHALL be built from a string dictionary by a JSON encoder as single-line JSON in a defined key order, never by string concatenation, and SHALL round-trip through `DocumentFileComposition.ledger(in:)`. Resolution SHALL read only files reachable from the root through a host-supplied reader. It SHALL refuse unsupported children (Sculpt compact storage, compressed binary, `ascii-composition-1`, `ascii-world-1`, composition profiles and bundles, generic Markdown, and non-linked files that carry a ledger), invalid or escaping paths, missing files, cycles, and the interim caps (a 1,024-byte normalized path, a 255-byte component, 64 reachable files, 512 ledger edges, depth 16, 16 MiB of definition bytes and a bounded raw ledger value), naming the failing project path. It SHALL then resolve exactly the reachable set with ThreeMD 2.0.0, map positional bundle IDs back to project paths in errors, publish nothing partial and honor cancellation between files. A self-contained bundle SHALL encode as readable text or uncompressed binary and SHALL decode without its source folder; its references SHALL be read by the entry schema, using `glyph` and `source-file` as an unordered set and ignoring other attributes, and `source-file` SHALL never be followed. Existing schemas, bytes, detection order and messages SHALL stay unchanged.

Acceptance Criteria
- Unit tests cover ledger building and round trip, resolve, a shared child, a missing file, a cycle, an invalid path, unsupported children, each cap at its limit, cancellation, and readable and binary bundle round trips.
- Legacy fixtures stay byte-identical, and existing portable fixtures and messages are unchanged.
- A bundle produced by ThreeMD resolution opens as a self-contained composition.

### REQ-RookSculpture-045

`SculptureMathExamples` SHALL generate deterministic models from formulas: a 16-cell sine ripple, a 32-cell torus, a 64-cell gyroid, a 128-cell sphere with harmonic bumps and a 256-cell layered sine terrain, each exactly that size on every axis. Generation SHALL check cancellation and SHALL NOT allocate a dense buffer larger than one 256-cell model. A gallery catalog SHALL list every built-in example (the existing voxel examples, the composition and world examples and the ladder) with its kind, category and extent without generating it, and SHALL create each entry on demand. Existing examples and their bytes SHALL be unchanged.

Acceptance Criteria
- Tests check each ladder model's exact size, determinism and occupancy; cancellation; and that listing the catalog generates nothing.
- Existing example fixtures stay byte-identical.

### REQ-RookSculpture-046

`Sources/CLzfse/shim.h` SHALL be listed in the RookSculpture spec. `specsync check` run from `apps/sculpt` SHALL report 94/94 implementation files. Compact `.3mdb` SHALL stay the app save and SHALL NOT be an upstream ThreeMD standard.

Acceptance Criteria
- The RookSculpture spec files list includes `Sources/CLzfse/shim.h`.
- `specsync check` from `apps/sculpt` reports 94/94 implementation files.


### REQ-RookSculpture-012

The session camera SHALL allow complete yaw and pitch turns and finite screen-space pan, with zoom bounded to 0.5...2. ASCII and cube cameras SHALL use the same normalized inputs. Nonfinite angles, zoom and pan SHALL become 0, 1 and 0 respectively; finite pan SHALL be bounded to one million cells in either direction. Drag orbit SHALL use 0.008 radians per point, pan SHALL use the inverse native 0.68 viewport scale, and invalid gesture inputs SHALL leave the camera unchanged. Camera state SHALL NOT be persisted in a sculpture.

Acceptance Criteria:

- Shared native/browser cases cover both poles, upside-down and translated views. Full turns restore the basis, inverse pan restores the origin, zoom clamps at both limits, and invalid inputs cannot corrupt the camera.
