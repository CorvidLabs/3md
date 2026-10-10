# Viewer canvas lifecycle repair

Leif reported repeated WebGL loss and ResizeObserver undelivered notifications. This repair coalesces observer drawing outside delivery, uses a visible-area Slice bitmap over a virtual scroll surface, and suspends WebGL allocation/drawing until restoration. Browser rendering only; native camera and editing source are unchanged.

## Verification

- Complete existing browser suite plus new regressions: 234 passed on Chromium/WebKit, 2 workers, no skips/retries (2026-10-10).
- New high-zoom regression uses a 64 by 64 empty grid at 16x, scrolls to cell (21,31), paints precisely and undoes to exact source; the bitmap remains within 2048 pixels per edge.
- Genuine WEBGL_lose_context regression on both engines issues 50 redraw requests plus Slice/viewport changes while lost, with no repeated context acquisition or bitmap resizing. Restoration reacquires once and preserves source, camera and selected slice.
- Existing 1x/2x small/large drawable and camera/picking regressions passed.
- Isolated in-app browser: unchanged starter at 16x shrank from 3840x3840 pixels to 609x242, retaining its 3840x3840 scroll surface. No warning/error logs during scroll and Fit/Slice changes.
- Strict viewer spec check passed without warnings. Repository Trust and provenance are recorded separately after their actual completion.

## Initially tested source (234-test run)

- `web/viewer.html` SHA-256: `a6465df1b34e130dddf9e076bb368a209727b79a18ff755919c8128d4d23f2fc`
- `uitests/viewer.spec.mjs` SHA-256: `b6ba0d3bbd343c78e5c846be183ca145433347105df844670ae473095da83762`

These are actual Codex test/visual observations, not human diff review or live deployment evidence.

## Repository gate and provenance

Pinned Fledge 1.7.2 / Trust 1.2.2 passed all eight verification steps, four strict specs with zero warnings and 55/55 source coverage. Augur returned proceed, risk 34. Actual unsigned agent:codex provenance was recorded for implementation d2e875e after the lane passed. The unchanged requireSignature and reviewer allow-list reject that record; progressive Trust reports this degradation. No trusted signature or human review is claimed. PR95 contains the repair. Acceptance/archive remains pending explicit closing review.

## Expanded example and size coverage

Leif additionally requested multiple input types, examples and sizes. Four new browser tests passed in both Chromium and WebKit (8 checks):

- All 293 text catalog documents, spanning 48 axis values, open in Cubes, Slice and Preview without changing source or producing page/graphics errors. Nine qualify for the native-palette rectangular Slice editor; the other 284 show a nonempty explanation and retain readable Preview. This is not a claim that arbitrary Markdown is a sculpture.
- All four actual kind-1/kind-2 binary samples open through the file input. Shared-grove retains both embedded entries and each entry survives view changes with unchanged source.
- Desktop 1440x900 and phone 390x844 cover single and empty cells, 1x64 and 64x1, exactly 4000 occupied cells, 4096 cells, 65-row/column refusal, 256 and 257 planes, and source exceeding 1.5 MiB. Source remains readable; Slice explains its supported bounds and Cubes retains its 4000-cell cap.
- An actual local LinkedVillage folder resolves four entries and preserves each independently edited draft after switching entries.

An isolated built-site viewer opened the live public GitHub Examples folder (307 files), then its kind-2 canopy binary (two planes, six cubes), with Slice and the 3D reference visible and no warning/error logs. Screenshot: `github-binary.jpg`. This verifies public folder and binary navigation, not deployment. Existing GitHub linked-composition/root-only and direct non-GitHub binary URL gaps remain documented in `docs/VIEWER.md`; browser LZFSE and Sculpt compact saves remain unsupported.

The renderer remains byte-identical to implementation d2e875e. The expanded test file SHA-256 is `0c35ca8f3b8af09cde3b25a06450e1835c1b5373c19d018f360734f03cc32770`.

The complete expanded suite passed all 242 tests on Chromium/WebKit with two workers in 2.7 minutes, without skips or retries, on 2026-10-10. Runtime bytes remain unchanged from d2e875e; the source hashes above distinguish the original test set from this expanded test set.
