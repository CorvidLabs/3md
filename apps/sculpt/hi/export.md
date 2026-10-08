---
hi: 1
families: [EXPORT]
---

# Export

## Intent

I want to save a sculpture and open that same file again, and to export text, a PNG, a looping turntable, or an occupied-cell mesh only to a file I choose.

If I cancel an export, I want the sculpture I am editing to stay as it is.

I want a compact native save and an explicit portable ThreeMD text or uncompressed binary copy, and I want either one to reopen as the same scene.

## Criteria

- **EXPORT-7**  I can save the sculpture as a 3md file and open that same file again.
- **EXPORT-8**  I can export the current view as text and as a PNG image.
- **EXPORT-13**  I can export a looping turntable of the sculpture as a GIF or an MP4.
- **EXPORT-14**  I can export the occupied voxels as an OBJ mesh.
- **EXPORT-15**  Export stays responsive, I can cancel it, and cancelling leaves the sculpture I am editing in place.
- **EXPORT-16**  I choose the export file in the native save panel, and the app writes it only because I chose it.
- **EXPORT-28**  Save writes a compact native .3mdb sculpture without blocking the editor, I can choose readable .3md instead, and either format reopens the same title and cells. Canceling or failing a save preserves unsaved edits; corrupted or unsupported compact files are refused. A local agent can inspect either format and write validated edits to a new file in the chosen format.
- **EXPORT-35**  I can explicitly export portable ThreeMD text or uncompressed binary and reopen the same sculpture, shared composition or sparse world. Shared definitions, rotations and exact distant coordinates survive. Shared edits use stable identities and revision checks; failed, stale or cancelled actions keep my current work. A local agent can inspect and apply the same edits to a new file with structured errors. Older Sculpt files and default saves remain usable, with clear feedback when a portable format has a smaller capacity.
