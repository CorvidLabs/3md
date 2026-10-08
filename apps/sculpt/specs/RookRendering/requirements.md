---
spec: RookRendering.spec.md
---

# Requirements

The native selected-slice outline SHALL render only that layer's line indices after repeated selection changes. Camera-independent preparation SHALL cache the bounded per-layer index streams outside the main actor; switching layers SHALL reuse the occupied surface geometry and vertex bytes. Native image verification SHALL distinguish separate asymmetric depths and repeat selection without reinstalling the document mesh.

### REQ-RookRendering-007

For WORLD-33, immutable packed native position/color/triangle/line data SHALL be preparable outside the main actor, check cancellation and preserve exact exterior face order, glyph colors, selected-layer ranges and triangle-to-face picking. Actual native installation SHALL reuse those buffers. World preparation SHALL reuse unchanged model definitions across placement revisions while enforcing the original total model face budget. Camera-dependent subpixel edge visibility SHALL retain fills, selection outlines and native picking without rebuilding buffers. Exterior extraction SHALL retain its existing stable order, complete neighbor semantics and 500_000-face limit. Prepared-scene projection SHALL match existing scalar quads, ordering and picks with the 250_000 projected-quad limit. Cube animation jobs SHALL extract once and reuse the snapshot; only the distinct all-exterior overflow SHALL fall back to the original bounded scalar path. Cancellation SHALL publish no partial scene, geometry or output.

Acceptance Criteria

- Byte/topology/color and layer-range parity, canceled preparation, unchanged geometry identity across camera/world placement changes, and native cube/ghost picks are checked. Prepared and scalar projected frames match across poses. The over-exterior-budget fallback retains previously accepted camera-visible exports. Before/after release receipts record CPU work and synchronized native snapshots without claiming on-screen FPS.

### REQ-RookRendering-001

`SculptureRasterizer` SHALL draw a `SculptureFrame` with Core Text into a charcoal bitmap and SHALL encode that bitmap as PNG. `MetalSculptureView` SHALL display a supplied ASCII or cube bitmap through Core Image on a Metal device when `isAvailable` is true. The module SHALL NOT contain an authored `.metal` shader. ASCII projection and picking SHALL remain in RookSculpture; cube geometry and picking SHALL be owned by RookRendering. A missing Metal device SHALL leave the bitmap available for a non-Metal image view.

Acceptance Criteria

- PNG bytes decode to the frame's cell size. The raster of a glyph differs from the empty volume. The source directory contains no `.metal` file. GPU availability is not claimed by this requirement's text.

### REQ-RookRendering-002

`SculptureAnimationExporter.export` SHALL write a looping GIF or a silent H.264 MP4 of one yaw revolution to a new file URL. It SHALL accept `SculptureRenderStyle`, defaulting to ASCII, and cube opacity, defaulting to 0.35. The supplied style and opacity SHALL remain fixed for the job. Cube and ASCII styles SHALL use the same volume, camera, frame dimensions, encoder, and destination protections; opacity SHALL affect cubes only. `SculptureTurntableConfiguration.standard` SHALL be 4 seconds, 10 frames per second, 64 columns, and 36 rows: 40 frames and 576 by 648 pixels. The last frame SHALL NOT duplicate the first. A GIF SHALL use 5 or 10 frames per second. The destination SHALL be a new file in an existing directory. Encoding SHALL use a unique directory `.rook-turntable-<uuid>` containing `turntable.<ext>`, and cleanup SHALL remove that directory, including an ImageIO atomic temporary file. Cancellation SHALL leave the destination unreplaced. The call SHALL NOT mutate the sculpture.

Acceptance Criteria

- `standard.pixelWidth` is 576 and `standard.pixelHeight` is 648. An existing path throws `destinationExists`. A GIF at 20 frames per second, or an odd column count, throws `invalidConfiguration`.

### REQ-RookRendering-003

`SculptureVoxelProjection.frame` SHALL produce Sendable projected cube quads with real half-unit corners, occupied-neighbor surface culling, camera-facing exterior surfaces, and the ASCII camera convention. Image dimensions SHALL clamp to 64...2048 pixels. Selected-slice empty cells SHALL be represented by pickable ghost squares without changing occupancy. Invalid selected layers SHALL add no ghost squares. `hitTest` SHALL select the nearest perspective-correct quad intersection and SHALL reject nonfinite and out-of-image coordinates. An occupied hit SHALL offer only an in-bounds empty face neighbor as `paintCell`; an empty-square hit SHALL offer its own cell. Canceled projection SHALL publish an empty frame rather than partial geometry.

