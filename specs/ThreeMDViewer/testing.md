---
spec: ThreeMDViewer.spec.md
---

## Automated Testing

| Test File | Type | What It Covers |
|-----------|------|----------------|
| `web/gather.test.ts` | bun | Section planes, pack, kind 2 round-trip, line plane index, search rank. |
| `web/github-source.test.ts` | bun | Repo, folder, file, and raw locators. Host and path routing. Issues URL rejected. |
| `web/open-document.test.ts` | bun | Text, composition, kind 1, kind 2, LZFSE refusal, linked folder. |
| `uitests/viewer.spec.mjs` | Playwright | Edit, Preview, and Cubes share one panel; full cube face pixels from all sides; glyph fill and gold edge selection; nearest slice picking; no camera/selection geometry uploads; about 1400 cubes; no console errors; narrow layout; kind 2, linked village, search, sections, composition; keyboard camera and slice controls; phone stage space; disclosure dismissal and both downloads; source shortcut focus; Preview empty state; GitHub busy/error recovery; GPU-unavailable guidance. |

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
- [x] Open `viewer.html`. On a wide window, files stay on the left and Edit, Preview, and Cubes switch in the panel beside them. On a narrow window, Files and the document take turns.

## Edge Cases & Boundary Conditions

| Scenario | Expected Behavior |
|----------|-------------------|
| Host name only appears inside the path or query | The locator is rejected. |
| Tree contains `node_modules` or a file over 1.5 MB | Those files are skipped. |
| More than 400 text files, or more than 12,000 lines | The list stops at the cap and says so. |
| Apple LZFSE bytes | The page refuses them and names `compressionUnavailable`. |
| Desktop width | Files stay visible while Edit, Preview, and Cubes switch. Preview shows the live plane view. |
| Width at or below 900px | Files and the document take turns. The document still switches Edit and Preview. |

## Continuing UI and UX verification

- The viewer suite exercises the new controls in Chromium and WebKit. Binary export is compared as parsed document fields and plane bodies because decoding returns canonical text. Camera direction assertions are independent of font-driven aspect-ratio changes.
- Live desktop dark, desktop light, Edit, and phone views are inspected and captured in `docs/evidence/viewer-ui/`. These are agent visual checks, not human approval.

## File navigation fix

The Chromium and WebKit viewer suite covers exact draft restoration, invalid and empty edits, the caret and slice, composition-entry independence, linked entry/file sharing, original-text edited markers, current-text download, search and pack, file filtering and keyboard selection, mobile document reveal, failed-open preservation, and stale source-query removal on navigation. Screenshots from live desktop and phone inspection are in `docs/evidence/viewer-navigation/`. These are agent checks and do not record human definition approval.

## Closure regression coverage

The file-draft test waits beyond the 160ms source-render debounce and checks that slice 1 survives before navigating. The phone keyboard test requires paths in alphabetical order before using End and Enter. The existing phone canvas, control separation, and overflow checks run unchanged at 390 by 844 and 320 by 740. The three original failures were reproduced and the targeted regression checks passed in Linux WebKit 1.61.1. The complete Linux hosted suite passed 190 tests with 8 existing skips in 2.1 minutes; the macOS viewer suite passed all 98 tests in 24.0 seconds. Targeted lifecycle verification, pinned Trust, and closure remain pending.

Closure implementation checks: macOS viewer 98 passed; Linux hosted UI 190 passed and 8 existing skips; Bun helper suite 15 passed; strict SpecSync 4 specs passed with zero warnings and full configured coverage; Hi 85 criteria with no problems; pinned element bundle drift passed at 48840 bytes. Logs remain local under /private/tmp/3md-viewer-closure-*. The Trust and SpecSync closing gates are still pending.

## Full camera parity

`uitests/viewer.spec.mjs` covers complete yaw/pitch turns, continuous poles, unchanged GPU geometry, modified mouse and explicit Pan, Shift-arrow pan, wheel bounds, two-finger pinch/pan, pointer cancellation, Fit without slice/source changes, and the shared native/browser projection/picking fixture. Native `CameraParityTests`, `SculptureLiveVoxelTests` and `SculptureCanvasPointerTests` check matching transforms, scalar/live picking and camera-only input. Existing math example regressions verify compatible utility framing. Current results and limits are recorded in `docs/evidence/viewer-camera/README.md`; final Trust and lifecycle evidence remain separate.
