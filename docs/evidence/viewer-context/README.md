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

## Safari startup follow-up (2026-10-10)

The observations and source pin above describe the merged PR95 repair. Safari 26.5.2 still reproduced 256 `WebGL: context lost` console errors at the public viewer. The existing loss-event handler was insufficient when context creation failed or returned an already-lost context before the event reached the app. A controlled pre-fix test made 263 context requests during 256 redraws. The underlying intermittent Safari/GPU loss cause has not been established; subsequent fresh public loads also succeeded.

The follow-up latches failure/loss directly during initialization and drawing, refuses null shader/program/vertex-array/buffer handles, and clears the loss latch only on actual restoration. No shader, camera, native app, file-format or loader behavior changed. A failed unavailable context makes one request for the page lifetime; a lost context resumes after restoration. Slice and Preview remain available while graphics are paused.

- Complete browser suite: 256 passed on Chromium/WebKit, two workers, 2.8 minutes, no skips or retries. This includes all 293 text examples, binary/composition/folder inputs, size bounds and existing camera/picking/edit checks.
- A subsequently added genuine early-loss test passed in both engines (2 checks). It suppresses the app's loss-event delivery, forces a real loss via `WEBGL_lose_context`, issues 256 redraws, then restores: one initial request, one rebuild, exact source/camera/slice retained and no GPU errors after restoration.
- Native Safari 26.5.2 independently tested the same genuine startup-loss harness. While lost: one context request and zero draws. Slice erasure reduced the cube count 122 to 121; Undo restored 122 without another context request. After explicit graphics restoration: two total requests, one draw, one loss and one restoration, with the WebGL2 reference visible. Screenshot: [safari-startup-restored.png](safari-startup-restored.png). The diagnostic footer and restore button exist only in the temporary harness.
- Null startup context and already-lost startup context each stay at one request through 256 redraws, Slice, phone resizing, 16x and Expand. All five null GPU-resource cases stop safely with Slice/Preview usable and source preserved.

Tested `web/viewer.html` SHA-256: `591ab297de99f35198abf1214490e6be8c211e553d192d315bc8ef0ec85a16fa`. Tested `uitests/viewer.spec.mjs` SHA-256: `ca0222441f219e230f8571d389c66430e35d33ce21c4b198812989332524dbff`. Native observations supplement the automated WebKit checks; they do not prove every Safari device or the deployed public revision. Current repository-gate/provenance outcomes are reported separately after the actual gates run. No human diff review, trusted signature or lifecycle closure is claimed for this follow-up.

## Main UI CI follow-up (2026-10-10)

After PR96 merged at ff547d72e4ca14ffa2f103f9f0c260efca70d8a2, [main UI run 38090326009](https://github.com/CorvidLabs/3md/actions/runs/38090326009) failed the touch-stroke/navigation assertion and retried a wrong-cell CRLF edit. [Previous main UI run 38086816399](https://github.com/CorvidLabs/3md/actions/runs/38086816399) also exposed empty metadata and missed first edits. Other current main workflows passed.

The synthetic gesture helpers measured before the deferred Slice redraw completed and treated the clipped canvas bitmap as the complete grid. The repair waits for rendered ARIA grid dimensions and queued drawing/layout frames, then measures cell centers on the full virtual scroll surface. Exact source, CRLF/download, Undo/history, cancellation, touch navigation and phone assertions remain unchanged. No retry, timeout, skip, runtime, camera, parser, format, dependency or trust-policy change is included. The site already imported the merged Safari repair; this test-only follow-up needs no site import.

- Unmodified main on Linux: 2 failures / 28 passes in 30 focused Chromium checks, two workers and no retries; missed touch edits reproduce the hosted failure.
- Repaired helpers on Linux: 90/90 repeated focused Chromium checks passed, two workers and no retries.
- Complete Linux suite: 250 passed, eight existing CI image-snapshot skips, two workers, no retries, 6.5 minutes. Official Playwright 1.61.1 Ubuntu Noble ARM64 container with CI=1; this is not the hosted x86_64 runner.
- Complete macOS suite: 258 passed, two workers, no retries or skips, 2.6 minutes.
- Both complete suites retain all 293 catalog documents across 48 axes, actual binary/composition/folder inputs, desktop/phone size limits, Slice edits/history, camera/picking and startup loss/restoration coverage. Exact-head hosted CI is reported on the follow-up PR after it runs.

Unchanged `web/viewer.html` SHA-256: `591ab297de99f35198abf1214490e6be8c211e553d192d315bc8ef0ec85a16fa`. Tested `uitests/viewer.spec.mjs` SHA-256: `c318d3f046da23036803c7543ac52e48057558cfeea58f38277f6e449ca40d64`. Repository-gate and actual unsigned Codex provenance outcomes are reported separately after those steps run. These receipts do not claim human diff review, trusted signatures, main CI completion for this unmerged branch, or lifecycle acceptance/archive.
