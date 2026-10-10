---
module: RookRendering
version: 8
status: active
files:
  - Sources/RookRendering/SculptureWorldNavigation.swift
  - Sources/RookRendering/SculptureWorldCoarseMesh.swift
  - Sources/RookRendering/SculptureLiveWorldView.swift
  - Sources/RookRendering/SculptureRasterizer.swift
  - Sources/RookRendering/MetalSculptureView.swift
  - Sources/RookRendering/SculptureAnimationExporter.swift
  - Sources/RookRendering/SculptureVoxelGeometry.swift
  - Sources/RookRendering/SculptureVoxelRasterizer.swift
  - Sources/RookRendering/SculptureRenderStyle.swift
  - Sources/RookRendering/SculptureVoxelSurface.swift
  - Sources/RookRendering/SculptureLiveVoxelView.swift
  - Sources/RookRendering/SculptureVoxelMeshBuffers.swift
db_tables: []
depends_on: [RookSculpture]
---

# RookRendering

## Purpose

Core Text glyph raster, cached exterior cube geometry with live SceneKit Metal document and sparse-world views and native picking, projected translucent cube bitmaps for fallback and export, a Core Image Metal bitmap view, and a looping GIF or silent H.264 MP4 turntable. RookSculpture supplies the shared volume, model library, sparse placements, and ASCII projection; this module owns cube geometry, distance culling, and rendering. Intent: SCULPTURE-4, EXPORT-8, EXPORT-13, EXPORT-15, CUBES-21, CUBES-22, RENDER-25, RENDER-29, WORLD-31.

## Public API

WORLD-37 adds session-only `SculptureWorldNavigationMode` (`orbit`, `explore`) and `SculptureWorldExplorer`, whose exact Int64 `anchor` and bounded local `offset` preserve distant precision. Its checked `move(forward:right:vertical:speed:duration:)` normalizes simultaneous movement and refuses invalid or overflowing travel; `look(horizontal:vertical:)` changes orientation. Explore uses a perspective camera and focused native WASD, Q/E, Shift and drag look. Resigning the responder or window, changing mode, dismantling or releasing keys stops movement. `SculptureLiveWorldController.focusCanvas()` and `stopNavigation()` expose native focus/release. Existing orbit APIs remain available through defaulted navigation parameters. Shared coarse meshes provide colored distant silhouettes; six-face bounds remain a budget fallback, and all prepared/rendered faces count toward finite limits. Navigation never changes a model, source file, document revision or Undo.

WORLD-33 prepares immutable packed native buffers outside the main actor, preserves surface ordering for exact face picking, and reuses unchanged world model buffers. Subpixel voxel grid edges may be hidden while filled geometry, selected-slice outlines and pick targets remain. Animation jobs prepare one camera-independent exterior scene and reuse it for each pose; the existing scalar path remains available when its distinct all-exterior capacity requires a fallback. Performance is measured separately from correctness and does not claim an on-screen frame rate.

The prepared native initializer is `SculptureLiveVoxelView.init(preparedMesh:sceneID:camera:selectedLayer:opacity:preparedGhosts:controller:)`. Its mesh wrapper carries the source scene, avoiding mismatched geometry/picking inputs. The original scene initializer remains available. Worker preparation uses `SculptureVoxelMeshBuffers.prepare(_:) throws` and `SculptureVoxelGhostBuffers.prepare(cells:scene:selectedLayer:) throws`; neither contains mutable native view objects.

### Exported Symbols

