# Slice and camera parity evidence

The browser Slice workspace follows Sculpt’s Draw/Erase/Fill, palette and square brush behavior. Shared `slice-parity.json` cases use independently stated expected rows and run through real native workspaces and browser pointer gestures. The cases cover sparse diagonal and horizontal strokes, unchanged starts, repeated points, asymmetric 9×7×5 slices, size-3/5 edge clipping, erase, four-neighbor boundaries, untouched planes and no-op history. Camera cases in `../viewer-camera/camera-parity.json` use an independent rotation-matrix reference, including X/Y/Z, negative steps, mixed sequences, inverse steps and full turns. Actual GPU projection and nearest picking are compared with those values; native scalar/live picking and ASCII Z picking are also checked.

Verified locally on 2026-10-10:

- Full macOS Chromium/WebKit UI suite: 226 passed, no skips or retries (`mac-browser.log`).
- Final expanded shared browser fixtures: 4 passed (`browser-fixtures.log`).
- Final phone regressions at 390×844 and 320×740: 4 passed (`phone.log`).
- Configured native regression selection: 637 tests in 54 suites passed (`native-full.log`), using the existing `--skip deterministicPortableInterchangeFixtures` selection. The previously established release-fixture/version mismatch remains outside this UI change; no new skip was introduced.
- Final native camera, live picking/mesh reuse and expanded Slice fixture selection: 11 passed (`native-parity.log`). This includes the independent ASCII Z-picking test added after the broad suite; implementation did not change afterwards.
- Strict root and nested app specs passed with complete configured coverage. Hi criteria are unique and generated intent indexes are current.

Visual evidence uses the actual browser and an isolated source-built Sculpt preview: `browser-desktop.png`, `browser-phone.png`, and `sculpt-axis.png`. This is agent visual verification, not Leif’s implementation diff review or an independent human approval.

Slice preserves raw non-target text, including CRLF, fractional plane positions, labels and prose; exported text and kind 2 use the current draft. History is bounded to 100 snapshots per draft and 8 MiB across the current collection. Over-budget transactions roll back completely, and late pointer events cannot edit a newly activated file. One WebGL canvas is shared with the live reference. Source editing and 2D Slice remain available without WebGL.

The browser’s supported edit profile is complete common rectangular grids up to 64×64, 256 planes, 4000 occupied cells and 1.5 MiB source, with the native palette and dot/space empties. Structural slice actions, volume resizing and browser 3D painting remain subsequent work. Native storage, formats, library APIs, examples, generated browser bundles and releases are unchanged.

Linux, final Trust and lifecycle receipts are recorded after their current runs complete. Actual reviewer identity is agent:codex. Scope and conditional verified closure were directly authorized by Leif; that does not supply a permitted signature or a human diff review. Existing soft unsigned provenance policy remains intact.
