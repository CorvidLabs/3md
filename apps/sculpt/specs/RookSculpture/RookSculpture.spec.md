---
module: RookSculpture
version: 22
status: active
files:
  - Sources/RookSculpture/SculptureVolumeStudyExamples.swift
  - Sources/RookSculpture/SculptureScene.swift
  - Sources/RookSculpture/SculptureThreeMDCodec.swift
  - Sources/RookSculpture/SculptureThreeMDEditing.swift
  - Sources/RookSculpture/SculptureSceneInsertion.swift
  - Sources/RookSculpture/SculptureInsertionPlan.swift
  - Sources/RookSculpture/SculptureSceneReader.swift
  - Sources/RookSculpture/SculptureModelEditing.swift
  - Sources/RookSculpture/Sculpture.swift
  - Sources/RookSculpture/SculptureCodec.swift
  - Sources/RookSculpture/SculptureBinaryCodec.swift
  - Sources/RookSculpture/SculptureSHA256.swift
  - Sources/CLzfse/shim.h
  - Sources/RookSculpture/SculptureStorageFormat.swift
  - Sources/RookSculpture/SculptureProjection.swift
  - Sources/RookSculpture/SculptureExamples.swift
  - Sources/RookSculpture/SculptureOBJExporter.swift
  - Sources/RookSculpture/SculptureCommand.swift
  - Sources/RookSculpture/SculptureComplexExamples.swift
  - Sources/RookSculpture/SculptureComposition.swift
  - Sources/RookSculpture/SculptureCompositionCodec.swift
  - Sources/RookSculpture/SculptureCompositionExamples.swift
  - Sources/RookSculpture/SculptureWorld.swift
  - Sources/RookSculpture/SculptureWorldCodec.swift
  - Sources/RookSculpture/SculptureWorldExamples.swift
  - Sources/RookSculpture/SculptureBlockWorldExamples.swift
  - Sources/RookSculpture/SculptureLinkedComposition.swift
  - Sources/RookSculpture/SculptureLinkedError.swift
  - Sources/RookSculpture/SculptureLinkedResolver.swift
  - Sources/RookSculpture/SculptureLinkedBundle.swift
  - Sources/RookSculpture/SculptureMathExamples.swift
  - Sources/RookSculpture/SculptureGalleryCatalog.swift
  - Sources/RookSculpture/SculptureGenerationProbe.swift
db_tables: []
depends_on: []
---

# RookSculpture

## Purpose

Sendable ASCII volumes up to 256 cells along each axis, bounded readable 3md and native compact .3mdb voxel codecs, PNG-independent ASCII view frames, twenty-one built-in voxel examples, typed document edits, and a bounded occupied-voxel OBJ mesh. COMPOSITION-30 adds self-contained reusable model compositions with explicit bounded expansion. WORLD-31 adds sparse model instances at exact Int64 anchors, without allocating empty space between them or raising individual model bounds. GALLERY-32 adds Blockhaven, an original editable block landscape built from reusable chunks, separately from the existing voxel catalog. Intent: SCULPTURE-1, SLICE-3, SCULPTURE-5, SCULPTURE-6, EXPORT-7, EXPORT-8, SCULPTURE-9, SCULPTURE-10, GALLERY-11, EXPORT-14, GALLERY-17, CUBES-23, GALLERY-24, RENDER-25, GALLERY-26, CUBES-27, EXPORT-28, RENDER-29, COMPOSITION-30, WORLD-31, GALLERY-32.

## Public API

WORLD-36 adds `SculptureVolumeStudyExamples` with `extent`, `chunkDimension`, `denseEquivalentWorld()` and `landscapeWorld()` for explicit development case studies. The solid world repeats one 64-cubed model at 4096 disjoint anchors and occupies exactly 1024 cubed cells, with 262,144 uniquely stored voxel bytes plus its required library root. The landscape reuses terrain/forest/water/castle/island definitions in that address domain. Its actual repeated occupancy is measured separately. Generation is deterministic and cancellable, uses existing graph/world constraints, and does not add entries to the ordinary gallery or raise 256-cell model bounds.

EXPORT-35 adds explicit upstream portable storage and immutable scene snapshots. The codec uses ThreeMD document storage for voxels and self-contained composition profiles for reusable scenes. Sparse placements remain strict Int64 JSON within a reserved root definition; references describe unique targets without expanding geometry. Capture adopts stable identities; decoding retains imported identities. Portable text and uncompressed binary are explicit copies, with a 20 MiB document bound and the upstream 16 MiB canonical graph-definition ceiling. Existing native saves and legacy file capacities remain.

COMPOSITION-40 adds linked compositions. The app-specific readable `ascii-linked-composition-1` schema stores a tile map with a `3md-files` ledger instead of an embedded library. `SculptureLinkedResolver` reads only reachable files through a host reader, refuses unsupported children, bad paths, missing files, cycles and the interim caps with the failing project path, then resolves exactly that set with ThreeMD 2.0.0 into a self-contained composition. `SculptureLinkedBundle` writes that graph as readable or uncompressed binary `3md-composition-1`, which reopens without the folder. Native composition and world decoding still follow no path.

GALLERY-41 adds `SculptureMathExamples` and `SculptureGalleryCatalog`. Math models are generated from formulas at exactly 16, 32, 64, 128 and 256 cells per axis: a sine ripple, a striped torus, a gyroid shell, a harmonic planet and layered sine terrain. The catalog lists all 32 built-in examples as metadata and creates one on demand with progress and cancellation. Existing examples are unchanged.

| Export | Contract |
| --- | --- |
| `SculptureScene` | Sendable Equatable voxel, composition or sparse-world scene value. |
| `voxels` | A bounded editable voxel sculpture. |
| `SculptureThreeMDSnapshot` | Immutable scene, retained upstream storage identities and structured inspection report. |
| `scene` | The snapshot's corresponding validated Sculpt scene. `SculptureGalleryCatalog.scene(for:progress:)` creates only a listed entry's scene, on demand, with its declared kind, extent and title; math entries check cancellation and report progress per layer, while other entries check cancellation before and after building only that entry and report zero and one. An authored voxel entry builds its own volume without initializing `SculptureExamples.all`. |
| `diagnostics` | Structured upstream report with actual code/path/line evidence. |
| `revision` | Exact canonical expected content from the upstream snapshot. |
| `SculptureThreeMDError` | Structured app-profile failure conforming to LocalizedError. |
| `diagnostic` | The actual supported-profile validation issue. |
| `SculptureThreeMDCodec` | Bounded explicit portable scene conversion and file codec namespace. |
| `isPortable` | Content recognition for the portable profile or upstream binary envelope. |
| `capture` | Validate a scene and retain stable upstream document/composition identities. |
| `isCapacityError` | Classify upstream byte/graph capacity refusal for an explicit legacy-only editing fallback. |
| `SculptureThreeMDEditing` | Atomic upstream-backed shared-voxel replacement namespace. |

COMPOSITION-34 adds pure reference-preserving voxel leaf edits. `SculptureModelEditing.replacingVoxelModel(in:modelID:expected:with:)` accepts a composition or world, compares the complete expected model, reconstructs the full graph and checks the existing readable codec bounds before returning. Every reference to that definition sees the replacement. `makingUnique(in:instanceID:newModelID:)` clones one world voxel leaf and changes only the selected instance's model ID; instance identity, origin and rotation remain. Nested tile maps are refused rather than shallow-cloned as isolated children. Cancellation and validation errors publish no partial graph.