| Symbol | Role |
| --- | --- |
| `SculptureWorldNavigationMode` | Session-only `orbit` or `explore` camera mode. |
| `SculptureWorldNavigationError` | Sendable local navigation failure, with localized feedback. |
| `SculptureWorldExplorer` | Exact Int64 anchor plus small local offset and bounded yaw/pitch. Checked offset initializer rebases without converting the global anchor to floating point. |
| `rebaseDistance` | 64-cell local offset threshold for checked integer rebasing. |
| `defaultSpeed` | 48 cells per second for normal free movement. |
| `move` | Checked mutating yaw-relative horizontal movement and independent upward `vertical`; normalizes simultaneous directions, validates finite nonnegative speed/time, and leaves the pose unchanged on failure. |
| `look` | Mutating finite radian orientation deltas; yaw wraps and pitch stays upright. |
| `orbit` | Existing overview camera. |
| `explore` | Perspective navigation without gravity or collision. |
| `invalidMovement` | Nonfinite input or negative speed/time is refused. |
| `coordinateOverflow` | Travel beyond signed 64-bit coordinates is refused. |
| `SculptureWorldCoarseMeshResult` | Sendable coarse buffers with original extent and scaling metadata. |
| `buffers` | Immutable coarse grid geometry prepared once per shared model. |
| `scale` | Per-axis child scaling restoring the original centered model extent. |
| `originalDimensions` | Original validated voxel dimensions. |
| `stride` | Source cells per coarse bin, rounded up to keep each axis at most 16. |
| `faceCount` | Actual coarse exterior face count used by preparation and rendering budgets. |
| `SculptureWorldCoarseMesh` | Cancellable deterministic coarse silhouette preparation preserving occupied bins and dominant nonempty materials. |
| `maximumDimension` | Coarse-grid bound of 16 per axis; ordinary document bounds remain unchanged. |
| `mode` | Defaulted world-view navigation mode; Orbit preserves existing callers. |
| `explorer` | Optional session exploration pose for the perspective camera. |
| `onExplorerChange` | Main-actor callback publishing native movement/look to session state. |
| `updateExplorer` | Applies pose without rebuilding model meshes; anchor changes rebase finite visibility. |
| `focusCanvas` | Returns whether the world canvas became the native first responder. |
| `stopNavigation` | Cancels held-key movement and clears native movement state. |
| `SculptureVoxelMeshBuffers` | Sendable packed document geometry bound to its source `scene`, with cancellation and the existing exterior-face limit. |
| `SculptureVoxelGhostBuffers` | Sendable packed selected-slice squares preserving cell order, bounded filtering and native picking. |
| `byteCount` | Summed immutable raw vertex/color/index bytes, excluding metadata and SceneKit objects. |
| `cells` | Accepted in-bounds selected-slice empty-square targets, in supplied order, considering at most 65,536 inputs. |
| `SculptureRasterizer` | Builds a `CGImage` and PNG data from a `SculptureFrame`. |
| `image` | `SculptureRasterizer.image(_:selectedLayer:)` rasters an ASCII frame. `SculptureVoxelRasterizer.image(_:opacity:selectedLayer:transparentBackground:)` rasters cube quads with defaults 0.35, nil, and false. `SculptureImageRenderer.image(sculpture:camera:style:opacity:width:height:)` selects either renderer, with opacity 0.35, width 576, and height 648 by default. Opacity affects cubes only. Each returns nil if its bitmap cannot be made; the voxel raster also returns nil on cancellation or an over-budget frame. `MetalSculptureView.image` is the bitmap to draw. |
| `png` | `SculptureRasterizer.png(_:)` encodes an ASCII frame with no selected layer. `SculptureImageRenderer.png(sculpture:camera:style:opacity:)` encodes the chosen style and cube opacity at its default image size; opacity defaults to 0.35. Returns nil if the image or destination fails. |
| `MetalSculptureView` | `NSViewRepresentable` that draws one `CGImage`. |
| `init` | `MetalSculptureView.init(image:)` stores that bitmap. `SculptureTurntableConfiguration.init(durationSeconds:framesPerSecond:columns:rows:)` defaults to 4, 10, 64, and 36, and throws `invalidConfiguration` outside 1...10 seconds, frame rates 5, 10, 20, 25, or 30, even columns 8...128, and rows 8...72. `SculptureLiveVoxelController.init()` and `SculptureLiveWorldController.init()` prepare persistent native scenes. `SculptureLiveVoxelView.init(scene:sceneID:camera:selectedLayer:opacity:emptyCells:controller:)` stores the document snapshot and session inputs. `SculptureLiveWorldView.init(scene:sceneID:focus:renderDistance:detailDistance:camera:controller:onCameraChange:onSelectInstance:)` stores a prepared world and session inputs; its two main-actor callbacks default to no-ops. |
| `makeCoordinator` | `makeCoordinator()` creates `Coordinator`. |
| `makeNSView` | `MetalSculptureView.makeNSView(context:)` returns a paused `MTKView` using the coordinator device. Both live views create their controller's `SCNView`, requesting the Metal rendering API. |
| `updateNSView` | `MetalSculptureView.updateNSView(_:context:)` replaces the bitmap and redraws. The live document view configures scene identity, camera, selected slice, opacity, and empty squares, reusing unchanged geometry. The live world view configures prepared scene identity, focus, distances, camera, and callbacks; focus and distance changes reuse model buffers, and camera changes also reuse instance nodes. |
| `dismantleNSView` | Both live views' `dismantleNSView(_:coordinator:)` detach the native view's scene. |
| `isAvailable` | True when `MTLCreateSystemDefaultDevice()` returns a device. |
| `Coordinator` | Public `MTKViewDelegate` nested in `MetalSculptureView`. |
| `mtkView` | `mtkView(_:drawableSizeWillChange:)` is a no-op size callback. |
| `draw` | `draw(in:)` renders with `CIContext` on that Metal device, or returns when Metal objects are missing. |
| `SculptureAnimationFormat` | `gif` or `mp4`. |
| `gif` | Looping GIF. Frame rate must be 5 or 10. |
| `mp4` | Silent H.264 MP4. |
| `SculptureTurntableConfiguration` | One revolution. The last frame is not a copy of the first. |
| `durationSeconds` | Length in seconds. |
| `framesPerSecond` | Frame rate. |
| `columns` | Character columns. `pixelWidth` is `columns * 9`. |
| `rows` | Character rows. `pixelHeight` is `rows * 18`. |
| `frameCount` | `durationSeconds * framesPerSecond`. The standard value is 40. |
| `pixelWidth` | Bitmap width. The standard value is 576. |
| `pixelHeight` | Bitmap height. The standard value is 648. |
| `standard` | The default configuration: 4 seconds, 10 frames per second, 64 columns, 36 rows. |
| `SculptureAnimationExportError` | `Sendable` `LocalizedError` for a refused or failed animation export. |
| `invalidConfiguration` | Duration, frame rate, columns, or rows are outside the bounds above, or a GIF uses another frame rate. |
| `invalidDestination` | The URL is not a file in an existing directory. |
| `destinationExists` | The destination path already exists. |
| `frameRenderingFailed` | A turntable frame could not be rasterized. |
| `encodingFailed` | ImageIO or the H.264 writer failed. The associated text is the detail. |
| `stalledWriter` | The video input stopped accepting frames. |
| `errorDescription` | The sentence declared for the animation, voxel-surface, or world-rendering error case. |
| `SculptureAnimationExporter` | Writes one turntable on a private worker. |
| `export` | `export(sculpture:camera:style:opacity:format:configuration:destination:progress:)` writes a new file and returns that URL. Style defaults to `ascii`, cube opacity to 0.35, and configuration to `standard`. The supplied style and opacity are fixed for the job. Progress runs from 0 to 1. The turntable is written in a unique directory `.rook-turntable-<uuid>/turntable.<ext>` beside the destination, then moved into place. Cancellation removes that directory and does not replace the destination. |
| `SculptureRenderStyle` | Sendable session presentation of the same volume, with no new document metadata. |
| `cubes` | Translucent exterior cube faces; raw value `Cubes`. |
| `ascii` | Projected glyphs; raw value `ASCII`. The default animation style. |
| `id` | The render style itself, for `Identifiable`. |
| `SculptureImageRenderer` | Style-aware image and PNG entry points. ASCII pixel dimensions are multiples of 9 by 18, using the core frame bounds; cube image dimensions clamp to 64...2048. |
| `SculptureVoxelFace` | Six document-relative face directions, used for visible surfaces and adjacent-cell painting. |
| `left` | Neighbor X - 1. |
| `right` | Neighbor X + 1. |
| `top` | Neighbor Y - 1. |
| `bottom` | Neighbor Y + 1. |
| `back` | Neighbor Z - 1. |
| `front` | Neighbor Z + 1. |
| `SculptureVoxelVertex` | Sendable projected vertex in image pixels and eye-space depth. |
| `x` | Vertex horizontal pixel coordinate, increasing rightward. |
| `y` | Vertex vertical pixel coordinate, increasing downward. |
| `depth` | Vertex eye-space depth; quad average depth is used to order raster surfaces. Greater depth is nearer the camera. `SculptureVoxelScene.depth` is the document slice count. |
| `SculptureVoxelQuad` | Four projected vertices for an exterior occupied cube face, or an empty-cell square on the selected slice. |
| `cell` | The zero-based document cell of a surface, quad, or hit. |
| `face` | An occupied surface's document-relative direction; optional in quads and hits, where nil identifies an empty slice square. |
| `glyph` | Occupied surface material byte; optional in quads, where nil identifies an empty slice square. |
| `vertices` | The quad's four image-space corners. |
| `brightness` | Directional brightness, bounded to 0.45...1. |
| `adjacentCell` | An in-bounds empty neighbor beyond an occupied face, or nil if there is none. |
| `isEmpty` | True for a ghost square; false for an occupied cube. |
| `SculptureVoxelHit` | The nearest intersected face or selected-slice empty square. |
| `paintCell` | The ghost's cell, or the occupied face's empty `adjacentCell`. Nil prevents adding beyond the volume boundary. Replace and erase can instead use `cell`. |
| `SculptureVoxelFrame` | Equatable, Sendable snapshot of projected quads and bounded image dimensions. |
| `width` | Frame image width in pixels, clamped to 64...2048. `SculptureVoxelScene.width` is the document column count. |
| `height` | Frame image height in pixels, clamped to 64...2048. `SculptureVoxelScene.height` is the document row count. |
| `quads` | Exterior camera-facing cube faces and optional selected-slice empty squares, ordered back to front for rasterization. |
| `isOverBudget` | True when the preview exceeds `maximumQuads`; the frame then contains no partial geometry or pick targets. |
| `maximumQuads` | 250_000 camera-visible cube faces plus selected-slice ghost squares. Checked before appending each quad. |
| `hitTest` | `SculptureVoxelFrame.hitTest(x:y:)` accepts upper-left-origin image pixels and returns the greatest perspective-correct intersection depth. `SculptureLiveVoxelController.hitTest(x:y:)` accepts upper-left-origin local AppKit points, independent of Retina scale, and maps native scene hits to occupied surfaces or selected-slice empty squares. `SculptureLiveWorldController.hitTest(x:y:) -> String?` uses the same local point convention and returns the nearest detailed model or outline proxy's instance ID. All reject nonfinite and out-of-view coordinates; live picking also requires an installed scene and camera. |
| `SculptureVoxelProjection` | Pure cube projection using the same center and yaw/pitch convention as ASCII. |
| `frame` | `frame(_:camera:width:height:selectedLayer:showsEmptyCells:)` projects a sculpture, with selected layer nil and empty squares enabled by default. Invalid selected layers add no ghosts. `frame(_: SculptureVoxelScene,camera:width:height:)` projects already prepared occupied exterior faces with the same math, order, picks and 250,000-quad limit. It adds no ghost inputs. Cancellation returns an empty frame with bounded image dimensions. |
| `SculptureVoxelRasterizer` | Core Graphics raster of projected quads; it adds no glyph cells or document metadata. |
| `color` | `color(for:)` returns labeled red, green, blue Doubles for the nine glyph materials. Other bytes use the mint color. |
| `name` | `name(for:)` returns the glyph's display color name: Mint, Violet, Amber, Blue, Green, Coral, Fern, Sand, or Cyan. Other bytes use Mint. These are display names, not physical material properties. |
| `SculptureVoxelSurface` | Equatable, Sendable exterior face record, independent of the camera, with cell, face, material byte, and optional empty neighbor. |
| `SculptureVoxelScene` | Equatable, Sendable document dimensions, occupancy, and complete exterior surfaces for a live mesh. It contains no AppKit or SceneKit object. |
| `occupiedCount` | The source document's occupied cell count in the scene snapshot. |
| `surfaces` | Exterior faces in stable slice, row, column, then face order. No occupied-neighbor interior face is present. |
| `SculptureVoxelSurfaceExtractor` | Builds bounded camera-independent exterior geometry, skipping cached empty layers and rows. |
| `maximumFaces` | 500_000 exterior faces across all view directions, independent of the CPU projected-quad and OBJ budgets. |
| `extract` | `extract(_:) throws -> SculptureVoxelScene` returns complete geometry or throws for cancellation or excess exterior faces. It never publishes a partial scene. |
| `SculptureVoxelSurfaceError` | Equatable, Sendable LocalizedError for an exterior scene that cannot be represented within its face budget. |
| `tooManyFaces` | Extraction would exceed 500_000 exterior faces. Its description directs editing to Slice or ASCII. |
| `SculptureLiveVoxelController` | Main-actor owner of the native scene, cached batched mesh, camera readiness, and view-local picking. |
| `viewportSize` | Current native view bounds in AppKit points, or zero before mounting. |
| `renderingAPI` | The mounted `SCNView` rendering API, or nil before mounting. |
| `updateCamera` | Each live controller's `updateCamera(_:)` changes only the native camera transform and projection, without resolving models, scanning voxels or world placements, or encoding mesh buffers. |
| `SculptureLiveVoxelView` | Main-actor `NSViewRepresentable` for a persistent SceneKit view requesting Metal. It uses batched fill and edge geometry, with native face and empty-square picking. |
| `scene` | Complete immutable document exterior snapshot or prepared sparse-world snapshot supplied to its live view. |
| `sceneID` | Caller-owned document or world/model-library geometry revision. Equal identities reuse installed model buffers. A focus or camera change must not change the world scene identity. |
| `camera` | Session yaw, pitch, and zoom, using the shared sculpture camera convention. |
| `selectedLayer` | Zero-based slice to highlight and to use for empty-cell squares. |
| `opacity` | Live cube fill opacity; finite values clamp to 0...1 and nonfinite values become 0.35. |
| `emptyCells` | Caller-supplied selected-slice empty cells. The live view considers at most 65_536, retaining only in-bounds cells on the selected slice. They add no document occupancy. |
| `controller` | Persistent document or world controller supplying the native view, readiness, camera updates, and hit testing. |
| `SculptureWorldScene` | Sendable camera-independent snapshots for only the unique model IDs referenced by world placements; contains no AppKit or SceneKit objects. |
| `maximumPreparedFaces` | 1_000_000 exterior faces summed across unique prepared world models, in addition to each model's 500_000 extraction limit. |
| `world` | The immutable sparse world supplied to preparation, with its self-contained library and exact integer placements. |
| `modelCount` | Number of unique referenced model definitions prepared, independent of instance count or render distance. |
| `prepare` | `SculptureWorldScene.prepare(_:cachedModels:) throws -> Self` resolves, extracts and packs each referenced unique model once, or reuses its existing buffers when the cached world's complete immutable library matches. The cache defaults to nil; aggregate face limits are checked even on reuse. `SculptureVoxelMeshBuffers.prepare(_:)` and `SculptureVoxelGhostBuffers.prepare(cells:scene:selectedLayer:)` pack immutable bounded native bytes with cancellation. All may run detached, contain no mutable native objects and return no partial result on failure. No bounding world volume is allocated. |
| `SculptureWorldRenderingError` | Sendable LocalizedError for an excessive aggregate prepared exterior cache. |
| `excessivePreparedFaces` | Referenced definitions would exceed the aggregate 1_000_000-face cache; the description asks the caller to simplify the library. |
| `SculptureLiveWorldView` | Main-actor `NSViewRepresentable` for a persistent SceneKit Metal sparse-world view with shared model geometry, bounded detailed instances, outline proxies, and native orbit, zoom, and instance selection. |
| `focus` | Exact `SculptureWorldPoint` session anchor. Relative integer subtraction precedes any conversion to local GPU coordinates; focus is not written to the world. |
| `renderDistance` | Session spherical radius in voxel units, normalized to 1...1_048_576. Actual rotated model bounding boxes must intersect the radius to become candidates. |
| `detailDistance` | Session spherical radius for full model detail, normalized to 0...renderDistance. In-range models beyond it use selectable bounding outlines. |
| `onCameraChange` | Main-actor native drag-orbit or scroll-zoom callback, invoked after the controller applies the changed session camera. Defaults to a no-op. |
| `onSelectInstance` | Main-actor click callback carrying a detailed model or outline proxy's instance ID. Dragging does not produce click selection. Defaults to a no-op. |
| `SculptureLiveWorldController` | Main-actor observable owner of prepared world geometry, bounded placement nodes, camera, native picking, and separately reported culling/capacity/detail counts. |
| `maximumVisibleInstances` | 512 active detailed or proxy placement nodes, chosen by nearest bounding-box distance with instance-ID ties. |
| `maximumFullDetailFaces` | 500_000 rendered faces across active full models and six faces per outline proxy. Full-detail instances that cannot fit this budget remain selectable proxies. |

