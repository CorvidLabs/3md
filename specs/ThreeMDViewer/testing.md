---
spec: ThreeMDViewer.spec.md
---

## Automated Testing

| Test File | Type | What It Covers |
|-----------|------|----------------|
| `web/gather.test.ts` | bun | Section planes, pack, kind 2 round-trip, line plane index, search rank. |
| `web/github-source.test.ts` | bun | Repo, folder, file, and raw locators. Host and path routing. Issues URL rejected. |
| `web/open-document.test.ts` | bun | Text, composition, kind 1, kind 2, LZFSE refusal, linked folder. |
| `uitests/viewer.spec.mjs` | Playwright | Edit, Preview, Slice, and Cubes share one panel; full cube face pixels from all sides; glyph fill and gold edge selection; nearest slice picking; no camera/selection geometry uploads; about 1400 cubes; no console errors; narrow layout; kind 2, linked village, search, sections, composition; keyboard camera and slice controls; phone stage space; disclosure dismissal and both downloads; source shortcut focus; Preview empty state; GitHub busy/error recovery; GPU-unavailable guidance. |

## Requirement evidence

| ID | Canonical | Evidence |
| --- | --- | --- |
| REQ-ThreeMDViewer-001 | REQ-ThreeMDViewer-001 | VIEWER-6 in `hi/tools.md`. The page and the bun and Playwright tests above. |
| REQ-ThreeMDViewer-002 | REQ-ThreeMDViewer-002 | `web/github-source.ts` hostname checks, the 400 file and 1.5 MB caps, the 12,000 line cap in `web/viewer.html`, and the LZFSE test. |
| REQ-ThreeMDViewer-003 | REQ-ThreeMDViewer-003 | VIEWER-6 in `hi/tools.md`. Desktop and narrow layout tests in `uitests/viewer.spec.mjs`. |
| REQ-ThreeMDViewer-004 | REQ-ThreeMDViewer-004 | VIEWER-6 in `hi/tools.md`. `uitests/viewer.spec.mjs` opens the page and requires lit cubes inside the window, checks that the page does not autoplay, and draws about 1400 cubes on WebGL2. |

## Manual Testing

- [x] Run Sculpt locally, orbit Character orb in Cubes, and compare the same orb in the refreshed local viewer. Screenshots: `docs/evidence/viewer-sculpt-parity/`.
- [x] Inspect one-cell and starter sculptures for filled top, front, and side faces, visible edges, and pane framing.
- [x] Open `viewer.html`. On a wide window, files stay on the left and Edit, Preview, Slice, and Cubes switch in the panel beside them. On a narrow window, Files and the document take turns.

## Edge Cases & Boundary Conditions

| Scenario | Expected Behavior |
|----------|-------------------|
| Host name only appears inside the path or query | The locator is rejected. |
| Tree contains `node_modules` or a file over 1.5 MB | Those files are skipped. |
| More than 400 text files, or more than 12,000 lines | The list stops at the cap and says so. |
| Apple LZFSE bytes | The page refuses them and names `compressionUnavailable`. |
| Desktop width | Files stay visible while Edit, Preview, Slice, and Cubes switch. Preview shows the live plane view. |
| Width at or below 900px | Files and the document take turns. The document still switches Edit and Preview. |

## Continuing UI and UX verification

- The viewer suite exercises the new controls in Chromium and WebKit. Binary export is compared as parsed document fields and plane bodies because decoding returns canonical text. Camera direction assertions are independent of font-driven aspect-ratio changes.
- Live desktop dark, desktop light, Edit, and phone views are inspected and captured in `docs/evidence/viewer-ui/`. These are agent visual checks, not human approval.

## File navigation fix

The Chromium and WebKit viewer suite covers exact draft restoration, invalid and empty edits, the caret and slice, composition-entry independence, linked entry/file sharing, original-text edited markers, current-text download, search and pack, file filtering and keyboard selection, mobile document reveal, failed-open preservation, and stale source-query removal on navigation. Screenshots from live desktop and phone inspection are in `docs/evidence/viewer-navigation/`. These are agent checks and do not record human definition approval.

## Closure regression coverage

The file-draft test waits beyond the 160ms source-render debounce and checks that slice 1 survives before navigating. The phone keyboard test requires paths in alphabetical order before using End and Enter. The existing phone canvas, control separation, and overflow checks run unchanged at 390 by 844 and 320 by 740. The three original failures were reproduced and the targeted regression checks passed in Linux WebKit 1.61.1. The complete Linux hosted suite passed 190 tests with 8 existing skips in 2.1 minutes; the macOS viewer suite passed all 98 tests in 24.0 seconds. These are historical pre-closure results; the original viewer closure subsequently passed as recorded in the archived change.