| Export | Contract |
| --- | --- |
| `SculptureModelEditing` | Stateless immutable shared-model editing namespace. |
| `replacingVoxelModel` | Exact expected-model precondition for legacy composition/world overloads; portable snapshots require an exact expected parent revision and apply through upstream atomic transactions. All paths validate the complete resulting graph before publishing it. |
| `makingUnique` | Clone a selected world voxel leaf under a fresh safe ID and rebind only that placement. |
| `SculptureModelEditingError` | Sendable Equatable LocalizedError for refused model sessions. |
| `expectedModelChanged` | The target differs from the captured full model snapshot. |
| `voxelModelRequired` | The target is missing or is a nested tile model. |
| `unknownInstance` | The selected world instance is absent. |
| `unchangedModelID` | Uniqueness requires a different model ID. |

COMPOSITION-30 adds a pure self-contained graph of reusable voxel and tile models. Its app-specific readable `ascii-composition-1` schema preserves references; the existing voxel codecs do not silently accept or flatten it. Tile positions multiply their explicit block dimensions. Children must fit after clockwise X/Y rotation around Z, with empty padding and no clipping. All graph nodes, including unused models and unused bindings, are validated for references, cycles, rotated fit, depth, and work budgets. Each explicit expansion caches resolved children by model ID. Bounds are 256 cells on each expanded axis, 64 models including the root, 16 model nodes on a dependency path, 64 MiB summed unique resolved voxel volumes, and 65,536 nested placement occurrences summed across unique models. `expanded()` resolves the root; `expanded(modelID:)` resolves only that model and its dependencies, refusing an unknown ID. Cancellation returns no partial result. The separately lazy `compositionStarters` avoid allocating the large gallery for the tile editor; `SculptureCompositionExamples.courtyard()` demonstrates four definitions and nested shared references without changing the existing catalog.

WORLD-31 separates sparse world extent from bounded model geometry. `SculptureWorld` retains one validated composition library and at most 65,536 instances. It does not expand models during construction or serialization and has no fixed bounding cube. Anchors remain exact Int64 coordinates, including Int64.min; every component must be at most Int64.max minus 256 so adding model-local coordinates cannot overflow. World and instance IDs use the same safe identifier grammar as the library, and instances preserve clockwise rotations and model references. The app-specific `ascii-world-1` codec stores the library once and stores each instance explicitly. Viewing focus, render distance, culling, and detail levels belong to the renderer and app; they do not remove or alter persisted instances. `SculptureWorldExamples.wideWorld()` places four references to the same garden, including one a trillion cells away.

GALLERY-32 supplies Blockhaven as deterministic original content in the existing composition and sparse-world schemas. Thirty-six reusable 32 × 64 × 32 chunks and one root make thirty-seven model definitions. The root map is six by one by six tiles and expands to a bounded 192 × 64 × 192 landscape. A single global landscape is partitioned into chunks so neighboring tiles retain exact terrain continuity. The title is `Blockhaven valley`; original terrain contains a river and lake, forests, a village with fields and a bridge, a castle, a ruin and underground caves. The matching sparse world places each chunk without rotation at `(xChunk × 32, 0, zChunk × 32)`. Reference sources remain editable through the existing composition and world editors; explicit expansion creates a separate voxel copy. This is a Sculpt.3md block landscape, not a Minecraft runtime, bundled Minecraft asset set, or native Minecraft world-format implementation. The existing twenty-one voxel catalog entries remain unchanged.

### Exported Symbols

Names below are the public declarations in the source files. This table does not add signatures that are not declared there. `public private(set)` stored properties are not exports.