The controller's publicly readable, privately set properties are `installedSceneID`, the optional installed mesh UUID; `currentCamera`, the optional camera applied to the native view; and `meshInstallationCount`, the count of document mesh installations. Camera, opacity, and selected-slice updates do not increase that count. These readiness and diagnostic properties do not guarantee a frame rate and are described here rather than included in SpecSync's exported-symbol inventory.

The world controller's publicly readable, privately set properties are `installedSceneID`, `currentCamera`, `totalInstanceCount`, `visibleInstanceCount`, `fullDetailInstanceCount`, `proxyInstanceCount`, `omittedInstanceCount`, `culledInstanceCount`, `detailBudgetProxyInstanceCount`, `renderedExteriorFaceCount`, and `meshInstallationCount`. The active count is detailed plus proxy instances; distance culling is separate from in-radius capacity omissions. Detail-budget proxies are the near instances downgraded by the face limit. The face count includes six faces per outline proxy. World mesh installations count one buffer set per unique prepared model on each changed scene identity. Camera, focus, and distance updates retain those sets. Observable count/camera/readiness fields allow native UI status to refresh; SceneKit and cache state are excluded from observation. These privately set properties belong in this prose rather than the exported-symbol table.

## Invariants

1. No `.metal` shader is authored. Live cubes use SceneKit's Metal view and cached geometry. ASCII, cube bitmap fallback, and image/animation export use a `CGImage` produced by Core Text or Core Graphics; the bitmap display path uses Core Image's Metal context when available.
2. The raster uses Menlo Bold at 15 points, a 9 by 18 cell, and the charcoal fill red 0.065, green 0.085, blue 0.10. The selected layer is tinted warm. Other glyphs are tinted green. Brightness scales those fills. Menlo is a system font, not a bundled resource.
3. `png` does not take a selected layer, so an exported image is the untinted frame.
4. `isAvailable` is the GPU gate. A missing device does not invent a second geometry.
5. This module imports RookSculpture. It does not import RookApp, RookCore, or the development targets. It does not open a network connection or start a process.
6. A turntable adds one full yaw revolution across `frameCount` frames and does not append the starting frame again. GIF properties set the loop count to 0. MP4 is H.264 in an `.mp4` file and has no audio track. The writer creates a unique directory `.rook-turntable-<uuid>` beside the destination and encodes `turntable.gif` or `turntable.mp4` inside it. ImageIO may leave a hidden atomic temporary file in that directory. Cleanup removes the directory. The finished file is moved to the destination. An existing destination is refused. The sculpture value is not mutated.
7. `standard` is 4 seconds, 10 frames per second, 64 by 36 characters, and 576 by 648 pixels.
8. Cube corners are the document cell center plus or minus half a unit. Faces with occupied neighbors are omitted. CPU projection culls exterior faces pointing away from the camera; the live mesh retains all exterior directions so orbit reuses it. World Y points upward while document Y increases downward. Perspective distance is three times the maximum document dimension. Nonfinite yaw, pitch, and zoom become 0, 0, and 1; finite pitch clamps to -1.4...1.4 and zoom to 0.5...2.
9. The selected empty slice consists of faint pickable XY squares at its Z coordinate. It creates no occupied cubes. A cube hit is chosen by perspective-correct triangle intersection depth, so a farther ghost square does not override a nearer occupied face. Projected bounds are cached per quad to reject distant hit candidates before triangle interpolation.
10. CPU cube fills have opacity 0.35 by default. Finite opacity clamps to 0...1; nonfinite opacity becomes 0.35. Raster edges remain visible. A selected layer is amber, and ghost squares use faint amber fills and edges. A clear background is optional; otherwise the background is charcoal. Surface rasterization uses back-to-front quad-average ordering, not volumetric ray tracing or a per-pixel transparency depth buffer.
11. Voxel projection checks cancellation per Z slice and before and after sorting. A canceled projection returns no partial quads. Rasterization checks cancellation every 256 quads and before publishing the image. Cube frames and geometry values are Sendable and contain no AppKit view state.
12. CPU projection for bitmap fallback and exports is bounded at 250_000 camera-visible quads, including editable empty squares. Exceeding the budget returns `isOverBudget: true` with no quads; rasterization returns nil instead of encoding a misleading empty preview. Empty unselected layers are skipped. A canceled frame is distinct from an over-budget frame. The live scene has its separate 500_000 all-exterior-face budget, and OBJ's separate 250_000 all-exterior-face preflight remains in RookSculpture. The app keeps Slice and ASCII available when a cube path exceeds its budget.
13. `SculptureRenderStyle` and opacity are presentation only. The cube and ASCII image and animation paths read the same glyph volume and camera. Neither style nor opacity is written into 3md. Style-aware PNG and animations accept the caller's chosen cube opacity; ASCII ignores that opacity. Animation retains ASCII as the source-compatible default and cube turntables use the same output dimensions and encoder as ASCII.
14. Exterior extraction checks task cancellation before work, per layer and row, and before returning. Cached layer and row occupancy queries skip empty regions. It returns complete surfaces in stable z/y/x/face order; cancellation or exceeding 500_000 faces throws with no partial scene. Extraction does not depend on camera or mutate the document.
15. A new `sceneID` installs batched fill and edge vertex/index buffers. An unchanged identity reuses those buffers. Camera updates change only native transforms and projection. Opacity changes materials. Slice highlighting selects a preindexed edge range without re-encoding the base geometry. Callers must change the identity whenever geometry or material bytes change.
16. Ghost geometry is separate from the base mesh, limited to 65_536 caller-supplied squares and filtered to the selected in-bounds slice. Its cache key is scene identity, selected layer, and supplied cell count; callers must keep empty-cell contents consistent with that scene revision. Live ghost edges are hidden when the smaller projected selected-plane cell basis length is below 2.5 AppKit points, accounting for yaw/pitch foreshortening, viewport size, volume extent, and normalized zoom. Faint ghost fills retain opacity 0.018 and all bounded pick targets remain; this visibility update rebuilds no buffers. Native picking ignores edge-only decoration and maps the hit face index back to a surface or ghost cell.
17. Native view/controller state is main-actor isolated; immutable surface extraction can run away from the main actor. The controller exposes installed identity, applied camera, and viewport size so a caller can reject stale picking. The app freezes scene, camera, opacity, and empty-square inputs for a painting stroke; this module itself does not mutate a sculpture or own the undo transaction.
18. A prepared sparse world resolves only unique model IDs referenced by placements, once per definition. Unused library definitions are not extracted. Each referenced model retains the 500_000 exterior-face extraction limit, and all prepared definitions together are limited to 1_000_000 faces. Preparation checks cancellation between definitions and before returning; model resolution and extraction also check cancellation. An error returns no partial prepared world. Models retain their individual bounded volumes; no cells are allocated between world placements.
19. World placement origins are rebased against the exact session focus using `Int64.subtractingReportingOverflow` on each axis. Overflow excludes the distant placement. The renderer compares bounded integer offsets before converting them to local floating-point coordinates, preserving nearby cell differences at anchors beyond exact Double integer range. Clockwise quarter-turns swap XY bounds when odd, and shared centered model geometry rotates about its local Z axis after document-Y inversion. No absolute Int64 anchor is converted directly to a GPU coordinate.
20. Render candidates are selected by Euclidean distance from the focus to each rotated model's axis-aligned bounding box, including its half-cell exterior limits. A bounding box must intersect the normalized render radius. Candidates sort nearest first with deterministic instance-ID ties. At most 512 become active; remaining in-radius placements are counted as capacity omissions, while outside-radius placements are counted as culled. The immutable world retains every placement, including those not rendered.
21. Active candidates within the normalized detail radius use shared batched exterior fill and edge geometry when the rendered-face budget permits. Detailed fills use opacity 0.6. Beyond that radius, or when detail would exceed the face budget, the placement uses a shared model-sized wireframe `SCNBox`, retaining its rotation and pickable instance identity. At most 500_000 faces are rendered, counting full exterior model faces and six faces per outline proxy. The prepared cache, active-instance, rendered-face, single-document, CPU export, and OBJ limits are distinct; no count is a claim that every placement is rendered in full detail.
22. World scene identity changes install one GPU geometry set per prepared model definition. Repeated instances share that set. Focus and radius changes rebuild only bounded placement nodes and proxy/detail choices. Camera-only updates retain model buffers and instance nodes and update native transform/projection only; they do not resolve models, extract surfaces, scan placements, or run the CPU rasterizer. Native resize updates the projection. Session focus, distances, and camera are not document metadata.
23. Native world mouse dragging beyond the click threshold changes yaw/pitch; scroll changes bounded zoom. A click selects the nearest detailed surface or proxy bounds through upper-left-origin native view-local picking, returning its stored instance ID. This view owns no placement edit, undo transaction, filesystem access, process, or network capability. World rendering has no selected-slice ghost mesh. The caller owns world edits and supplies a changed identity and prepared scene for those edits.

