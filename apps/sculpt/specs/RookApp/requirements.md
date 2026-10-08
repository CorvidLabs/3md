---
spec: RookApp.spec.md
---

# Requirements

### REQ-RookApp-011

For WORLD-33, live document and ghost mesh packing SHALL run outside the main actor in the actual app preparation path, with cancellation and stale-revision guards. Camera, opacity, selection and metadata-only title edits SHALL retain unchanged document buffers. World placement edits SHALL reuse unchanged bounded library model geometry. Document dirty/save/Undo semantics SHALL remain independent of geometry cache reuse. Slice drawing SHALL restrict work to visible cells with a small fringe, retain every visible cell and previous-slice hint, preserve precise scroll/hit/keyboard coordinates, and resolve distinct glyphs once per draw. Thumbnail cache identity SHALL include its own slice bytes, dimensions and resolved appearance colors; other-slice or camera changes SHALL NOT invalidate that thumbnail. Optimization SHALL NOT raise file, voxel, model or rendering capacity limits.

Acceptance Criteria

- Large-map mesh preparation is immutable and cancellable; stale work cannot replace a newer edit. Native cell/ghost picks and one-step stroke Undo still work. World move/rotation Undo retains model buffers. Title changes and their Undo affect dirty state without reinstalling identical geometry. Clipping tests include Fit, zoom, partially visible cells and offscreen cells; native checks retain scroll and keyboard editing.
- Clicking a visible sidebar slice SHALL select that layer without recentering the list under the pointer. Selection from the 3D canvas or keyboard SHALL still reveal its slice. Native scrolling SHALL update the bounded drawing region from the actual clip viewport, rather than relying on an unchanged SwiftUI frame preference.

### REQ-RookApp-010

For WORLD-31, a native sparse-world sheet SHALL retain shared model definitions and exact signed Int64 placements without a fixed dense cube. Focus, camera and render/detail distances SHALL be session state and SHALL NOT change the saved world. Focus changes SHALL preserve precise distant anchors; checked movement SHALL reject integer overflow. Placement, rotation, removal and Undo/Redo SHALL preserve exact origins. Scene preparation SHALL run detached only for geometry revisions; stale preparation SHALL be canceled. The view SHALL report visible/full/proxy/culled/capacity counts and SHALL retain hidden placements in storage. Open selected model SHALL explicitly produce a detached bounded voxel copy.

Reference saves SHALL capture immutable composition/world graphs and SHALL be cancellable. Native save completion or cancellation SHALL restore the draft; only successful writing SHALL clear its unsaved flag. The quit warning SHALL include dirty reference drafts without changing the main voxel saved baseline. Native Open SHALL route reference schemas to their appropriate editor rather than flattening them.

Using a composition in a new world SHALL mark that new world unsaved until it is written, including a graph carried from an edited composition.

Acceptance Criteria

- Positions beyond 2^53 and negative/extreme representable coordinates survive draft edits, Undo/Redo and save/reopen exactly. Viewing focus/distance/camera retains geometry and document state. Stale/canceled saves cannot publish a later result, native save cancellation restores the same graph, and the current sculpture remains unchanged until explicit replacement.

### REQ-RookApp-009

For COMPOSITION-30, File and command search SHALL open a native click-based composition editor in the same window. The person SHALL choose a model character, place/erase tiles, configure bounded dimensions and rotate bindings. Model import SHALL read only a selected bounded local file and embed a snapshot, remapping nested graph IDs. Save composition SHALL preserve references in user-selected readable 3md and restore the draft after success or cancellation. Opening a composition SHALL return to its tile editor. Open editable voxels SHALL explicitly expand a copy asynchronously and use dirty-work replacement confirmation; painting/exporting that copy SHALL NOT rewrite reusable definitions. Canceled/stale draft preparation SHALL NOT overwrite later draft state. Invalid input SHALL preserve the existing sculpture.

Acceptance Criteria

