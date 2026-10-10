# Shared 3D drawable resolution repair

Leif reported a blurry Cubes stage after Slice/camera work. Actual in-app WebKit measurement found a 368x322 drawing bitmap displayed at 1099x911 at density 1. The previous Safari workaround froze bitmap dimensions after context creation; expanding the small reference/phone view stretched that bitmap.

The fix updates only changed drawable dimensions, retains the existing context/program/geometry and redraws the current camera. The proportional 2048-edge and 2x density limits remain. Window resize and a rearmed resolution media query cover display changes, including density changes without a CSS-size change. No native source, format, camera convention or storage behavior changes.

## Verification

- Complete macOS Chromium/WebKit UI after the resize repair: 230 passed, no skips or retries (`browser-full.log`). This preceded the final density-change listeners.
- Complete final viewer suite after the density-change listeners: 130 passed, no skips or retries (`viewer-final.log`).
- Final density regressions, including the rearmed media-query callback and window-resize fallback: 4 passed, no skips or retries (`density-final.log`).
- At initial 1x/2x density, the new tests cover phone-to-desktop, small Slice reference, expanded Cubes, repeated view switches and larger-than-cap layouts. They compare actual WebGL drawing-buffer dimensions, retain one context/program with zero losses or geometry uploads/allocations, and preserve source, selected plane and pose. Existing projection, nearest picking and GPU pixel tests passed in the viewer suite.
- Actual user draft was preserved in its original tab. A separate preview copied its current 134-cell source. At the same 1099x911 displayed size, the repaired bitmap measured 1099x911 with WebGL2 active. The small reference measured 199x170 and the expanded stage 990x333, each matching its bitmap. Actual before/after frames are `browser-before.png` and `browser-after.png`; the before/after camera framing differs, so this is resolution evidence rather than a pixel-equality comparison.

Native behavior was already verified in `../viewer-slice/`; it is unchanged by this repair. Repository Trust and lifecycle results are recorded separately after the implementation commit. Agent verification does not claim Leif reviewed this diff, independent human review or a permitted signature. Existing Trust/provenance policy remains unchanged.

## Verified implementation content

- `web/viewer.html`: `d5c226e7ccb6b46c7e462c6d72a89772138080dce9269f0813cd0979d10116b8`
- `uitests/viewer.spec.mjs`: `59894ffd439caff704f34d3fba39425e991f854fcfe83a73aca673b0883c1c97`