| Symbol | Role |
| --- | --- |
| `SculptureVolumeStudyExamples` | Deterministic bounded world fixtures for the explicit 1024-cubed development case study. |
| `extent` | The study's 1024-cell address extent, separate from the production model editing limit; on a gallery entry, the created scene's declared SculptureGalleryExtent. |
| `chunkDimension` | The 64-cell axis size of each reusable study leaf model. |
| `denseEquivalentWorld` | Construct 4096 disjoint references to one solid leaf, covering exactly 1,073,741,824 occupied cells. |
| `landscapeWorld` | Construct the sparse 1024-cubed landscape from eight shared leaves and 280 disjoint placements. |
| `SculptureTileSize` | Validated voxel dimensions of a reserved model block. |
| `SculptureModelBinding` | One printable non-period map glyph, named model and clockwise X/Y rotation. |
| `modelID` | Binding or world instance's case-sensitive library model identity, never a filesystem path. |
| `quarterTurns` | Binding or world instance's clockwise X/Y rotations around Z, 0...3. |
| `SculptureTileMap` | Validated tile grid with explicit block size and bindings. |
| `tileSize` | Reserved block dimensions. |
| `bindings` | Unique glyph-to-model references and rotations. |
| `SculptureCompositionModel` | Reusable voxel sculpture or another tile map. |
| `tiles` | A nested tile-map model definition. |
| `SculptureComposition` | Self-contained validated global model graph. |
| `maximumModels` | 64 unique definitions including the root. |
| `maximumDepth` | At most 16 model nodes along a dependency path. |
| `maximumResolvedVoxelBytes` | At most 64 MiB summed unique expanded voxel volumes. |
| `maximumPlacements` | At most 65,536 nested placement occurrences summed across unique composition models. |
| `rootID` | Identity of the root tile map. |
| `models` | Shared immutable model definitions by ID. |
| `expanded` | Resolve the root or explicitly chosen model into a detached bounded sculpture with cached shared children. |
| `SculptureCompositionError` | Localized, Equatable, Sendable composition failures. |
| `invalidRoot` | Root missing or not a tile map. |
| `invalidID` | Composition model or world instance/model ID outside 1–48 ASCII letters, digits, underscores or hyphens, starting with a letter or digit. |
| `invalidBindingGlyph` | Nonprintable byte or the reserved empty period. |
| `unboundGlyph` | A tile character without a declared model binding. |
| `duplicateBinding` | Repeated character binding or metadata alias. |
| `unknownModel` | Composition reference, explicit expansion target, or world instance model absent from the library. |
| `duplicateModel` | Repeated definition identity. |
| `cyclicReference` | A model dependency loops back to itself. |
| `childDoesNotFit` | Rotated child exceeds its tile block. |
| `tooManyModels` | Empty or excessive model library. |
| `excessiveDepth` | More than 16 dependency levels. |
| `excessiveVolume` | Unique resolved volumes exceed the 64 MiB work budget. |
| `excessivePlacements` | Recursive placements exceed the bounded work budget. |
| `invalidLibrary` | Invalid composition library envelope/model document, or invalid embedded composition library in a world. |
| `SculptureCompositionCodec` | Bounded self-contained ascii-composition-1 ThreeMD codec. |
| `isComposition` | Lightweight content detection; full validation remains in decode. |
| `compositionStarters` | Separately lazy moon-gate, little-rocket and pixel-bonsai 24-cubed models. |
| `SculptureCompositionExamples` | Deterministic graph examples separate from the existing catalog. |
| `courtyard` | Four-definition nested scene expanded to sixteen trees and sixteen gates. |
| `SculptureWorldPoint` | Hashable, Codable, Sendable exact Int64 anchor in document axes. |
| `SculptureWorldInstance` | Validated immutable instance identity, model reference, origin and rotation. |
| `origin` | Instance's exact world anchor; each component is at most Int64.max minus 256. |
| `SculptureWorld` | Equatable, Sendable sparse scene with a self-contained library and explicit placements. |
| `maximumInstances` | At most 65,536 world instances, independently of their spatial extent. |
| `library` | The world's validated SculptureComposition, preserved without dense expansion. |
| `instances` | Ordered immutable sparse model placements with unique IDs. |
| `SculptureWorldError` | Localized, Equatable, Sendable world validation and codec failures. |
| `invalidOrigin` | An anchor exceeds the positive Int64 headroom reserved for bounded models. |
| `tooManyInstances` | World placement count exceeds 65,536. |
| `duplicateInstance` | Repeated world instance identity. |
| `invalidEnvelope` | World JSON lacks the exact supported versioned fields or has malformed, duplicate, unknown or incompatible values. |
| `SculptureWorldCodec` | Bounded self-contained ascii-world-1 ThreeMD codec with exact Int64 JSON coordinates. |
| `isWorld` | Lightweight world content detection; validation remains in decode. |
| `SculptureWorldExamples` | Deterministic sparse-world examples separate from the voxel catalog. |
| `wideWorld` | Four shared garden placements at nearby and distant anchors, including trillion-cell separation. |
| `SculptureBlockWorldExamples` | Deterministic original Blockhaven content, separate from the existing voxel catalog. |
| `composition` | SculptureScene's reusable library/root-map case; `composition() throws -> SculptureComposition` creates the self-contained reusable chunk map; SculptureGalleryKind's composition-editor entry. |
| `world` | SculptureScene's sparse-world case with exact Int64 placements; `world() throws -> SculptureWorld` creates the corresponding sparse chunk placements with the same model library; SculptureGalleryKind's world-editor entry. |
| `Sculpture` | `Sendable` volume. Its title and layer grids are readable; `rename(_:)` and the layer methods change them. |
| `maximumDimension` | 256. Applies to width, height, and layer count. |
| `palette` | UTF-8 bytes of `#@*+ox:=-`. |
| `empty` | Period, byte 46. An empty cell. |
| `width` | Sculpture, inspection or tile-map columns, or tile-block voxel width. |
| `height` | Sculpture, inspection or tile-map rows, or tile-block voxel height. |
| `depth` | Sculpture and tile-map layer count, inspection depth or tile-block voxel depth; ProjectedGlyph.depth is projected depth. |
| `layers` | SculptureTileMap's immutable row-major character grids, one array per tile Z plane. |
| `occupiedCount` | Cached count of cells whose byte is not `empty`; `occupiedCount(inLayer:)` reads the per-layer count in constant work and returns zero for an invalid layer. Initialization, paint, duplication, insertion, and removal keep counts equal to the layer grids. Rotation does not change occupancy. |
| `containsOccupiedCells` | containsOccupiedCells(inLayer:) and containsOccupiedCells(inRow:ofLayer:) read the derived slice/row occupancy caches without rescanning the volume. Invalid indices return false. ASCII projection and exterior-surface extraction can skip empty regions. |
| `init` | Sculpture validates its title, bounds and palette; tile size, binding, map and composition initializers validate their block and graph contracts. World instance and world initializers validate anchors, IDs, references and capacity without expansion. SculptureWorldPoint and SculptureCell store coordinates. Camera defaults to yaw -0.6, pitch 0.35, zoom 1. Example and inspection initializers populate their facts; command and batch decoding validate their schemas. |
| `glyph` | Binding's printable non-period byte; Sculpture.glyph(at:) returns a voxel byte or nil; ProjectedGlyph.glyph is the projected byte. |
| `paint` | `paint(_:glyph:)` writes a palette byte or `empty`. Returns false when refused or unchanged. |
| `rename` | `rename(_:)` replaces the title or throws `invalidTitle`. |
| `addLayer` | `addLayer(after:duplicate:)` inserts an empty or copied layer after the index. |
| `removeLayer` | `removeLayer(at:)` removes one layer. Refuses the last layer. |
| `rotateLayer` | `rotateLayer(at:)` is a clockwise quarter turn. Requires a square layer. |
| `blank` | `blank()` is 16 by 16, one empty layer, title `Untitled`. |
| `orb` | `orb()` is the deterministic 16-cubed hollow orb, title `Character orb`, surface byte 35 (`#`). |
| `SculptureExample` | One built-in document: identity, title, summary, category, and volume. |
| `id` | Stable gallery identity or unique world instance identity. |
| `title` | Immutable example, inspection, composition or world title. A sculpture's readable mutable title changes through rename(_:); that stored property is not this export. |
| `summary` | One-line example description. |
| `category` | Gallery category: `Sculptures`, `Maps`, `Characters`, `Creatures`, `Architecture`, `Worlds`, or `Space` for voxel examples; gallery catalog entries add `Math ladder`, `Compositions`, `Landscapes`, `Sparse worlds` and `Volume studies`. |
| `sculpture` | The example volume or SculptureCompositionModel.sculpture's bounded voxel definition. `SculptureMathExamples.sculpture(_:progress:)` generates one voxel rung exactly its size on every axis, reporting increasing progress that ends at one. |
| `SculptureExamples` | The deterministic gallery. |
| `all` | The original twelve examples, eight deterministic 64-cubed examples, then `grand-solar-system` at 256 cubed. The first read builds and keeps every volume; each element is built from the same per-identity table the gallery catalog uses to build one example alone. |
| `SculptureOBJExporter` | Occupied-cell surface mesh as OBJ text. |
| `maximumFaces` | 250_000 exposed quad faces. The exporter counts faces before allocating mesh arrays. |
| `data` | `data(for:)` returns UTF-8 OBJ. It checks cancellation, throws `tooManyFaces` beyond the exposed-face budget, and does not mutate the volume. |
| `SculptureOBJExportError` | Equatable, Sendable LocalizedError for a refused mesh export. |
| `tooManyFaces` | The model has more than 250_000 exterior faces. The error explains the limit and suggests reducing isolated cubes or exporting PNG, GIF, or video. |
| `SculptureCell` | Integer coordinate. |
| `x` | SculptureCell's Int column or SculptureWorldPoint's exact Int64 X anchor. |
| `y` | SculptureCell's Int row or SculptureWorldPoint's exact Int64 Y anchor; document Y increases downward. |
| `z` | SculptureCell's Int layer index or SculptureWorldPoint's exact Int64 Z anchor. |
| `SculptureError` | `Sendable` `LocalizedError`. |
| `invalidDimensions` | Voxel/block/map dimensions violate 1...256 or tile-grid products exceed a 256-cell expanded axis. |
| `invalidGrid` | A voxel or tile layer is not width × height, or its stored grid is not the declared rectangle. |
| `invalidGlyph` | A byte is outside the palette and is not a period. |
| `invalidTitle` | Title is empty, longer than 80 bytes, or not printable ASCII. |
| `unsupportedSchema` | Readable voxel, composition or world metadata/version/axis is outside that codec's supported schema. |
| `unsupportedPlane` | A voxel/tile plane is not a supported consecutive integer Z slice, or a world is not one Z-zero World plane. |
| `tooManyLayers` | The volume already has 256 layers. |
| `lastLayer` | The last layer cannot be removed. |
| `squareLayerRequired` | Quarter-turn rotation needs `width == height`. |
| `oversizedFile` | The file is larger than 20 MiB. |
| `errorDescription` | User-facing sentences on SculptureError, SculptureCommandError, SculptureOBJExportError, SculptureBinaryCodecError, SculptureCompositionError and SculptureWorldError. |
| `SculptureCodec` | ThreeMD parse and serialize for the existing native voxel schema only. |
| `maximumBytes` | 20_971_520 on SculptureCodec, SculptureBinaryCodec, SculptureDocumentCodec, SculptureCompositionCodec and SculptureWorldCodec. |
| `decode` | Voxel codecs return validated sculptures; SculptureDocumentCodec detects readable/compact bytes. CompositionCodec returns the preserved validated graph; WorldCodec returns the sparse library and exact placements. Each applies its bounds and throws on invalid input; no codec silently flattens another schema. |
| `encode` | SculptureCodec writes readable voxels; BinaryCodec writes native compact voxels; DocumentCodec takes an explicit storage format. CompositionCodec writes the graph; WorldCodec writes the sparse world. Portable ThreeMD encoding writes explicit text or uncompressed general binary from a retained immutable scene snapshot. Graph encoders preserve references without camera state. Command/batch encode(to:) write their supported Codable schemas. |
| `SculptureBinaryCodec` | Native app-specific version-1 .3mdb codec using a bounded LZFSE voxel stream and SHA256 checksum; not an upstream ThreeMD binary standard. |
| `SculptureBinaryCodecError` | Equatable, Sendable LocalizedError for compact header, stream, checksum, and compression failures. |
| `invalidHeader` | Missing or incomplete compact magic/header, or a nonzero reserved byte. |
| `unsupportedCompression` | Compression identifier other than version 1's LZFSE identifier 1. |
| `invalidLength` | Declared, decoded, or actual container lengths disagree, or bounded output would overflow. |
| `corruptPayload` | A malformed/truncated LZFSE stream or a stream that cannot make progress. Trailing input is also refused. |
| `checksumMismatch` | SHA256 differs from the stored checksum. |
| `compressionFailed` | LZFSE stream initialization or encoding failed. |
| `SculptureStorageFormat` | String-backed Codable, CaseIterable, Sendable storage choice. |
| `readable` | Existing ascii-sculpture-1 ThreeMD text. |
| `compact` | Native version-1 compressed voxel container. |
| `fileExtension` | 3md for readable, 3mdb for compact. |
| `SculptureDocumentCodec` | Shared content-detecting read and explicitly selected write boundary. |
| `format` | format(of:) chooses compact only when the complete eight-byte compact magic matches; otherwise the readable codec performs validation. |
| `SculptureCamera` | Session pose. |
| `yaw` | Horizontal orbit, in radians. |
| `pitch` | Vertical tilt, in radians. |
| `zoom` | Frame scale. |
| `ProjectedGlyph` | One projected cell. |
| `brightness` | Projected glyph brightness. |
| `SculptureFrame` | PNG-independent view. |
| `columns` | Frame width. `frame(_:camera:columns:rows:)` defaults this to 64 and clamps it to 8...160. |
| `rows` | Frame height. The same function defaults this to 36 and clamps it to 8...100. |
| `pixels` | Row-major `[ProjectedGlyph?]`. |
| `text` | Rows of the frame. Empty pixels are spaces. Trailing newline. |
| `cell` | `ProjectedGlyph.cell` is the volume cell. `SculptureFrame.cell(column:row:)` returns that cell, or nil outside the frame. |
| `SculptureProjection` | Deterministic projection. |
| `frame` | `frame(_:camera:columns:rows:)` builds the frame. Defaults are 64 columns and 36 rows. |
| `SculptureCommand` | Codable, Sendable, flat action-tagged edit: paint, erase, fill, clearSlice, rotateSlice, or rename. Coordinates are zero-based. |
| `erase` | Set one validated cell to the empty period. |
| `fill` | Replace the seed's four-connected region of the same glyph in one slice. |
| `clearSlice` | Empty one validated slice. |
| `rotateSlice` | Rotate a square slice by 1, 2, or 3 clockwise quarter-turns. |
| `SculptureCommandBatch` | Versioned transaction containing 1...256 commands. Unknown envelope fields and unsupported versions are refused. |
| `maximumCommands` | 256. |
| `version` | Command and inspection schema version, currently 1. |
| `commands` | Ordered document edits. |
| `SculptureInspection` | Codable document facts, dimensions, occupancy, palette, and coordinate conventions. |
| `emptyGlyph` | Period string for an empty cell. |
| `coordinateBase` | Zero. |
| `axes` | X columns left to right; Y rows top to bottom; Z increasing spatial depth. |
| `SculptureCommandEngine` | Pure inspection and copy-based edits, shared by app controls and structured callers. |
| `inspect` | Return document facts without mutation. |
| `apply` | Apply one command or all commands in a batch; an error returns no edited value. |
| `SculptureCommandError` | Clear validation errors, with LocalizedError explanations. |
| `unknownAction` | Action name not recognized. |
| `unexpectedFields` | Unknown or irrelevant fields for the envelope or action. |
| `unsupportedVersion` | A SculptureCommandError for a command schema version other than 1, or a SculptureBinaryCodecError carrying a compact container version other than 1. |
| `invalidCommandCount` | Empty batch or more than 256 commands. |
| `invalidRotation` | Command slice rotation outside 1...3, or model binding/world instance rotation outside 0...3. |
| `cellOutOfBounds` | Coordinate outside the chosen document. |
| `sliceOutOfBounds` | Z outside the chosen document. |

