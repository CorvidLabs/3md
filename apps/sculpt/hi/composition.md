---
hi: 1
families: [COMPOSITION]
---

# Composition

## Intent

I want one character in a tile map to place a reusable 3md model, including a model made of other models, and I want one edit of a shared model to reach every instance.

I want to insert models I choose into a composition or world, and I want a linked composition to resolve the files in a project folder I choose.

## Criteria

- **COMPOSITION-30**  One character in a visual tile map can place an entire reusable 3md model, including a model composed of other models. Saving and reopening a self-contained composition preserves its shared model bindings and rotations. I can explicitly open an expanded voxel copy for painting and export. Missing models, circular references, excessive expansion and out-of-bounds models are refused without changing my current sculpture.
- **COMPOSITION-34**  I can edit a shared voxel model inside its composition or world, apply that edit to every instance or cancel without changing the source, and undo the complete graph change in one step. I can make one world voxel instance unique without changing other instances. A local agent can apply the same validated reference-preserving edits to a new chosen output file. Existing file formats and app privacy stay intact.
- **COMPOSITION-38**  I can insert selected 3md models or a bounded model folder directly into a composition or world, with automatic nested bindings and placement. The batch is one Undo, portable copies preserve imported identities and annotations, and failure or cancellation leaves my current work intact. Existing native formats and privacy remain.
- **COMPOSITION-39**  I can find Insert 3md and Insert model folder from the File menu or a keyboard shortcut while a composition or world is open, or start a new composition or world with them from the command palette, and menu Undo changes only what I am editing. Insertions and saves I am allowed to make always reopen; large native models still insert when no portable annotations would be lost, and refusals name the file or the limit. A local agent can insert chosen files into a new output file with the same insertion checks, without controlling the app.
- **COMPOSITION-40**  I can open or start a linked composition inside a project folder I choose, insert a model file from that folder as one character, and see shared models resolved from their files. Reload picks up changes; missing, circular, invalid or oversized links are refused naming the file, without changing my work or any file I did not save. I can export a self-contained bundle as readable 3md or uncompressed binary and reopen it without the folder. Existing Sculpt files, formats and saves are unchanged.