### REQ-RookRendering-008

Native scalar, prepared and live volume projection SHALL use the same full-turn camera basis, screen-space pan target and finite inputs. Panning SHALL translate both the eye and target in the camera right/up plane. Camera-facing surface selection and nearest-quad picking SHALL account for the translated eye. Camera updates SHALL reuse the installed document buffers. Rendering, ghost and export budgets SHALL remain unchanged.

Acceptance Criteria:

- The shared camera fixture compares native basis and projected points with browser values. Native scalar/live picks agree through the poles, upside down and after pan; the mesh installation count remains one.

## Behavioral Examples

- A frame raster is wider than an empty frame's uniform charcoal only where glyphs were projected.
- `png` data begins as a PNG of `columns * 9` by `rows * 18` pixels when encoding succeeds.
- When `isAvailable` is false, callers still have the `CGImage` from `image`.
- `SculptureTurntableConfiguration.standard` is 4 seconds, 10 frames per second, 64 columns, and 36 rows. Its pixel size is 576 by 648 and its frame count is 40.
- A GIF requested at 20 frames per second, an odd column count, and a destination that already exists are refused before a finished file is published.
- A front-facing isolated cube at `(1,1,1)` in a 3-cubed document can add at `(1,1,2)`; a front face at Z 2 cannot add beyond that document.
- An all-empty selected 3 by 3 slice has nine visible ghost squares, and picking its center returns the empty center cell without inventing occupancy.
- A solid 64-cubed volume viewed head-on has 4096 visible front-face quads, with no shared interior faces.
- A disconnected checkerboard exceeding the visible surface budget reports `isOverBudget`, offers no partial picking, and produces no cube bitmap; its shared document still projects in ASCII.
- Rendering a cube with opacity 0.35 onto a transparent background produces a translucent face and leaves empty background pixels clear.
- Extracting a solid 64-cubed volume yields 24_576 exterior faces across all six directions, with no interior faces; that live scene remains unchanged when the camera turns.
- Reusing one scene identity while changing camera, opacity, or selected layer keeps `meshInstallationCount` unchanged. A new identity installs the changed document mesh once.
- An exterior extraction that would exceed 500_000 faces throws `tooManyFaces`; it does not return the first 500_000 as a misleading scene. A 256 by 256 selected empty slice can supply 65_536 ghost squares separately from that exterior budget.
- A dense selected slice or an edge-on camera can reduce projected cell spacing below 2.5 points. The live ghost edges then disappear while faint fill geometry remains pickable, and changing camera visibility retains the installed buffers.
- Two placements anchored beyond `2^53` and one cell apart retain their one-cell local separation after focus subtraction, share one model geometry, and return their distinct instance IDs when picked. A subtraction that overflows excludes the distant instance before conversion.
- A long model whose origin is outside the render radius still becomes a candidate when its actual bounding box intersects that radius. An odd quarter-turn uses the swapped XY dimensions; the origin alone is not the distance test.
- A near placement can show its colored exterior geometry while a farther placement of the same model shows selectable bounds. Moving focus or detail distance changes that choice without reinstalling the shared model buffers.
- With 620 equally distant placements, instance-ID order chooses the first 512 active placements and reports 108 capacity omissions. Near instances downgraded to proxies by the face cap remain separately counted and selectable.
- An unreferenced library model requiring more than the exterior extraction budget is not extracted during world preparation. Referenced definitions exceeding 1_000_000 total exterior faces throw without a prepared scene.