- Native clicks place repeated model tiles; expansion matches the selected bindings. A completed save/reopen preserves references. Canceling a save restores the draft; baking and Undo/painting affect only the detached main document. The native form exposes clear control names and bounded preview errors.

### REQ-RookApp-001

The app SHALL show one main window with id main, titled Sculpt.3md, a Settings scene, and a menu bar extra titled Sculpt.3md whose commands are Show Sculpt.3md, the Settings link, and Quit Sculpt.3md. Show Sculpt.3md SHALL reuse that main window. `CFBundleName` and `CFBundleDisplayName` SHALL be Sculpt.3md. `CFBundleExecutable` SHALL remain Rook. `CFBundleIdentifier` SHALL remain `labs.corvid.rook`. Settings SHALL persist only the rook.appearance value. The bundle SHALL NOT contain font or image resources.

Acceptance Criteria

- The menu commands are Show Sculpt.3md, Settings, and Quit Sculpt.3md. Closing and choosing Show Sculpt.3md does not create a second main window. Appearance is the only stored preference. The executable and bundle identifier remain Rook.

### REQ-RookApp-002

The main window SHALL host the sculpture editor. A session SHALL start on `Sculpture.orb()` in Cubes with a session camera, opacity 0.35, and Paint off. The person SHALL paint, erase, add, duplicate, remove, and clockwise-rotate the selected slice, pick a cell from the preview, orbit, undo, and redo. The title SHALL be edited through `Sculpture.rename`. Compact/readable Save, PNG export, and text export SHALL share one `SculptureExport` file exporter. Reopen SHALL use a user-selected readable .3md or compact .3mdb file bounded at 20 MiB, autodetected by content. PNG SHALL use the chosen render style and cube opacity; text SHALL remain ASCII. A refused file SHALL leave the open sculpture in place. The bundle SHALL enable only `com.apple.security.app-sandbox` and `com.apple.security.files.user-selected.read-write`. The editor frame minimum SHALL be 940 by 650.

Acceptance Criteria

- The menu and Settings behavior in REQ-RookApp-001 still holds. New and reopened sculptures reset the camera. Dirty replacement asks first. The entitlement file has those two keys and no network, bookmark, or keychain key.

### REQ-RookApp-003

The editor SHALL offer all twenty-one `SculptureExamples.all` documents, Draw, Erase, Fill, slice brush sizes 1, 3, and 5, clear slice, and viewpoints Orbit, Front, Side, and Above. Gallery construction SHALL run away from the main actor and show progress while loading. Loading an example SHALL reset undo and SHALL ask before replacing a dirty sculpture. Maps, Worlds, and Space SHALL set pitch to 0.7 after that reset; other categories SHALL use 0.35. The slice list SHALL center the selected slice on appear, on a depth change, and on a layer change except when clicking a visible sidebar slice. That sidebar click SHALL select the slice without recentering the list under the pointer; selection from the 3D canvas or keyboard SHALL still reveal its slice. The brush size row SHALL show the caption Brush once. GIF, MP4, and OBJ export SHALL render from a snapshot inside `SculptureExportStudio`, show progress, accept cancel, and then present one `FileDocument` `fileExporter` in that studio. GIF and MP4 SHALL retain the snapshot's selected style and cube opacity; OBJ SHALL use its occupied geometry independently of presentation. The studio SHALL read the generated bytes with `mappedIfSafe`. Content types SHALL be `.gif`, `.mpeg4Movie`, and `.sculptureMesh`. The default filename SHALL be the generated file's name. Duration, frames per second, and resolution SHALL stay locked while a job is running or a generated file is waiting. The studio SHALL apply the Brand palette. A save or export error SHALL keep the generated file for another attempt. The studio SHALL NOT use the system file mover. Cancel SHALL leave the open sculpture in place. Compact/readable Save, PNG, and ASCII text SHALL keep one other `SculptureExport` `fileExporter` in the main editor. Each view SHALL have one `fileExporter`. The app SHALL NOT import RookTool, RookTooling, or RookVerification.

Acceptance Criteria