### Public insertion APIs

| Export | Contract |
|--------|----------|
| `SculptureInsertionInput` | Decoded spatial scene plus optional matching portable snapshot; immutable Sendable input. |
| `modelTitle` | Pure optional projection of an existing stored composition entry title by model ID, without decode/encode/expansion; nil for missing IDs or standalone document storage. |
| `snapshot` | Portable source preservation, or the complete inserted-scene snapshot when the parent or an input carried portable data; nil when no portable data was involved. |
| `SculptureInsertionResult` | Validated complete replacement, published once by the native host. |
| `placedRootIDs` | Imported root model IDs in caller input order. |
| `sourceName` | Optional source filename carried with an input so refusals can name it. |
| `displayName` | The source filename when known, otherwise the scene title. |
| `usedNativeFallback` | Stored flag, true only when the portable limit refused and native values were published. |
| `SculptureInsertionError` | Atomic insertion refusal. Per-file size, fit, volume, decode and portable-capacity failures name the file; batch count, cell and character failures name the limit; cancellation stays `CancellationError`. |
| `SculptureInsertionTarget` | One composition cell a batch would fill, with its current glyph and model ID. |
| `currentGlyph` | Glyph at the target before insertion; an empty target holds `Sculpture.empty`. |
| `currentModelID` | Model bound to that glyph before insertion, or nil. |
| `isOccupied` | Whether placing at the target would replace an existing tile. |
| `SculptureSceneInsertion` | Pure namespace/remap/bind/place operations for supported voxel and tile graphs, shared by the portable and native paths. |
| `targets` | Row-major target cells for a batch from the selected cell, without changing the parent. |
| `intoComposition` | Insert a batch into consecutive row-major cells from selection; retain tile size and require child fit. Publishes portable data, falling back to native values only when neither parent nor any input carries a portable snapshot and the portable path refuses on capacity. |
| `intoWorld` | Insert at exact focus, then checked positive-X spacing with a one-cell gap, with the same fallback rule. |
| `intoCompositionNatively` | The same composition placement using native values only; the result has no snapshot. Used by the native fallback and explicit native tools. |
| `intoWorldNatively` | The same world placement using native values only. |
| `noInputs` | At least one supported child is required. |
| `unsupportedChild` | Sparse world grouping or nonspatial input cannot be a child. |
| `mismatchedSnapshot` | Input scene and supplied portable snapshot disagree. |
| `invalidSelection` | Selected composition cell is outside the root grid. |
| `insufficientCells` | Consecutive placement region cannot contain the complete batch; carries needed and available counts. |
| `noAvailableGlyph` | Not enough unused printable binding characters remain; carries needed and available counts. |
| `coordinateOverflow` | World batch placement exceeds checked Int64 coordinates. |
| `tooManyPlacements` | A world batch would exceed the instance limit; carries current, incoming and maximum counts. |
| `tooManyFiles` | More selected or discovered files than the batch limit of 64. |
| `tooManyDiscoveredEntries` | A folder scan reached the 4,096-entry discovery limit. |
| `aggregateBytesExceeded` | The named source would push the batch past the 20 MiB aggregate source limit. |
| `resolvedVolumeExceeded` | The named source would push the combined resolved model volumes of the scene past 64 MiB of voxels; refused before decoding when a compact header shows it. |
| `modelDoesNotFit` | The named source needs a larger tile than the composition's current tile size. |
| `portableLimitExceeded` | The portable limit refuses and a native copy would lose portable data in the open scene or the named sources, so nothing is inserted. |
| `source` | Wraps a refusal for one named source file. |
| `SculptureInsertionPlan` | Sendable early-check budget for one batch: file count, free cells, glyphs, models, tile fit and aggregate bytes. Counts, cells, characters and sizes are checked before files are read; tile fit and volume are checked from compact headers before decoding and otherwise right after each file decodes. |
| `maximumFiles` | Batch file limit, 64. |
| `maximumDiscoveryEntries` | Folder discovery entry limit, 4,096. |
| `admitFileCount` | Refuse a batch whose file count cannot fit before any file is read. |
| `admitBytes` | Charge one named source's byte count against the aggregate limit before decoding it. |
| `admit` | Decode or accept one named input and check its fit and counts against the plan. |
| `precedes` | Natural filename order with a stable full-path tiebreak, used for folder and multi-select batches. |
| `isSupportedFile` | Whether a path extension names a readable or compact 3md file. |
| `SculptureSceneReader` | Content-detected decode of a voxel, composition or world scene and its optional portable snapshot, shared by the app and tools. |
| `SculptureDiagnosticMessage` | Shared user-facing text for structured portable diagnostics. |
| `describe` | Render one diagnostic as a sentence. |
| `dimensions` | Read width, height and depth from a compact header without decompressing; nil for a malformed header. |
| `tooLargeToReopen` | A composition or world whose native encoding would exceed the 100,000-line or 20 MiB decode budget; carries the line and byte counts, which are placeholders (0 lines, the byte maximum plus one) for a world file over 20 MiB. |
| `validateNativeCapacity` | Refuse a composition or world whose native encoding could not reopen, without writing it. |

