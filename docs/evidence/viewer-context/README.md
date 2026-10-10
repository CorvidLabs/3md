# Viewer canvas lifecycle repair

Leif reported repeated WebGL loss and ResizeObserver undelivered notifications. This repair coalesces observer drawing outside delivery, uses a visible-area Slice bitmap over a virtual scroll surface, and suspends WebGL allocation/drawing until restoration. Browser rendering only; native camera and editing source are unchanged.

## Verification

- Complete existing browser suite plus new regressions: 234 passed on Chromium/WebKit, 2 workers, no skips/retries (2026-10-10).
- New high-zoom regression uses a 64 by 64 empty grid at 16x, scrolls to cell (21,31), paints precisely and undoes to exact source; the bitmap remains within 2048 pixels per edge.
- Genuine WEBGL_lose_context regression on both engines issues 50 redraw requests plus Slice/viewport changes while lost, with no repeated context acquisition or bitmap resizing. Restoration reacquires once and preserves source, camera and selected slice.
- Existing 1x/2x small/large drawable and camera/picking regressions passed.
- Isolated in-app browser: unchanged starter at 16x shrank from 3840x3840 pixels to 609x242, retaining its 3840x3840 scroll surface. No warning/error logs during scroll and Fit/Slice changes.
- Strict viewer spec check passed without warnings. Repository Trust and provenance are recorded separately after their actual completion.

## Tested source

- `web/viewer.html` SHA-256: `a6465df1b34e130dddf9e076bb368a209727b79a18ff755919c8128d4d23f2fc`
- `uitests/viewer.spec.mjs` SHA-256: `b6ba0d3bbd343c78e5c846be183ca145433347105df844670ae473095da83762`

These are actual Codex test/visual observations, not human diff review or live deployment evidence.

## Repository gate and provenance

Pinned Fledge 1.7.2 / Trust 1.2.2 passed all eight verification steps, four strict specs with zero warnings and 55/55 source coverage. Augur returned proceed, risk 34. Actual unsigned agent:codex provenance was recorded for implementation d2e875e after the lane passed. The unchanged requireSignature and reviewer allow-list reject that record; progressive Trust reports this degradation. No trusted signature or human review is claimed. PR95 contains the repair. Acceptance/archive remains pending explicit closing review.