- A cancelled example replacement and a cancelled GIF, MP4, or OBJ export both leave the open sculpture. The default animation frame is 64 by 36. The larger frame is 96 by 48. A failed studio save keeps the generated file. The studio does not start a process or open a network connection.

### REQ-RookApp-004

The editor SHALL open with a dominant 3D canvas in Sculpt mode and SHALL provide a spacious Slice mode with contextual editing controls. Cmd-1/2 SHALL switch modes. Cmd-K SHALL open a searchable palette of actual editor actions. Return SHALL execute the highlighted available action, and Escape SHALL dismiss the palette and restore focus. Stable accessibility names and identifiers SHALL describe controls, slices, canvas, and commands. Existing dirty-document guards and native save/export behavior SHALL remain.

Acceptance Criteria

- Minimum and default layouts render without clipping essential controls. The selected slice stays visible. Brush tools appear in Slice mode, and camera controls remain contextual. Shared structured batches are atomic and one-step undoable in the workspace.

### REQ-RookApp-005

The Sculpt canvas SHALL distinguish Orbit from explicit Cubes Paint mode. Native canvas-local mouse down, drag, and up SHALL deliver flipped local coordinates across the embedded GPU view, without a global event monitor. Mouse down SHALL acquire the existing scoped canvas keyboard responder. With Paint off, drag SHALL orbit and a click SHALL select a rendered cell. With Paint on, Draw SHALL add to an in-bounds empty face neighbor or selected-slice ghost square, Erase SHALL remove the occupied hit cube, and Fill SHALL change the matching connected region on its slice. Surface painting SHALL use a one-cell brush and SHALL NOT orbit. A drag SHALL freeze its first matching render geometry and document generation, SHALL be one undo step, and SHALL end on mouse up, document replacement, or presentation change. Cube opacity SHALL be adjustable from 0.15...1. Mesh extraction and bitmap preview work SHALL run away from the main actor, cancel obsolete work, and SHALL NOT install canceled results. The live GPU camera SHALL update directly without rebuilding that mesh. Selection SHALL use geometry matching the current presentation.

Acceptance Criteria

- A face stroke adds or removes cubes without changing camera pose and undoes as one edit. Newly added cubes do not change the hit depth of subsequent events in the same stroke. An out-of-bounds face cannot add a cube. Canceled or obsolete preview work cannot become the interactive current frame.
- Native canvas click, drag, and release reach the correct local coordinates and callbacks; mouse down focuses the keyboard canvas. Model-only tests do not establish actual pointer delivery in the running Metal-backed view.
- Live GPU cube scenes are bounded at 500,000 exterior faces plus at most 65,536 selected-slice ghosts. CPU raster previews retain 250,000 visible quads. Exceeding either budget shows a clear limit message with Slice and ASCII alternatives, publishes no partial picking geometry, and disables surface painting for that scene.

### REQ-RookApp-006

The editor File menu SHALL offer new 16-, 32-, 64-, 128-, and 256-cubed empty volumes, opening Cubes with Paint enabled, through existing dirty-replacement guards. Cmd-K SHALL also offer New 256-cubed volume. Slice mode SHALL offer Fit, 2×, 4×, 8×, and 16× grid zoom with two-axis scrolling. Pointer-to-cell geometry SHALL remain local to the canvas regardless of scroll offset. Changing zoom SHALL finish a stroke and center the selected cell; keyboard selection SHALL center the selected cell while zoomed.

Acceptance Criteria

- A new 256-cubed volume has a visible editable empty slice. Canceling a dirty replacement keeps the current document, including an uncommitted title draft. Zoomed selection and pointer painting remain in bounds through coordinate 255 on every axis.

### REQ-RookApp-007