### Public linked composition APIs

| Export | Contract |
|--------|----------|
| `SculptureLinkedComposition` | Readable `ascii-linked-composition-1` root value: title, tile grid and size, layers, link files and quarter-turns. Validated without reading any linked file; every placed byte other than a period is a link key. |
| `files` | Link character to a path relative to the containing file. |
| `SculptureLinkedCodec` | Readable linked-root storage, content detection and `3md-files` ledger building. |
| `schema` | The app-specific scene schema `ascii-linked-composition-1`. |
| `maximumDetectionBytes` | 256 KiB searched for a linked root frontmatter; the canonical writer sorts `3md-files` first. |
| `maximumLedgerBytes` | 128 KiB of raw `3md-files` text, checked before the ledger is parsed. |
| `isLinked` | Content recognition of a readable linked root; a binary container is never one. |
| `ledgerValue` | Single-line JSON ledger built with `JSONSerialization` (sorted keys, unescaped slashes), at most 128 KiB, verified through `DocumentFileComposition.ledger(in:)`. |
| `SculptureLinkedLimit` | Interim resolution cap named in refusals until a tagged ThreeMD release bounds file intake. |
| `pathBytes` | Normalized project path, 1,024 UTF-8 bytes. |
| `componentBytes` | One path component, 255 UTF-8 bytes. |
| `links` | Ledger entries across all reachable files, 512. |
| `definitionBytes` | Bytes read across all reachable files including the root, 16 MiB. |
| `ledgerBytes` | Raw bytes in one `3md-files` value, 128 KiB. |
| `SculptureLinkedFileKind` | A child kind a linked composition refuses, detected by content: compact storage, compressed binary, a binary linked root, a native `ascii-composition-1` composition (`composition`), an `ascii-world-1` world (`world`), a composition profile, Markdown, or a stray ledger. |
| `compactStorage` | Sculpt compact `3MDB` storage. |
| `compressedBinary` | A general ThreeMD binary container with compression. |
| `binaryLinkedComposition` | A linked root stored in the general binary container. |
| `compositionProfile` | A `3md-composition-1` profile, including portable Sculpt scenes and self-contained bundles. |
| `markdown` | A Markdown or ThreeMD document without a Sculpt model schema. |
| `ledgerOutsideLinkedComposition` | A non-linked document carrying a `3md-files` ledger. |
| `description` | Short noun phrase for a refused child kind. |
| `SculptureLinkedError` | Linked and file-composition failures; messages name project-relative paths only. |
| `needsProjectFolder` | A readable linked root was decoded without its project folder; the host names the file and asks for the folder. |
| `binaryLinkedRoot` | A linked root stored as general binary is refused. |
| `outsideProject` | The root file is not inside the chosen project folder; an escaping link is `invalidPath`. |
| `invalid` | A linked root breaks a schema rule, named in the reason. |
| `file` | A named project file was refused for the given reason. |
| `missingFile` | A linked file is absent; names the file and the file that links it. |
| `invalidPath` | A link path is malformed or escapes the folder; names the link and its containing file. |
| `limit` | An interim cap was exceeded at the named path. |
| `cycle` | Linked files form a cycle, listed as a chain of project paths. |
| `SculptureLinkedReader` | Host-supplied `@Sendable` reader of one normalized project path within a byte maximum. |
| `SculptureLinkedResolution` | A completed resolution: composition, root path, reachable paths, model paths and per-file digests. Nothing partial is published. |
| `rootPath` | Normalized project-relative root path. |
| `resolvedPaths` | Every reachable normalized path in Unicode scalar order. |
| `modelPaths` | Bundle model ID to the project path that defines it. |
| `digests` | Project path to the lowercase hexadecimal SHA256 of the bytes read. |
| `SculptureLinkedResolver` | Pure reachable-only resolution through a host reader: content classification, named refusals, interim caps, cycle chains and cancellation between files, then ThreeMD 2.0.0 resolution of exactly the reachable set. |
| `maximumPathBytes` | 1,024 UTF-8 bytes in a normalized project path. |
| `maximumComponentBytes` | 255 UTF-8 bytes in one path component. |
| `maximumLinks` | 512 ledger entries across all reachable files. |
| `maximumDefinitionBytes` | 16 MiB read across all reachable files. |
| `resolve` | Resolve a linked root from its path and bytes, or read the root through the same reader first. |
| `SculptureLinkedBundleFormat` | Readable `3md-composition-1` text or the general binary container without compression. |
| `binary` | Uncompressed general ThreeMD binary; other tools can read it. |
| `SculptureLinkedBundle` | Self-contained bundle encode of a resolution and content-detected decode; `source-file` is never followed. |

### Public math example and gallery APIs

