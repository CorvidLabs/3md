# Verification

The 2026-10-04 cleanup retains a native main window, Settings, and a menu bar. The app was built from a reset Swift build directory with no external package dependencies and packaged with the app sandbox enabled. No SpecSync diff review or finalization is claimed.

`hi check` and `specsync check --strict` are structural. They do not run the product tests. The guarded test command is `RookTool test`. Packaging is `RookTool package`.

The guarded suite passed all 32 retained Swift tests. The receipt and raw log are at `/private/tmp/rook-base-cleanup-test-evidence/`. These cover appearance fallback, product/development source and dependency boundaries, resource-free bundle packaging safety, and rejection of incomplete or misleading test runs. Product fixes after this first run are checked again in the final verification receipt.

The final `/opt/homebrew/bin/fledge lanes run verify` passed all seven steps: format, guarded test harness (29 tests), guarded complete suite (32 tests), hi, strict spec-sync, product boundaries, and release fixture scan. The complete suite receipt and raw log are retained unchanged in `docs/evidence/base-mac-app/`, copied from `.build/verification/C6C34413-7CD5-49E9-9EAB-77589564DA8C/`. The receipt preserves the original run paths. Strict spec-sync reports 3 passing specs, no warnings, and 100% source coverage (13/13 files).

Native interaction with the packaged app confirmed the main window and its Settings button, System/Light/Dark choices, and a single Rook entry in the Window menu. Visual inspection found and fixed a background sizing issue. Closing the main window initially quit the process; the app delegate now prevents that. Process 93041 survived the close/reopen check unchanged. The computer-use observer reactivates the app when reading its accessibility tree, so this is process-lifetime evidence, not proof of a click on the menu-bar-extra icon. That icon's click path was not separately exercised. VoiceOver was not run.

Old feature docs and screenshot assets are removed from the checkout and remain recoverable from commit `d274d9d91f8a82d989c118a38720234b194964a6` on `leif/unified-launcher-home`. Retired specs remain under `historical/specs/`; 53 retired hi criteria reserve their original IDs. `.specsync/archive/` was not rewritten. Open feature changes were not marked reviewed or finalized.

On 2026-10-07 the nine retired launcher hi files were deleted: `access`, `action`, `applet`, `extend`, `file`, `launch`, `notebook`, `privacy`, and `pro`. Their ids are no longer reserved in the checkout. Git history keeps the text. At that deletion, active criteria were in `hi/local.md`, `hi/sculpture.md`, and `hi/shell.md`. `historical/specs/` and `.specsync/archive/` were left as they were. Past lane receipts that report 53 retired criteria keep the counts those runs recorded. This note is `grok-build` recording Leif's direct request. It is not Leif's diff review.

The same day, the sculpture criteria moved into one file per concern and kept their numbers. `hi/sculpture.md` no longer holds every SCULPTURE id. Slice, cubes, export, gallery, render, composition, and world each have their own family.

The game/editor experiments and copied paid artwork were moved out of their active scratch paths to `/private/tmp/rook-paused-experiments-2026-10-04/`. This is temporary recoverable storage. Original assets and the Godot project under Peck were not changed. Saved notes, notebooks, intake answers, and Library containers were not changed.

## ASCII sculpture

The receipts above cover the reset app only. They do not cover RookSculpture, RookRendering, or the editor.

Codex reported an initial guarded suite of 49 passed tests, including an offscreen real-Metal visible-glyph assertion. grok-build did not run that suite and did not add a receipt for it. Codex also inspected a running app at 940 by 682 in dark appearance: the orbit slider and painting worked, and the unsaved-quit and open-discard warnings worked. Codex's save at `/private/tmp/rook-sculpture-roundtrip-20261004.3md` was 5126 bytes and reopened as 608 characters. A preview tap selected cell 11, 5 on slice 13. The exported PNG was 576 by 648 and the exported ASCII text was 36 lines. Those observations are Codex tool reports, not a human diff review. The retained copies are `docs/evidence/ascii-sculpture/native-roundtrip.3md`, `native-export.png`, and `native-export.txt`. The menu-bar extra was not clicked. VoiceOver was not run.

Codex subsequently completed all seven steps of the pinned verify lane, including 49 complete-suite tests and the 29-test harness. Product sources and tests were unchanged afterward. Retained receipts, native observations, and verification limits are in [the sculpture verification notes](evidence/ascii-sculpture/verification-notes.md). grok-build had corrected formatting and the strict contracts; it did not run the product tests. Strict spec-sync reports 5 passing specs, no warnings, and 21/21 source files. CI, publication, and lifecycle require their own evidence. The contract is in `docs/ascii-sculpture.md`.