`SculptureLiveWorldTests` contains controlled native tests for integer rebasing, overflow exclusion, bounding intersection, clockwise rotation and empty-space picking, shared geometry identity across camera/focus updates, active and face budgets, skipped unused definitions, aggregate cache refusal, and real SceneKit Metal snapshots with retained receipts. At this documentation update those tests are authored and their root-owned execution and visual inspection are pending. Existing evidence under `docs/evidence/camera-performance/` describes the earlier bounded document canvas; it is not new sparse-world verification.

## Error Cases

`image` and `png` return nil when the bitmap or PNG destination cannot be created. A canceled voxel projection returns an empty frame; a canceled or over-budget voxel raster returns nil. Exterior extraction throws `SculptureVoxelSurfaceError.tooManyFaces` or `CancellationError` and returns no partial scene. `hitTest` returns nil outside the image/native view and for nonfinite coordinates; live picking also returns nil before installing a scene and camera. `draw(in:)` returns without drawing when the device, queue, context, or drawable is missing. There is no silent substitute mesh. Animation export throws `SculptureAnimationExportError` for a bad configuration, destination, frame, or encoder, and `CancellationError` when the task is cancelled. Cancellation deletes the owned staging directory and leaves the destination unpublished. A missing Metal device leaves the CPU bitmap fallback available and uses a Core Image context for MP4 frames.