| Export | Contract |
|--------|----------|
| `SculptureMathExamples` | Deterministic formula-generated ladder: five voxel models evaluated at cell centers. Generation checks cancellation per layer and allocates no dense buffer larger than one 256-cell model. |
| `Model` | The voxel rungs keyed by axis size: `ripple` 16, `torus` 32, `gyroid` 64, `harmonicSphere` 128 and `terrain` 256. |
| `ripple` | 16-cell concentric cosine ripple filled to the floor, banded by height. |
| `torus` | 32-cell tilted torus with twelve twisted angular stripes in three colors. |
| `gyroid` | 64-cell gyroid shell clipped to a sphere, banded by height. |
| `harmonicSphere` | 128-cell planet whose radius follows spherical harmonics, with ocean, beaches, mountains, snow, mantle and core. |
| `terrain` | 256-cell layered sine terrain with a sea, snow and wavy strata. |
| `dimension` | A voxel rung's cells on every axis. |
| `formula` | The generating formula of a ladder rung or math gallery entry, in cell-center coordinates with Y measured upward; nil for authored gallery entries. |
| `SculptureGalleryKind` | Codable entry kind selecting the editor: `model`, `composition` or `world`. |
| `model` | An entry that creates one editable voxel sculpture. |
| `SculptureGalleryExtent` | Hashable, Codable cells per axis; `init(of:)` measures a voxel volume, an expanded composition root, or a world's placement bounding box without expanding it, saturating at Int.max, and zero for an empty world. |
| `SculptureGalleryEntry` | Identifiable, Hashable, Codable plain metadata: id, title, summary, category, kind, declared extent and optional formula. It holds no scene or factory. |
| `kind` | The editor kind of the scene an entry creates. |
| `SculptureGalleryCatalog` | Every built-in example in one list: the 21 voxel examples from static metadata, the courtyard and Blockhaven compositions, the wide, Blockhaven and two 1024 study worlds, and the 5 ladder rungs. |
| `entries` | All 32 entries grouped models, compositions, worlds. Listing reads static metadata and generates nothing; a test keeps the voxel metadata equal to `SculptureExamples.all`, and an internal task-local probe on every example builder and generator shows that rebuilding the listing runs none of them. |
| `mathLadder` | The five ladder models from 16 cells to 256 cells on each axis, smallest first. |
| `entry` | `entry(id:)` returns the listed entry with that identity, or nil. |
| `SculptureGalleryError` | Equatable, Sendable LocalizedError for a refused gallery request. |
| `unknownEntry` | The entry is not listed, or differs from the listed entry with its identity. |

## Invariants

### REQUIREMENT REQ-RookSculpture-013

For EXPORT-35, explicit portable scene encoding and decoding SHALL use ThreeMD2 bounded document/composition storage and immutable identity/revision snapshots, preserve voxel values and shared graph bindings including unused definitions and exact Int64 world instances, and perform atomic stale-checked shared-model edits without partial output. Portable text/binary round trips preserve the scene; malformed profiles, graph mismatches and upstream capacity failures return no partial value. Existing app-specific formats and defaults remain usable above the portable graph ceiling. Cancellation remains distinct from invalid data.