For EXPORT-28, Save and Cmd-S SHALL default to compact .3mdb. File, Cmd-Shift-S and the command palette SHALL offer Save readable 3md. Immutable snapshot preparation SHALL run away from the main actor and SHALL be cancellable. Document replacement SHALL invalidate obsolete preparation. The save panel SHALL use the prepared snapshot title and exactly the content type matching its encoded bytes. Only successful native writing SHALL mark that snapshot saved, and only in its original document generation. Later edits SHALL stay dirty. Preparation errors, cancellation and panel failure SHALL leave the saved baseline unchanged. Both formats SHALL reopen through the same user-selected native panel and bounded document codec.

Acceptance Criteria

- Prepared bytes decode to the captured snapshot even if the person edits afterward. Canceled work cannot publish an obsolete result. A save completed for an earlier document generation cannot mark a replacement saved. Native panels use .3mdb for compact and .3md for readable saving, and both reopen without losing cells or title.

### REQ-RookApp-008

For RENDER-29, Cubes on a Metal device SHALL use a prepared, bounded GPU scene. Camera orbit and zoom SHALL update camera pose without volume scanning, cube projection or bitmap rasterization. The mesh revision SHALL change only when voxel dimensions or layer bytes change, including changes caused by Undo, Redo or replacement. Metadata-only title edits and their Undo/Redo SHALL retain that revision while preserving ordinary dirty/save/Undo semantics; camera, slice and opacity SHALL NOT invalidate it. Document replacement SHALL change its generation identity independently of geometry cache reuse. Obsolete mesh preparation SHALL be canceled and SHALL NOT become the current scene. Selected-slice ghost cells SHALL remain bounded and pickable. Selection SHALL require the installed scene revision and camera to match the current presentation. A surface stroke SHALL retain its initial scene, camera and ghost targets until completion and SHALL defer edited mesh construction until then. ASCII and the non-Metal fallback SHALL remain available, and CPU export behavior SHALL remain unchanged.

Acceptance Criteria

- Repeated camera updates reuse the installed GPU geometry. Native solar orbit and zoom visibly respond while preserving the document. A face and an empty slice can still be painted, undone and selected at different camera poses. Timings distinguish optimized camera submission from actual GPU frame rendering; no unmeasured frame-rate claim is made.

### REQ-RookApp-012

For COMPOSITION-34, the main workspace SHALL open a selected reusable voxel leaf in the existing editor and provide explicit Apply Shared Edit and Cancel actions. Applying SHALL publish one validated source-graph Undo step and refresh affected geometry; canceling SHALL restore the exact reference workspace. Composition/world history and dirty baselines SHALL include model definitions. A shared edit SHALL not silently save a detached voxel file as the source scene.

Acceptance Criteria
- Two shared instances update together after Apply, and one Undo/Redo restores/reapplies the complete graph.
- Cancel returns to the reference workspace with no source changes.
- Invalid or stale edits retain the active edit for correction and never replace the source.
- Accessible control names identify the shared model and its scope; world Make Unique affects only the selected voxel instance.

### REQ-RookApp-013

For EXPORT-35, native Open and explicit portable text/binary export actions SHALL route the same voxel/composition/world scenes through the portable codec while keeping existing save defaults, cancellation, stale-parent checks, one-step shared-edit Undo and user-selected-file sandbox boundaries.

Acceptance Criteria
- Portable files reopen into the corresponding native editor without flattening shared definitions.
- Export prepares immutable snapshots away from the main actor and failed/cancelled output preserves the unsaved parent.
- Shared edits use upstream snapshot/revision semantics where representable, and explicit capacity feedback preserves legacy editing capability.
- Controls and errors remain accessible in the same app window.

### REQ-RookApp-014

For WORLD-37, the sparse-world editor SHALL provide Orbit and free Explore modes, focused-canvas WASD, drag-to-look and Q/E vertical travel, and a complete-world overview. Navigation SHALL preserve content, dirty state and Undo. Explore SHALL state that collision and gravity are absent.

Acceptance Criteria
- Mode switching and travel preserve saved content and editing history.
- Overview frames complete placement extent within existing capacity, disclosing omissions.
- Input only moves the focused canvas and stops on focus loss or removal.
- Exact distant coordinates remain exact and boundary overflow is refused.