World preparation propagates model-resolution and single-model extraction errors, throws `SculptureWorldRenderingError.excessivePreparedFaces` for the aggregate cache limit, and throws `CancellationError` when canceled. None returns partial world geometry. Distance and active/detail capacity limits do not delete instances or pretend to render them all: observable counts expose distance culling, in-range capacity omissions, and full/proxy choices. Relative coordinate subtraction overflow excludes the far placement safely. World native picking returns nil for excluded instances, invalid points, or an unmounted/unconfigured view.

## Dependencies

RookSculpture, AppKit, Observation, SceneKit, simd, Core Text, Core Graphics, ImageIO, UniformTypeIdentifiers, Core Image, Metal, MetalKit, AVFoundation, CoreVideo, and SwiftUI. No package dependencies. No authored GPU shader.

## Change Log

- 2026-10-10: Full-turn volume camera, screen-space pan and matched browser/native projection. Verification and lifecycle closure are recorded separately.

- Version 6: worker-prepared native mesh/ghost bytes, cached model reuse across world placement edits, subpixel grid edge detail, direct-neighbor exterior extraction and a prepared-scene cube projection reused by animation jobs for WORLD-33. Existing scalar fallback and capacity limits remain. New release measurements and verification are recorded separately under `docs/evidence/blockhaven/`; no lifecycle approval or finalization is claimed.

