# Lesson bundle — repair-blurry-cubes-and-slice-canvases-after-view-and-display-size-changes-while-retaining-the-webgl-context-and-camera

Material for folding this change's lessons into the affected specs' `context.md`.
Synthesise from what actually happened below; do not restate the change description.

## What this change was

- **Title**: Repair blurry Cubes and Slice canvases after view and display-size changes while retaining the WebGL context and camera parity
- **Kind**: BugFix
- **Specs**: ThreeMDViewer
- **Paths**: web/viewer.html, uitests/viewer.spec.mjs, specs/ThreeMDViewer, docs/evidence/viewer-resolution
- **Acceptance**: The shared 3D canvas drawing buffer follows the displayed Cubes or Slice-reference size and device pixel ratio within the existing 2048-edge/2x limits; switching from a small reference or phone viewport to a large stage remains sharp; resizing retains the same WebGL context, geometry and camera/source/selection; Chromium, WebKit and the actual in-app browser verify transitions and picking.

## Evidence

- Verification commit: `57a2db9ac4e98000a36aa9660df39e74aa21e17b`
- Base commit: `dab4258541208f8bf6bb5a38f6200a5b348a858e`
- Verified by: `specsync check --spec ThreeMDViewer --strict`

## From the change's context.md

# Context

Leif reported the existing browser preview was blurry after the approved Slice/camera work. Actual DOM and screenshot inspection found the shared 3D canvas bitmap at 368x322 while its Cubes display was 1099x911. The bitmap was frozen after initial context creation as a Safari workaround; a phone/reference-sized initialization was later stretched across a desktop stage.

This repairs the existing approved viewer/Sculpt-quality behavior under Leif's standing request to continue improving the browser and fix the viewer PR. It adds no editing tool, storage behavior, renderer or camera convention. Preserve the single WebGL context, installed mesh, source, selection, pose, 2x density cap and 2048 pixel edge cap. Resize only the drawable when its required dimensions change; validate actual in-app WebKit behavior rather than assuming every resize loses its context.

## From the change's testing.md

# Testing

At device pixel ratios 1 and 2, initialize a phone-sized Cubes stage, switch through Slice's small reference and expand/resize to desktop and larger-than-cap layouts. Check actual drawable width/height against proportional 2048-edge/2x bounds, the same context/program/mesh, zero context-loss events and zero subsequent geometry uploads. Preserve source, selected slice, camera pose and nearest picking. Run existing projection, pixel, Slice and navigation regressions on Chromium and WebKit and inspect the actual in-app WebKit output. Root strict specs and pinned Trust must pass; actual unsigned agent:codex provenance remains separate from a permitted signature or human diff review.

## Requirement evidence

| ID | Canonical | Evidence |
| --- | --- | --- |
| REQ-ThreeMDViewer-004 | REQ-ThreeMDViewer-004 | New actual drawable-density and context-retention regression, existing GPU pixel/projection/picking tests, in-app browser before/after measurements and screenshot. |

## Current results

The complete post-resize UI suite passed 230 tests. After final display-density listeners, the viewer suite passed 130 tests. The final media-query/window-resize density regressions passed 4 tests. All ran on Chromium and WebKit without skips or retries. Actual in-app bitmap/display measurements and screenshots, test logs and implementation digests are in `docs/evidence/viewer-resolution/`. Pinned Trust, actual provenance and finalization remain separately evidenced.

## Repository verification and provenance

Pinned Trust 1.2.2 with Fledge 1.7.2 passed on implementation commit `95c1213886b853a7b945fd833a5af02fa0f8128d`; Augur returned review at risk 36, with configured soft provenance degradation. The full configured verification lane passed. Strict root specs passed at 55/55 files and Hi passed 87 criteria. Source digests above bind the browser results to this implementation; later lifecycle/materialization records do not change the HTML or tests.

Actual unsigned agent:codex attestation was recorded after the lane passed. The unchanged strict Attest policy rejects the unavailable permitted signature and reviewer allow-list, as shown in `attest-policy.json`. This is not a human review or signed provenance claim, and no policy was changed. Lifecycle closure is recorded separately in its supported receipt.

## Where these lessons go

- `specs/ThreeMDViewer/context.md`