### REQ-RookApp-084

The native composition and world editors SHALL offer Insert 3md for explicitly selected supported files or a bounded selected folder. They SHALL automatically remap and bind complete nested graphs and place models, atomically publishing one Undo with portable metadata preserved. Invalid inputs, fit/capacity, coordinate overflow and cancellation SHALL leave the parent unchanged. Source file access SHALL stay within the selected grants, without network or process use.

Acceptance Criteria
- Insert selected files places supported models without a separate binding step.
- Batch failures and cancellation leave parent and dirty/Undo values unchanged.
- Native file grants, bounded folder discovery, Undo and portable save/reopen are checked.

### REQ-RookApp-085

While a composition or world sheet can accept an insertion, the app SHALL offer Insert 3md and Insert model folder from the File menu with a keyboard shortcut, using the sheet's importer and rules. The command palette SHALL offer inserting files or a folder into a new composition or world, opening it and presenting its importer, and SHALL be unavailable while a sheet, save or open is in progress. Menu Undo and Redo SHALL act on the open sheet's history, or be unavailable, and SHALL NOT change the hidden main sculpture. Refusals SHALL name the file and the limit. Inserting, placing or moving at an unchanged focus in Explore SHALL keep the eye position. Example replacement SHALL clear stale portable data, Use in a world SHALL carry the composition's portable data, and labels SHALL show model titles rather than generated IDs. Select without painting, named overwrite confirmation, publish-nothing cancellation, one complete Undo and unavailable portable export and world handoff while pending SHALL remain.

Acceptance Criteria
- File menu entries present the open sheet's importer and are unavailable otherwise; palette entries open a new composition or world and present its importer.
- Menu Undo with an open sheet leaves the main sculpture unchanged.
- Explore insertion keeps the explorer offset when the focus is unchanged.

### REQ-RookApp-086

Opening a linked composition SHALL ask for its project folder, and cancelling SHALL open nothing. The folder grant SHALL live in memory for the session only, with no bookmark, no stored data beyond `rook.appearance` and no new entitlement, and the root SHALL lie inside the folder. Every linked read SHALL go through one confined reader that opens each path component without following symbolic links, accepts only regular files, refuses hidden components and hard-linked files, identifies files by device and inode, reads within the remaining budget, and holds the security scope until the detached resolution finishes or is cancelled. Reload Linked Files SHALL re-resolve on demand without a watcher, timer or polling; when it fails it SHALL keep the previous scene and name the file, and it SHALL NOT mark the session changed. When resolution fails at open, the root SHALL open in a repair view that lists each failing link with its file and reason, offers Reload and Choose Folder, and writes nothing. In this iteration a linked session SHALL be view-only: painting, insertion, shared-model Apply, Make Unique, world handoff and saving SHALL be unavailable with an explanation. Opening a self-contained bundle through ordinary Open SHALL need no folder and SHALL show a composition. Embedded insertion of a linked root SHALL be refused naming the file.

Acceptance Criteria
- In-process tests cover open with and without a folder, cancel, confinement refusals (symbolic link component, hidden component, hard link, root outside the folder), reload success and failure, the repair view and unavailable actions.
- One packaged sandboxed run opens a linked root whose children sit in nested folders.
- Opening a bundle needs no folder.

### REQ-RookApp-087

The Examples gallery SHALL list every catalog entry grouped by kind and category, showing each entry's size, without generating entries that are not opened. Opening an entry SHALL generate and prepare it in a detached task with a visible stage, progress and a Cancel action; cancelling SHALL leave the current document, selection and history unchanged. A voxel entry SHALL open in the main editor, a composition in the composition editor and a world in the world editor, through the same paths and unsaved-work protection as existing example opening. Previews of large entries SHALL be bounded and SHALL NOT block the gallery.

Acceptance Criteria
- In-process tests open a model, a composition and a world from the gallery, cancel a large entry while it loads, and confirm the current document and history are unchanged afterwards.
- Listing the gallery generates no large entry.