Projection SHALL stop before exceeding 250_000 quads, counting camera-visible occupied faces and empty selected-slice squares. An over-budget result SHALL explicitly report `isOverBudget` and contain no partial geometry or pick targets. The rasterizer SHALL return nil for that result. This budget SHALL bound allocation for large accepted 256-cell-axis documents without mutating them.

Acceptance Criteria

- Head-on face picking in a 3-cubed fixture returns the front face and its empty neighbor. A boundary face cannot add outside the volume. Rotating to the side changes the face and neighbor. Joined cells hide shared faces. A nearer cube wins over a farther ghost square. A fully occupied 64-cubed document exposes only its 4096 front surfaces in the head-on view.

### REQ-RookRendering-004

`SculptureVoxelRasterizer.image` SHALL rasterize exterior quad fills and visible edges with default opacity 0.35, finite opacity clamped to 0...1, and a charcoal or explicitly transparent background. The selected slice SHALL be amber, and empty squares SHALL be faint amber. Glyph colors and names SHALL be available to native material controls. Rasterization SHALL check cancellation periodically and SHALL return nil when canceled. `SculptureImageRenderer` SHALL render and encode PNG for either session style and the supplied cube opacity without adding style or opacity metadata to the document. Quad raster ordering SHALL be back to front by average depth; no per-pixel volumetric renderer is claimed.

Acceptance Criteria

- A face rendered at opacity 0.35 onto a transparent background has alpha between 88 and 91 of 255 at its interior; empty background alpha is zero. A fully opaque face has alpha 255. A canceled task publishes neither partial geometry nor an image. ASCII and cube PNG paths remain views of the same unmodified sculpture.

### REQ-RookRendering-005

The live cube preview SHALL use a persistent native SceneKit view requesting the Metal rendering API, implementing RENDER-29. `SculptureVoxelSurfaceExtractor.extract` SHALL return a complete Sendable exterior scene independent of camera, omitting occupied-neighbor faces and skipping cached empty layers and rows. It SHALL check cancellation per layer and row and SHALL throw rather than publish partial geometry when canceled or when more than 500_000 exterior faces are required. This live limit SHALL remain separate from the 250_000 camera-visible CPU bitmap/export quads and the 250_000 all-exterior OBJ faces.

`SculptureLiveVoxelController` SHALL install batched document fill and edge buffers only when the caller's scene identity changes. Orbit and zoom SHALL update native camera transforms and projection without scanning the voxel volume or encoding document buffers. Opacity SHALL change materials; selected-slice highlighting SHALL select a preindexed edge range. A separate empty-cell mesh SHALL consider at most 65_536 supplied cells, retaining only in-bounds cells on the selected slice, without changing occupancy. Its cache SHALL use scene identity, slice, and supplied count; callers SHALL keep its contents aligned with that revision. Live ghost edges SHALL be hidden when the smaller projected selected-plane cell basis length is below 2.5 AppKit points, including yaw/pitch foreshortening. Ghost fills SHALL remain at opacity 0.018 with all bounded empty-cell pick targets retained. Camera-dependent edge visibility SHALL rebuild no buffers.

Native `hitTest` SHALL accept upper-left-origin view-local points independent of Retina scale and SHALL map fill or ghost hits to the shared cell/face/neighbor result. It SHALL reject nonfinite or out-of-view coordinates and uninstalled geometry. The controller SHALL expose installed identity, camera, and viewport size for stale-hit checks. Native mutable view state SHALL be main-actor isolated. The module SHALL NOT start a process, access a network, or author a custom GPU shader. CPU images, exports, and missing-Metal fallback SHALL remain available through the existing paths.

Acceptance Criteria

- A solid 64-cubed fixture extracts 24_576 exterior surfaces in stable z/y/x/face order. Joined cells omit internal faces; face neighbors are in bounds and empty or nil at a boundary. Cancellation and excess exterior surfaces return no scene.
- A mounted native controller reports its rendering API. Camera, opacity, and selected-slice changes keep its mesh installation count unchanged; a new scene identity installs a changed mesh once. Native view-local picking returns the expected surface or empty-square cell, while invalid coordinates return nil.
- A selected 256 by 256 empty slice has no more than 65_536 ghost cells. Live camera motion does not invoke the CPU raster path or change document occupancy. These acceptance criteria specify behavior; completed native and performance evidence is recorded separately.
- Dense or foreshortened cells below the 2.5-point threshold hide live ghost edges while native picking still returns their empty cells. Crossing that threshold changes visibility without reinstalling document buffers or mutating occupancy.

### REQ-RookRendering-006