Closure implementation checks: macOS viewer 98 passed; Linux hosted UI 190 passed and 8 existing skips; Bun helper suite 15 passed; strict SpecSync 4 specs passed with zero warnings and full configured coverage; Hi 85 criteria with no problems; pinned element bundle drift passed at 48840 bytes. Logs remain local under /private/tmp/3md-viewer-closure-*. These historical checks preceded the original viewer and camera archives. Current Slice/axis checks are listed below.

## Full camera parity

`uitests/viewer.spec.mjs` covers complete yaw/pitch turns, continuous poles, unchanged GPU geometry, modified mouse and explicit Pan, Shift-arrow pan, wheel bounds, two-finger pinch/pan, pointer cancellation, Fit without slice/source changes, and the shared native/browser projection/picking fixture. Native `CameraParityTests`, `SculptureLiveVoxelTests` and `SculptureCanvasPointerTests` check matching transforms, scalar/live picking and camera-only input. Existing math example regressions verify compatible utility framing. Current results and limits are recorded in `docs/evidence/viewer-camera/README.md`; final Trust and lifecycle evidence remain separate.

## Slice and precise camera parity

Slice uses the native character palette `#@*+ox:=-`, Draw/Erase square brushes 1/3/5, integer gap-free strokes and four-neighbor fill confined to the selected plane. Exact raw source offsets preserve all untouched bytes, including CRLF and prose. Eligibility requires complete, common rectangular grids, at most 64 by 64 cells, 256 planes, 4000 occupied cells and 1.5 MiB source. Empty grids can be edited. Rejected over-budget strokes restore the entire transaction.

History is shared with source typing and attached to each draft state, including linked entries. It retains at most 100 snapshots per draft and 8 MiB across the current collection; no-op strokes add no entry. Pointer up, cancellation, lost capture and navigation finish the accepted transaction. Thumbnails, one-based coordinates, keyboard arrows/Space, explicit cell Apply, previous-slice ghosts and Fit/2x/4x/8x/16x grid zoom use the same state. The live reference reparents the existing WebGL canvas rather than allocating another context; 2D editing remains available without WebGL. Phone layouts scroll inside Slice with full-size touch targets.

The volume camera shows colored X/Y/Z rings and Free/X/Y/Z constraints. A normalized quaternion composes document-axis rotation with continuous free orbit. Numerical rotation defaults to 15 degrees and pan to 0.25 cells, accepting only finite positive steps. Fit restores the default orientation and zero pan. Shared independent matrix-reference cases cover three-axis projection and picking; shared edit cases run through actual Sculpt workspaces and browser pointer gestures.


## Current approved Slice and precise-axis verification

2026-10-10: complete macOS UI 226 passed without skips or retries; Linux CI UI 218 passed with 8 existing platform-snapshot skips and no retries; configured native suite 637 passed and final parity selection 11 passed. Shared fixtures compare native workspace edits and actual browser gestures against independent expected rows and camera matrices. Logs and actual UI screenshots are in `docs/evidence/viewer-slice/`. Pinned Trust passed for implementation commit `8e9a0c4`; final archive-tip verification remains separate. Actual unsigned agent:codex provenance is recorded and does not satisfy the unchanged strict permitted-signature/reviewer policy.

Both current approved changes were successfully finalized and archived on 2026-10-10. Their supported scoped review records identify agent:codex. Scope authorization and agent verification do not claim independent human review or a permitted signature. Exact final archive-head Trust and remote CI status are reported in PR #93; the implementation and test fixtures are unchanged from `8e9a0c4`.

## Drawable resolution regression

At 1x and 2x density, exercise a phone-initialized canvas, small Slice reference, expanded Cubes stage and larger-than-cap desktop. Assert actual WebGL drawing-buffer dimensions match proportional 2048-edge/2x bounds, with one context, no context-loss events, no geometry allocations/uploads and unchanged pose/source/selection. Existing pixel/projection/nearest-picking checks continue on both engines.

2026-10-10: the post-resize full UI suite passed 230 tests; the final viewer suite including display-density listeners passed 130 tests; the final media-query/window-resize regressions passed 4 tests. No skips or retries. Actual browser bitmap/display measurements, screenshots, logs and implementation digests are in `docs/evidence/viewer-resolution/`; repository Trust and lifecycle verification remain separate. Native source is unchanged.

Pinned Trust passed at implementation `95c1213` with Augur review risk 36 and configured soft provenance degradation. Strict root specs passed at 55/55 files and Hi at 87 criteria. Actual unsigned Codex provenance was recorded after the lane passed; unchanged strict signature/reviewer policy rejects it. Evidence is in `docs/evidence/viewer-resolution/`. Later lifecycle metadata does not change the HTML or tests.

## Documentation examples

Verify README and guide links resolve to existing source examples, direct viewer links use supported GitHub locators for binary, and hosted docs expose the Viewer anchor with the existing styles. Parse both generated docs mirrors, require an identical VIEWER plane, and check that they remain equal. Check live example destinations and inspect the local hosted-docs section. The two current loader gaps are documented rather than claimed repaired.