1. `Sculpture`, `SculptureCell`, `SculptureError`, `SculptureCamera`, `ProjectedGlyph`, and `SculptureFrame` are `Sendable`.
2. A cell index is `y * width + x`. Rows are Y, columns are X, and the layer index is Z.
3. `orb()` uses a 16-cubed grid. A cell is `#` when its distance from center 7.5 is in the closed range 5.6...6.7. Every other cell is a period.
4. Clockwise rotation sends `(x, y)` to `(width - 1 - y, x)`. Four turns restore the layer.
5. The document is 3md. `encode` sets the document version to `1.0`, axis `space`, the sculpture title, and metadata keys `scene-schema`, `width`, and `height` only. `scene-schema` is `ascii-sculpture-1`. Width and height are decimal strings. There is no preamble. Plane `z` values are `0..<depth`. The written label is `Slice N`. The body is a `ascii` fence with `height` rows of `width` bytes.
6. `decode` refuses data larger than 20_971_520 bytes before parsing and bounds plane directives to 256. A private preparse cap rejects more than 100,000 physical lines with `invalidGrid` before ThreeMD can allocate per-line parsing structures, independently of the byte bound. It requires axis `space`, that schema, those three metadata keys and no others, integer width and height in 1...256, 1...256 planes, no preamble, and `planesByZ` enumerated so each `z` equals its index (`0`, `1`, `2`, ...). Planes have no `x`, `y`, or extra attributes. Each body is a `ascii` fence of that rectangle. A missing document title becomes `Untitled`. The camera is not read. Existing smaller documents remain valid; the schema is unchanged.
7. A title is 1...80 bytes, each in 32...126. The codec does not drop characters or convert another schema into this one.
8. Projection does not encode PNG. Empty cells are omitted. A later glyph replaces a pixel only when its depth is greater. Non-finite yaw, pitch, and zoom become 0, 0, and 1. Finite pitch stays in -1.4...1.4 and finite zoom stays in 0.5...2. The existing nonthrowing API checks cancellation before geometry work, per row, and before returning; cancellation returns a bounded all-nil frame rather than partial projected glyphs. Normal traversal and occlusion remain unchanged.
9. This module does not import RookApp, RookCore, RookRendering, or the development targets, and it does not open a network connection or start a process.
10. `SculptureExamples.all` contains twenty-one values. The original twelve retain their order and IDs: `character-orb`, `woven-torus`, `moon-gate`, `spiral-tower`, `crystal-garden`, `little-rocket`, `pixel-bonsai`, `orbital-rings`, `hill-observatory`, `terraced-island`, `canal-city`, and `alpine-valley`. `character-orb` is `Sculpture.orb()`. Each other original volume is 24 by 24 by 24. The original `Maps` are `terraced-island`, `canal-city`, and `alpine-valley`; the other original nine are `Sculptures`. Their map samples use Y for elevation and Z for depth, sampling grid Y at Y + 6 inside the 24-cubed volume.
11. The first eight appended examples are each 64 by 64 by 64, in this order: `wandering-cartographer` (`Characters`), `clockwork-dragon`, `woodland-fox`, `deep-sea-whale` (all `Creatures`), `citadel-of-arches` (`Architecture`), `sky-island-village`, `canyon-waterfall`, and `moonlit-harbor` (all `Worlds`). Their deterministic primitives provide posed human features, creature anatomy, castle structure, and spatial scenery. All examples use only palette bytes and periods and satisfy the existing title and schema rules.
12. `SculptureOBJExporter.data(for:)` emits exposed faces of occupied cells. A face is skipped when the neighbor cell is occupied. A preflight count refuses more than 250_000 faces before mesh arrays are allocated. The object name is `sculpture`. Each glyph is a group `glyph_` plus that byte, in ascending byte order. Y points up, Z follows the slice index, and one cell is one unit centered on the volume. The text ends with a newline. Empty volumes have the six `vn` lines and no `g` line.
13. Occupancy is computed while validating a constructed document and maintained incrementally afterward. Empty-to-occupied paint adds one; occupied-to-empty paint removes one; changing one occupied glyph to another keeps the count. Adding an empty slice changes no occupancy; duplicating or removing a slice adds or removes that slice's occupancy. Private row and slice occupancy caches stay aligned through edits and let ASCII projection skip empty regions. These derived caches are not new 3md metadata.
14. The final catalog item is `grand-solar-system`, title `Grand solar system`, category `Space`, with a 256 by 256 by 256 volume. Its deterministic Sun and eight planets include Saturn rings, Earth and Jupiter moons, asteroids, a comet, and stars. Sizes and distances are artistically compressed to keep the scene legible within the volume. It remains an editable palette-and-period sculpture in the existing schema.
15. Decoding checks cancellation before and after the synchronous ThreeMD parse and while decoding slices. Cancellation does not publish a partial sculpture. ThreeMD's internal parser remains synchronous.
16. Compact storage encodes validated native voxel bytes, not serialized Markdown. Its fixed header is 60 bytes. Every integer is little endian; dimensions are 1...256 and the title is 1...80 printable ASCII bytes. The uncompressed voxel count must equal width × height × depth, at most 16_777_216 bytes. Cells are slice-major, then row-major: (z × height + y) × width + x. No camera or presentation state is stored.
17. The compact stream uses Apple's LZFSE with 65_536-byte output chunks, explicit FINALIZE, bounded output checked before appending, no-progress rejection, and a required complete end-of-stream with no unused source bytes. Decode requires exactly the declared voxel count and actual container size; trailing bytes, truncated streams, unknown versions/algorithms, invalid titles/dimensions/glyphs, and checksum mismatch are refused. Cancellation is checked per layer and stream chunk, with stream state destroyed on every exit after successful initialization.
18. The compact SHA256 checksum covers header bytes 0..<28, title bytes, and the uncompressed voxel bytes. It detects corruption of those contents; it does not identify or authenticate the file's author. Sculpture construction revalidates the decoded palette and rebuilds the derived occupancy caches.
19. SculptureDocumentCodec detects the compact magic independently of a filename extension. Explicit readable writes keep the existing ascii-sculpture-1 schema and are checked for cancellation before and after encoding. This wrapper does not turn arbitrary Markdown into a sculpture or define an upstream ThreeMD binary format.
20. Composition model IDs and world instance/model IDs are case-sensitive, 1...48 ASCII bytes, consisting of letters, digits, underscore or hyphen, with a letter or digit first. References are global identities, never paths or URLs. A composition root must be a tile map. All nodes and bindings are validated, even when unused. The graph has at most 64 models, path depth 16 including root and leaf, summed unique resolved voxel volumes of at most 67_108_864 bytes, and summed nested placement occurrences of at most 65_536. These are graph/work limits; model and expanded-root axes stay at most 256.
21. Tile grids contain periods or bound printable ASCII bytes 32...126. A period reserves an empty block. Bindings are unique and stored sorted by glyph. The block origin is (tile X × block width, tile Y × block height, tile Z × block depth). Clockwise rectangular rotation sends (x, y) to (child height - 1 - y, x); odd turns swap child width and height. Every rotated child must fit its block. Padding stays empty; no child is clipped or overlaps another block. Explicit expansion caches children per model ID for that call, returns a detached Sculpture, and checks cancellation without returning partial geometry.
22. Composition storage is app-specific ascii-composition-1, ThreeMD version 1.0, axis space. Root metadata is exactly scene-schema, root-id, width, height, tile-width, tile-height, tile-depth and declared bind- keys. A bind-C value is modelID:quarterTurns. Space and colon use canonical bind-0x20 and bind-0x3A keys; aliases that resolve to the same byte are rejected. The root's fenced JSON preamble contains exactly version 1 and models records with id/document fields, excluding the root definition. Each embedded document is readable ascii-sculpture-1 or a same-schema tile definition with matching identity/title and no preamble library. Tile planes are consecutive Z positions without offsets/extra attributes. Normal grids use fenced ascii; rows resembling backtick/tilde fences use a fenced JSON array of row strings so literal characters survive. Other fences fail.
23. Composition and world files are bounded to 20_971_520 bytes. A preflight bounds physical lines to 100,000 before ThreeMD allocates line structures, rejects duplicate frontmatter/directive keys, and caps composition planes at 256 or world planes at one. Composition's line budget includes embedded documents. JSON preflight rejects duplicate object keys and excessive nesting/value counts before Codable decoding; supported records reject missing/unknown fields. Cancellation remains distinct from malformed data. Constructors, decoding, encoding and explicit expansion do not return a partial complete value.
24. Sparse world construction validates a title, composition library and at most 65_536 uniquely named instances, with known model IDs and rotations 0...3. Every origin component is an exact Int64 at or below Int64.max - 256; Int64.min is accepted. This headroom protects addition of any nonnegative bounded model coordinate. Construction and saving do not expand the library, compute a dense bounding volume, or allocate cells between instances. Instance count is finite, while spatial extent has no fixed cube boundary. Model graph and voxel limits remain unchanged.
25. World storage is app-specific ascii-world-1, ThreeMD version 1.0, axis space, with scene-schema as its only metadata key and no preamble. Exactly one plane has z 0, label World, no offsets/extra attributes, and a fenced JSON envelope with exactly version 1, library and instances. Library is one embedded complete composition document. Every instance record contains exactly id, modelID, x, y, z and quarterTurns. Coordinates decode as Int64 integers without a floating-point conversion. Compact JSON avoids a canonical 65_536-instance document exceeding the physical-line cap. No external library file, camera, focus, render distance or hidden-instance state is stored.
26. Composition and world examples are separate from SculptureExamples.all. courtyard() has root, garden, tree and gate definitions; eight root placements of the four-model garden resolve to sixteen trees and sixteen gates. wideWorld() reuses that library and places garden at (0, 0, 0), (96, 0, 0), (512, 0, 256) and (1_000_000_000_000, 0, -1_000_000_000_000), with no allocation for the intervening space. The existing twenty-one voxel example IDs and order stay unchanged.

### Native compact layout

| Byte range | Value |
| --- | --- |
| 0..<8 | Magic bytes 33 4D 44 42 0D 0A 1A 0A: 3MDB plus the binary signature. |
| 8..<12 | UInt16 version 1, UInt8 LZFSE identifier 1, UInt8 reserved 0. |
| 12..<20 | UInt16 width, height, depth, and title byte count. |
| 20..<28 | UInt32 uncompressed voxel count and compressed stream byte count. |
| 28..<60 | SHA256 of the first 28 header bytes, title, and uncompressed voxels. |
| 60... | Printable ASCII title bytes, then exactly one LZFSE stream. |

## Behavioral Examples

- `SculptureCodec.decode(SculptureCodec.encode(sculpture))` returns the same sculpture, including a title that contains quotes and a backslash.
- Painting `(1, 2)` on a 16-wide square layer and rotating once reads that glyph at `(13, 1)`.
- A 1 by 1 column with `#` at z 0 and `@` at z 1, viewed at yaw 0 and pitch 0, keeps `@` and picks z 1.
- An empty volume's frame text contains only spaces and newlines.
- Axis `time`, a fractional `z`, a `markdown` fence, a short row, an unknown glyph, width 999999, and a file larger than `maximumBytes` are refused.
- `SculptureExamples.all` has twenty-one unique ids. `character-orb` is 16 cubed. `terraced-island` is 24 cubed and its category is `Maps`. `wandering-cartographer` is 64 cubed and its category is `Characters`. The final `grand-solar-system` is 256 cubed in `Space`.
- OBJ for an empty volume has no `g` line. OBJ for one isolated occupied cell has six `f` lines in one `glyph_` group.
- A batch renames and paints a copy. If a later edit has an invalid coordinate, no result is returned and the original volume is unchanged.
- A fill does not cross a different glyph or a slice boundary. Command decoding refuses extra fields rather than silently ignoring them.
- A checkerboard volume with more than 250_000 exposed faces throws `SculptureOBJExportError.tooManyFaces` instead of allocating or returning an unbounded mesh.
- A 256-cubed sculpture round-trips through the unchanged 3md schema within the 20 MiB file limit. Renaming or rotating it leaves `occupiedCount` equal to a direct count of its nonempty cells.
- Readable and compact encoding both reopen the same title, dimensions, palette cells, and occupancy, including a 256-cubed volume. Format detection uses bytes even when a filename has another extension.
- A compact file with a changed checksum, mismatched decoded size, unsupported version/compression, truncated stream, or trailing bytes is refused rather than returning a partial sculpture.
- A two-by-three model rotated once fits a three-by-two block; it is refused in a two-by-three block. A period in the tile grid preserves that whole block as empty.
- Saving and reopening a composition preserves shared definitions and nested references. expanded(modelID:) can resolve a library leaf without expanding the root, and an unknown ID throws unknownModel.
- World instances a quadrillion cells apart remain two references to one library model. Exact neighboring anchors above 2^53 and near the Int64 limits survive JSON save/reopen without rounding or a dense bounding allocation.
- An anchor at Int64.max - 256 is accepted; one above it is refused. A repeated instance ID or missing model is refused without returning a new world.