The sparse-world preview SHALL implement WORLD-31 with a persistent native SceneKit view requesting Metal. `SculptureWorldScene.prepare` SHALL resolve and extract only unique model IDs referenced by world instances, once per definition, without allocating a world bounding volume or intervening empty cells. Unused definitions SHALL NOT be extracted. Each referenced model SHALL retain the 500_000 exterior-face limit; the prepared model cache SHALL contain at most 1_000_000 exterior faces in total. Cancellation, resolution, or extraction errors SHALL return no partial prepared scene. Immutable preparation SHALL be usable away from the main actor, while native view/controller state SHALL remain main-actor isolated.

Detailed model fills and edges SHALL retain glyph-derived colors. Dense nested scenes SHALL remain visibly colored rather than being washed out by neutral edges; native Metal fixtures SHALL verify both a garden and its containing courtyard.

Placement origins SHALL be rebased against the exact session focus with checked Int64 subtraction before floating-point conversion. A subtraction overflow SHALL exclude that distant placement. Relative offsets SHALL be bounded before conversion to local GPU coordinates, preserving adjacent local cell positions at large exact anchors. Clockwise quarter-turn rotation SHALL update model placement and XY bounds consistently with document coordinates.

The renderer SHALL cull by Euclidean distance to each rotated model's axis-aligned bounding box, including half-cell exterior bounds. Only boxes intersecting the session render radius SHALL become candidates. Render distance SHALL normalize to 1...1_048_576 voxel units; detail distance SHALL normalize to 0...renderDistance. Candidates SHALL sort by nearest bounding-box distance, then instance ID. At most 512 instances SHALL be active. The controller SHALL report total, active, detailed, proxy, distance-culled, in-radius capacity-omitted, detail-budget-proxy, and rendered-face counts separately. Culling and capacity limits SHALL preserve the immutable world's hidden instances.

Nearby instances SHALL share batched exterior model geometry with fill opacity 0.6 and visible edges. Instances beyond the detail radius, or downgraded by the face budget, SHALL retain selectable model-sized wireframe bounds. Full model exterior faces plus six faces per bounds proxy SHALL total at most 500_000. A world scene identity change SHALL install one geometry set per unique prepared model. Focus and distance changes SHALL retain those model buffers and update only bounded placement nodes and detail choices. Orbit, zoom, and resize SHALL update camera transform/projection without resolving models, extracting faces, scanning world placements, encoding mesh buffers, or using the CPU raster path. Session focus, distances, and camera SHALL NOT be saved as world document metadata.

Native world dragging SHALL orbit and scrolling SHALL zoom through the main-actor camera callback. A click SHALL pick the nearest detailed surface or bounds proxy, returning its instance ID through the main-actor selection callback. Native picking SHALL accept upper-left-origin view-local AppKit points, reject nonfinite and out-of-view coordinates, and require installed geometry and a camera. Dragging SHALL NOT also select an instance. The rendering module SHALL NOT mutate world placements, own their undo transaction, start a process, contact a network, or author a custom GPU shader.

Acceptance Criteria

- Instances beyond `2^53` but one local cell apart retain that separation after focus subtraction. Both share the same native geometry and remain individually pickable. An overflowing relative subtraction excludes the far instance safely.
- An origin outside the radius can remain visible when its actual model box intersects the radius. Odd clockwise quarter-turns use swapped XY bounds and produce correct occupied and empty-space picking. Moving the detail radius changes full/proxy choices while retaining installed model geometry.
- Equal-distance placement IDs produce deterministic active order. A fixture with 620 in-range placements retains at most 512 active nodes and reports 108 capacity omissions. Rendered full/proxy faces stay within 500_000, and budget-limited near instances remain selectable proxies.
- An unused definition that would exceed its extraction budget is not extracted. Used definitions exceeding 1_000_000 aggregate faces refuse preparation without a partial scene. Repeated references prepare one model definition.
- Controlled native tests compare actual shared SCNGeometry, source, and element identities across camera/focus updates; snapshots contain colored full geometry and outline proxies with receipts retaining dimensions and culling/detail counts. These tests are authored; root-owned execution and visual inspection are pending at this requirement update. Existing document-camera performance evidence remains historical and is not world-test completion evidence.

### REQ-RookRendering-014

For WORLD-37, sparse-world rendering SHALL support perspective exploration with exact integer anchoring and bounded local movement, retaining Orbit. Cancellable preparation SHALL provide shared colored coarse geometry for distant models. Rendering SHALL preserve picking, caches and finite instance and face budgets.

Acceptance Criteria
- Travel and look reuse model meshes and only rebase visibility when the anchor changes.
- Coarse geometry remains bounded, camera-independent and recognizable for nonempty models.
- Directions, normalization, Int64 edges and input cancellation have semantic and native tests.
- Native and visual evidence is distinct from FPS claims.
