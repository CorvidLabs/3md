# Insert 3md in Sculpt

Insertion is in the current app. [Direct insertion](evidence/file-insertion/README.md) and [discoverability](evidence/insertion-discoverability/README.md) record those slices. This page describes the behavior.

## Finding Insert

While a composition or world sheet is open and idle, the File menu offers Insert 3md… (Shift-Command-I) and Insert model folder… (Option-Shift-Command-I). The sheets show the same two buttons. From the main window, the command palette (Command-K) and the in-window File menu offer Insert 3md into a new composition or a new world; those actions open a blank canvas (for a composition, a 4 by 4 by 4 grid of 64-cell tiles) and present the file chooser, and are unavailable while another sheet, save or open is in progress. Menu Undo and Redo act on the open composition, world or shared-model history, so the hidden main sculpture never changes while a sheet is open; they are unavailable while a shared-model edit is applying.

## What can be inserted

Insert 3md accepts one or more user-selected spatial files, and Insert model folder accepts a bounded collection. Supported children are Sculpt voxel documents and reusable tile compositions, including their portable ThreeMD copies. A whole sparse world cannot be one reusable child glyph. Arbitrary Markdown ThreeMD documents have no spatial rendering adapter. Both are refused with the file name, not converted.

## Placement

Insertion automatically namespaces the imported model graph, retains sharing within it and places the models in natural filename order (model2 before model10). Compositions use consecutive row-major cells beginning at the selected cell and keep their current tile size. Select chooses that start without painting or registering Undo. A batch that would replace occupied tiles requires a confirmation that names each replaced tile; cancellation or a changed parent discards the candidate. After a successful insertion an accessible status line names the first and last tiles and says when the batch continued onto the next row or into another layer. Worlds place the first model at the exact focus, then along positive X with a one-cell gap; checked Int64 overflow refuses the batch. In Explore, inserting at an unchanged focus keeps the eye where it is. Edit shared model menus, library rows and world instance labels show model titles and dimensions; generated model and instance IDs stay internal.

## Checks and refusals

File count, free cells, binding characters, model and placement counts, tile fit, the 20 MiB aggregate source size and the 64 MiB combined model volume are checked before files are decoded where possible: every file size is admitted first, and compact files are measured from their headers. Per-file refusals name the file and the limit, for example the tile size a model needs; batch count, cell and character refusals name the limit. Preparation runs away from the main actor and publishes one validated result. Cancel, malformed input, an unsupported child, capacity or coordinate failure leaves the scene, dirty state and Undo intact, and a changed scene, focus or portable snapshot refuses a prepared result. One Undo/Redo restores the complete graph and portable metadata. Portable export and Use in a world are unavailable while an insertion is preparing or awaiting confirmation.

## Portable data and native storage

Portable snapshots retain incoming plane identities, reference identities and order, and opaque metadata and attributes. Reference attributes are matched by glyph and target, and untitled nested definitions stay untitled. Use in a world carries the composition's portable data. Replacing a composition with an example clears portable data that belonged to the replaced document, and Undo restores it.

Insertion first prepares a complete portable result, which must fit the upstream 16 MiB canonical-definition limit and the 20 MiB file limit. When that limit refuses and neither the open scene nor any input carries portable data the person actually has, insertion uses native Sculpt values instead (snapshots Sculpt generated itself from native values do not count), so large native models such as the 256-cubed solar system can still be inserted; a notice says so. When portable data would be lost, insertion names the limit and the affected files and inserts nothing.

Native composition and world encoding applies the same 100,000-line and 20 MiB budget that native decoding uses. An insertion or save that could not reopen is refused before anything is written, so every accepted native save reopens. Existing native formats and default saves are unchanged. Saving a portable copy makes the imported graph self-contained, so the selected source files are no longer needed.

## Privacy

Files are read only under user-selected grants. Folder discovery skips hidden files, packages and symbolic links, propagates discovery errors and caps 4,096 entries, 64 source files and the aggregate source byte limit. Source reads use nonblocking regular-file descriptors and refuse symlinks. The app does not start a process, use a network or follow a sibling path from a single-file grant.

## Agent tools

Local agents can apply the same insertion checks to explicitly chosen files with `RookTool sculpture portable insert` and `RookTool sculpture reference insert`. Both write a new output file and never control the running app. See [agent commands](../Examples/agent-commands.md).

## Linked authoring versus embedded insertion

The native Insert action embeds supported spatial files; it is not a live filesystem link or background watcher. Linked compositions, which use ThreeMD 2.0.0's `3md-files` ledger, are described in [Linked compositions](linked-composition.md). Embedded Insert refuses a linked root and names the file; open it and choose its project folder instead.

No default file migration, new storage schema, or new entitlement belongs to this feature.