## Error Cases

`SculptureError.errorDescription` is the user-facing sentence for that case. ThreeMD parse errors are left as that parser's error. Unsupported schemas, including other 3md documents, throw `unsupportedSchema` or `unsupportedPlane` and are not rewritten. `paint` refuses an out-of-range cell or a byte outside the palette and period by returning false. `data(for:)` throws `CancellationError` when the task is cancelled and then returns no mesh. More than 250_000 exposed faces throws `SculptureOBJExportError.tooManyFaces`; the document is unchanged and no mesh is returned.

Composition and world validation uses SculptureCompositionError and SculptureWorldError, with localized explanations for missing/duplicate IDs, cycles, binding/rotation/fit errors, unsafe anchors, work/capacity limits and invalid schema envelopes. Their strict codecs wrap malformed parser/JSON/library input in the appropriate schema, plane, envelope or library error; cancellation remains CancellationError. They return no substitute graph, expanded sculpture or world after an error.

## Dependencies

The package product `ThreeMD` comes from the `3md` package at `../..`. It handles readable documents, portable general binary/composition storage, identities, revisions, atomic editing and diagnostics. Foundation is the shared SDK dependency. macOS compact storage uses Apple's Compression framework for LZFSE. Linux unit tests use liblzfse for that same framing, through `Sources/CLzfse/shim.h`. SHA256 is the local `SculptureSHA256` implementation on every host. No additional package dependency, product process or network operation is introduced.

## Change Log

- Linux unit tests: `Sources/CLzfse/shim.h` is part of this module. It is the liblzfse header link. Compact `.3mdb` stays the app save, not an upstream ThreeMD standard.

- Version 12: explicit ThreeMD2 portable scene copies, retained upstream snapshots and atomic shared edits for EXPORT-35. Current verification is recorded separately; old schemas and receipts remain historical.

- Shared-model preparation: COMPOSITION-34 adds exact-precondition immutable voxel definition replacement and one-world-instance uniqueness, preserving existing schemas and ThreeMD 1.8.1. Verification belongs to the new preparation record.

- Version 10: expose bounds-safe cached per-layer occupancy for WORLD-33, keeping voxel content and storage schemas unchanged. Large-map optimization verification is recorded separately.

- Version 1: bounded sculpture, codec, and view frame from the sources on `leif/ascii-sculpture`. Export names are bare. `frame` defaults to 64 by 36. No review or finalization is claimed.
- Version 2: twelve examples and occupied-voxel OBJ from the sources on disk. Export names are bare. No review or finalization is claimed. Map samples use a Y offset of 6. Codex's later verify lane is recorded in `docs/evidence/sculpture-enhancements/verification-notes.md`. grok-build did not run it.
- Version 3: typed document commands and inspection for native controls and local agents. No lifecycle approval or independent review is claimed.
- Version 4: unchanged-schema 64-cell axes and 1 MiB decoding limit, cached occupancy, eight appended detailed examples, and an OBJ preflight budget of 250_000 exterior faces. No lifecycle approval or independent review is claimed.
- Version 5: 256-cell axes and 20 MiB decoding limit in the existing schema, plus the final editable Grand solar system example at an artistically compressed scale. Original catalog entries remain unchanged. No lifecycle approval or independent review is claimed.
- Correction, same version: a private 100,000-physical-line preparse cap bounds ThreeMD allocations before parsing, and ASCII projection returns a bounded empty frame when canceled. Existing APIs and schema remain unchanged; new verification is pending separately.
- Version 6: app-specific version-1 .3mdb storage of LZFSE-compressed validated voxel bytes, a header/title/voxel SHA256 checksum, and shared readable/compact storage APIs. Readable ThreeMD remains unchanged. The decoder withholds the final LZFSE marker and drains buffered output to reject concealed concatenation. Compact verification and measurements are retained separately in `docs/evidence/compact-storage/verification-notes.md`; no lifecycle approval, review, or finalization is claimed.
- Version 7: expose derived row/slice occupancy queries for bounded exterior-surface extraction and cached live rendering. Document contents and existing file formats remain unchanged. Live-rendering verification is pending separately; no lifecycle approval, review, or finalization is claimed.
- Version 8: bounded reusable model compositions, explicit whole-root or selected-model expansion, exact Int64 sparse worlds, separate composition/world examples and strict app-specific readable codecs for COMPOSITION-30/31. Existing voxel schemas and limits remain unchanged. New verification is pending separately; no lifecycle approval, independent review, or finalization is claimed.
- Version 9: original Blockhaven chunk composition and sparse-world content for GALLERY-32, using the existing schemas and bounded model APIs without changing the twenty-one-entry voxel catalog. New verification is pending separately; no lifecycle approval, independent review, or finalization is claimed.
| 2026-10-05 | edit-shared-sculpture-models-in-place-with-transactional-undo-and-unique-world-placements: Edit shared sculpture models in place with transactional undo and unique world placements |
| 2026-10-05 | adopt-threemd-2-portable-scene-interchange-and-transactional-shared-model-editing-in-sculpt: Adopt ThreeMD 2 portable scene interchange and transactional shared model editing in Sculpt |
| 2026-10-05 | measure-a-real-1024-cubed-dense-volume-and-reusable-sparse-worlds-without-raising-production-editing-limits: Measure a real 1024 cubed dense volume and reusable sparse worlds without raising production editing limits |
| 2026-10-06 | insert-selected-3md-models-directly-into-sculpt-compositions-and-worlds-with-preserved-portable-metadata-and-one-undo: Insert selected 3md models directly into Sculpt compositions and worlds with preserved portable metadata and one Undo |
| 2026-10-06 | make-3md-file-and-folder-insertion-discoverable-and-reliable-for-people-and-explicit-file-agent-tools: Make 3md file and folder insertion discoverable and reliable for people and explicit-file agent tools |
| 2026-10-07 | open-and-resolve-linked-3md-compositions-from-a-chosen-project-folder-and-import-self-contained-bundles: Open and resolve linked 3md compositions from a chosen project folder and import self-contained bundles |
| 2026-10-07 | show-every-example-in-one-gallery-and-add-a-math-generated-size-ladder-from-16-to-10-240-cells: Show every example in one gallery and add a math-generated size ladder from 16 to 10,240 cells |
| 2026-10-07 | drop-math-ladder-worlds-1024-and-10240: Drop the 1,024-wide and 10,240-wide math-ladder worlds; the ladder is five voxel models |