- Version 1: raster and Metal-backed view from the sources on `leif/ascii-sculpture`. Export names are bare. No review or finalization is claimed.
- Version 2: GIF and MP4 turntable export from the sources on disk. Export names are bare. No review or finalization is claimed. Staging is the owned directory `.rook-turntable-<uuid>/`, not a sibling file. Codex's later verify lane is recorded in `docs/evidence/sculpture-enhancements/verification-notes.md`. grok-build did not run it.
- Version 3: Sendable projected cube surfaces, empty-slice and adjacent-face picking, translucent Core Graphics raster, material display colors, and style- and opacity-aware PNG and turntable paths. ASCII remains the default animation style. No lifecycle approval or independent review is claimed.
- Correction, same version: bound projection at 250_000 camera-visible quads for 256-cell-axis documents, distinguish over-budget frames from canceled frames, and refuse rasterization of partial geometry. No lifecycle approval or independent review is claimed.
- Version 4: camera-independent exterior extraction and a persistent SceneKit Metal live cube view reuse batched document geometry for camera, opacity, and slice updates. Live extraction is bounded at 500_000 exterior faces, with a separate 65_536-square empty-slice mesh; CPU bitmap/export and OBJ budgets remain distinct. Release packaging and live-rendering verification are recorded in `docs/evidence/camera-performance/`. No lifecycle approval, review, or finalization is claimed.
- Correction, same version: adapt live empty-slice edge visibility below 2.5 projected AppKit points, retaining faint fill picking and unchanged mesh buffers. The dense-grid snapshot/target regression, full lane and actual native orbit, zoom, selection and face/ghost-stroke Undo checks passed; retained evidence is in that same directory.
- Version 5: a Sendable prepared sparse-world scene and observable native SceneKit Metal controller retain shared model buffers across focus and camera changes. Exact integer rebasing precedes distance culling and GPU conversion; nearby placements use bounded full detail, farther or over-budget placements use selectable bounds. Unique prepared definitions are limited to 1_000_000 exterior faces; at most 512 active placements and 500_000 full/proxy faces are rendered. Controlled tests are authored with execution and new visual evidence pending in the root lane. Earlier bounded-document camera evidence is unchanged; no lifecycle approval, review, or finalization is claimed.
| 2026-10-05 | add-free-exploration-of-sparse-worlds-with-wasd-movement-drag-to-look-vertical-travel-and-a-clear-overview: Add free exploration of sparse worlds with WASD movement, drag to look, vertical travel and a clear overview |
