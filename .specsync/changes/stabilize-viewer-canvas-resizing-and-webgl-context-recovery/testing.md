---
change: stabilize-viewer-canvas-resizing-and-webgl-context-recovery
artifact: testing
---

# Testing

Exercise Fit/16x, scroll and selected-cell painting/undo; rapid Slice/Cubes and phone/desktop transitions; assert bounded bitmap dimensions and no ResizeObserver errors. Force a genuine loss via WEBGL_lose_context, issue repeated redraws and resize/view changes, restore and assert one initialization, valid WebGL drawing, unchanged source/camera/slice. Keep existing camera/projection and mesh reuse regressions. Browser visual QA uses an isolated tab, preserving user drafts.

## Requirement evidence

| ID | Canonical | Evidence |
| --- | --- | --- |
| REQ-ThreeMDViewer-004 | REQ-ThreeMDViewer-004 | uitests/viewer.spec.mjs genuine loss/restoration, bounded high-zoom scrolled-cell edit/undo and existing drawable/camera/picking tests: initially 234 passed; expanded complete suite 242 passed with no skips or retries. Actual source hashes, bitmap measurements, Trust and provenance limits are recorded in docs/evidence/viewer-context/README.md. |

## Expanded viewer coverage

The viewer suite now visits all 293 text examples across 48 axes through Cubes, Slice and Preview, opens all four binary samples through file input, retains embedded entries, and verifies four linked local-folder drafts. Desktop and phone boundary cases cover empty/single cells, 64-cell skinny grids, 4000/4096 occupied cells, 64/65 grid edges, 256/257 planes and the 1.5 MiB source limit. Unsupported Slice grids explain their refusal while preserving source and Preview. Details and actual live GitHub-folder/binary observations are in `docs/evidence/viewer-context/README.md`.

Safari follow-up: reproduce null/already-lost startup contexts before loss-event delivery, 256 redraws, safe null resource creation, and genuine early loss/restoration. Verify actual Safari alongside Playwright; record the independent native observations and the unresolved hardware cause honestly.

2026-10-10 Safari follow-up verification: complete Chromium/WebKit suite 256 passed without retries or skips (2 workers, 2.8 minutes), followed by the additional genuine early-loss test passing in both engines (2 checks). Native Safari 26.5.2 independently held at one context request while lost, retained Slice erase/Undo, and rebuilt exactly once after restoration. See docs/evidence/viewer-context/README.md for the proof boundaries.

## Linux CI gesture readiness

Main UI runs 38086816399 and 38090326009 exposed synthetic Slice gestures measuring stale/empty metadata or using clipped bitmap bounds before queued drawing. Wait for rendered ARIA grid dimensions and two animation frames, then measure cell centers on the full virtual scroll surface in one browser evaluation. Keep the existing exact source, CRLF/download, Undo/history, cancellation, touch navigation and phone assertions; do not add retries or relax expectations.

On Ubuntu Noble ARM64 with Playwright 1.61.1, the unmodified main helper failed 2 of 30 focused Chromium checks. The repaired helper passed 90 repeated checks with two workers and no retries. The full macOS Chromium/WebKit suite passed 258 checks in 2.6 minutes with two workers and no retries or skips. Full suite receipts are recorded in docs/evidence/viewer-context/README.md; exact-head hosted CI is reported on the follow-up PR. Local ARM64 Docker is not the hosted x86_64 runner.

Full Linux Chromium/WebKit verification passed 250 checks in 6.5 minutes with two workers and no retries; the eight existing CI image-snapshot skips remain unchanged. Playwright 1.61.1 ran in the official Ubuntu Noble ARM64 container with CI=1. The complete macOS suite passed all 258 checks in 2.6 minutes without retries or skips. All 293 catalog documents across 48 axes, local binary/composition/folder inputs, source/history and desktop/phone boundaries remain covered.
