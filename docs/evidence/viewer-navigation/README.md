# Viewer file navigation verification

Agent inspection on 2026-10-10, after PR 92 merged. The local viewer served this fix branch at `http://127.0.0.1:8234/viewer.html`.

- `desktop.jpg`: opened a folder containing the public Character orb and the viewer starter, edited the starter title and glyphs, switched to the orb and back, and inspected the preserved draft in Cubes. The filename, Edited marker, file indicator, and selected walls slice are visible.
- `phone.jpg`: the same edited document at 390 by 844. The title, source filename, Edited marker, camera controls, and plane outline leave room for the cube stage.
- `phone-files.jpg`: filtered the opened files on the phone. The matching file keeps its path and edited indicator. Choosing it reveals the document and focuses its current view. The temporary viewport was reset after inspection.

These are live browser screenshots and agent visual checks. They are not human review or SpecSync definition approval. Drafts are held only in memory for the current collection; refreshing or opening another collection clears them. Download exports the selected document and does not overwrite a local or GitHub source file. Composition profiles are not rewritten when an entry is edited.

The viewer regression suite covers file and composition draft restoration, linked file/entry sharing, invalid and empty drafts, caret and slice restoration, edited markers, current-text download, search and packing, filtered keyboard file selection, phone document reveal, failed-open preservation, and current-document reload URLs. Existing cube, context, export, editor, and accessibility checks also remain in the suite. See the PR for the exact commit's test and Trust results.

## Approval and Linux regression follow-up (2026-10-10)

Leif approved final viewer scope and authorized acceptance and archiving after successful verification. The original PR 93 UI run failed three Linux WebKit tests; all three reproduced locally. Delayed editor rendering now retains the selected slice, the file list sorts paths to make native directory ordering consistent for keyboard navigation, and small-phone spacing leaves more drawing room. Existing assertions remain; draft restoration explicitly crosses the editor debounce and the file test asserts path order.

- macOS Chromium/WebKit viewer suite: 98 passed (24.0 seconds).
- Linux complete hosted UI suite, matching Playwright 1.61.1 environment: 190 passed, 8 existing skips (2.1 minutes).
- Bun helpers: 15 passed. Strict specs: 4 passed, zero warnings, 55/55 files and 21185/21185 configured LOC. Hi: 85 criteria, no problems. Element bundle drift: current at 48840 bytes.

These are implementation verification results. Targeted SpecSync verification, pinned Trust, provenance, acceptance, and archiving remain pending at this checkpoint. Approval was recorded after the earlier draft implementation; it is not backdated and does not claim independent human diff review or signed provenance.
