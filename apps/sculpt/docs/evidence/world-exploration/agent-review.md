# Scoped world exploration agent technical review

Reviewer claim: `agent:threemd_typescript`. This is an agent technical review of the bounded SCULPTURE-37 implementation, not an independent human review, a GitHub approval, a signature, or release authorization.

Source/Test commit reviewed: `afa827b772984ef64d537c7645c9d5aac9d282d5`. The checkout was clean at this commit before this evidence file was added. No builds, tests, publication, lifecycle actions or production edits were performed by this reviewer during the final source review.

The corrected capture-test commit is `eaa0497ce2b28f1eba551bf79f3eaf2e222ace57`. Direct Git comparison against the reviewed commit shows no changes under `Sources/`; this commit changes only the reviewer's optional capture test. The final product source review therefore remains applicable, while the full lane and supplemental capture results retain their distinct commit labels.

## Direct review scope

The reviewer read these implementation files and their integration boundaries:

- `Sources/RookRendering/SculptureWorldNavigation.swift`
- `Sources/RookRendering/SculptureLiveWorldView.swift`
- `Sources/RookRendering/SculptureWorldCoarseMesh.swift`
- `Sources/RookApp/SculptureWorldEditor.swift`
- `Sources/RookSculpture/SculptureWorld.swift`, specifically its existing coordinate and placement invariants supporting overview arithmetic

Peer-authored tests read as supporting coverage were `Tests/RookRenderingTests/SculptureWorldNavigationTests.swift`, `Tests/RookRenderingTests/SculptureWorldCoarseMeshTests.swift`, and the exploration/overview cases in `Tests/RookAppTests/SculptureWorldEditorTests.swift`. The existing native mesh regression in `Tests/RookRenderingTests/SculptureVoxelMeshBuffersTests.swift` was inspected when the initial full lane reported its failure.

This reviewer authored `SculptureWorldExplorationRenderingTests.swift` and the current assertion changes in `SculptureLiveWorldTests.swift` and `SculptureVolumeStudyRenderingTests.swift`. Their implementation and results are not claimed as an independent review of the reviewer's own tests.

## Findings and resolution

No remaining functional blocker was identified in the scoped final source review.

The initial full lane exposed a real compatibility regression: high-zoom Orbit detailed edges were always hidden, failing `SculptureVoxelMeshBuffersTests.swift:303`. This reviewer read the failure receipt and reported it to root and the renderer owner. The reviewed final source restores Orbit edge visibility using the existing projected spacing threshold of two pixels; Explore keeps detail edges hidden. The root-run repair receipt at `/private/tmp/sculpt-world-exploration-orbit-repair.log` records ten tests in two suites passing, including the existing native mesh suite and the new exploration suite. This is receipt inspection, not a test run performed by this reviewer.

Root separately reported that an initial native castle view used bounds fallbacks despite all visible coarse models fitting the face budget. The final source was directly checked: it sums the coarse cost of visible candidates, reserves all remaining coarse costs when that total fits 500,000 faces, and spends only the surplus on detailed upgrades. When the coarse total does not fit, the six-face fallback reservation remains. The source retains the 512-instance cap, deterministic candidate ordering, omissions and distance culling. The report of the initial visual problem comes from root; this reviewer has not claimed to have viewed that initial capture.

One minor wording boundary remains in the coarse result's source comment: original dimensions define placement and culling bounds, while native picking follows the scaled occupied coarse triangles, rather than accepting every point in the original bounding box. This was reported to the coarse owner. It does not change the inspected behavior.

## Technical checks

- Coarse preparation uses at most 16³ bins, at most 24,576 faces, bounded per-material histograms and cancellation checks. Occupied cells survive binning; palette order resolves equal dominant material counts. Scaling is applied to the geometry child before the instance transform, retaining the model center and original extents, including odd dimensions.
- Preparation reserves the existing detailed model cache first. Optional coarse meshes use only remaining capacity under the unchanged 1,000,000-face aggregate bound. Missing coarse data uses the explicit bounds fallback. Cache reuse requires matching immutable libraries and retains both detailed and coarse buffer identities. Local travel/look updates do not prepare models or rebuild instance nodes; an exact anchor rebase updates bounded placement nodes while retaining meshes.
- Exploration stores an exact signed Int64 anchor and small Double offsets. Rebase performs checked integer addition before assignment, never converts the large anchor through Double, and preserves fractional offsets. Failed moves leave the value unchanged. Rendering subtracts exact integer anchors before converting bounded local positions to Float.
- Movement and camera orientation agree: yaw zero faces negative Z; positive yaw turns left; WASD is horizontal and yaw-relative; E travels upward and Q downward using document Y-down coordinates. Diagonals are normalized. Pitch changes look rather than forward travel and is limited to avoid inversion.
- Held-key input requires the canvas to be first responder. Movement uses a cancellable main-actor task with elapsed-time updates and a bounded timestep. A first nonrepeat key press gives an immediate bounded movement pulse; autorepeat does not add another pulse. Releasing the last key, Escape, responder loss, window key loss/close, removal, mode change and dismantling cancel navigation and clear held keys. The task generation prevents an older canceled task from clearing a newer session.
- World title, model library, placement references and origins remain document state. Focus, explorer pose, camera, distances and navigation mode remain session state. The new navigation/overview/Visit methods do not append document Undo history or replace document/scene revision identifiers. Existing portable snapshots are retained; no user file is saved or migrated automatically.
- Overview uses validated model dimensions and exact signed midpoint arithmetic. It refuses a span that cannot fit the existing overview distance, leaving document content and focus unchanged. It is a bounded overview, not a promise to show an arbitrary Int64-spanning world or every placement beyond the render cap.
- Visit chooses the first existing placement of the selected reusable model, retains its exact origin, enters Explore with the documented starting offset and uses bounded local distances. It changes selection and view state, without changing the reusable model or placement document.

Bounds fallback counts also include empty geometry and unavailable coarse cache entries. They should not be described as exclusively caused by a full-detail budget failure. Coarse picking and silhouettes are approximate presentation of unchanged source voxels; this is free exploration without collision or gravity.

## Verification and visual evidence

The reviewer inspected `/private/tmp/sculpt-world-exploration-verify-final.log`: the root-run final pinned lane passed 394 tests in 35 suites in 252.080 seconds, the 31-test harness, source boundaries and release fixture checks. The seven-step lane completed in 276.558 seconds. Current strict specification coverage was five modules, 70/70 files and 17,956/17,956 lines; hi recorded 44 active criteria and 53 retired. These are read receipts, not additional tests run by this reviewer. The earlier failed full receipt remains historical and was not substituted for this result.

The reviewer opened all three actual PNGs under `metal/` with `view_image`, and read their receipt pinned to `afa827b772984ef64d537c7645c9d5aac9d282d5`. Root reported the seven-test capture suite passing in 5.514 seconds. The device recorded is Apple M1 Ultra, and each image is 800 by 600 pixels.

| Image | Direct visual observation | Recorded rendering counts |
| --- | --- | --- |
| `metal-final/overview.png` | A coherent colored valley with a central river/bridge pattern, trees and ground structures, with distinct floating islands/citadels above it. Terrain replaces the previous empty wire boxes. Most landmarks are small at this whole-world scale; this view establishes layout rather than close architectural detail. | 280 visible, 1 detailed, 279 coarse, 0 bounds, 0 omitted, 0 culled; 343,384 faces. |
| `metal-final/valley-castle.png` | A clearly readable foreground wall, four towers/roofs and central gateway, with stepped ground and trees at the sides. The frontal wall fills much of the view and hides the interior; it is an exploration starting pose rather than a complete castle overview. | 102 visible, 22 detailed, 80 coarse, 0 bounds, 0 omitted, 178 culled; 494,988 faces. |
| `metal-final/sky-citadel.png` | Distinct towers, roof colors, a flag, a doorway and the floating terraced island silhouette. The bottom of the island meets the lower image edge, so the entire underside is not demonstrated by this framing. | 4 visible, 1 detailed, 3 coarse, 0 bounds, 0 omitted, 276 culled; 23,842 faces. |

All three images are nonblank and show coherent colored geometry. Each receipt records eight shared model-cache installations, and zero wire-bounds fallbacks. Visible counts refer to the renderer's distance/cap selection, not a count of every placement contributing pixels after camera frustum/occlusion.

The first capture's `changedPixels` metric is invalid as object coverage: all three receipts report 480,000 changed pixels, including the overview's large uniform background margins. This reviewer identified the mismatch between the unconfigured empty-view reference and the configured rendered background, and reported it to root. Root authorized a narrow correction to the reviewer's own optional capture test. The reference now uses a validated zero-placement world, matching initialized camera settings, records its RGB background, and requires the overview to retain visible background. The original `metal/` images/receipt are unchanged.

The reviewer also opened all three corrected `metal-final/` PNGs with `view_image`, inspected `metal-final/receipt.json`, and read `/private/tmp/sculpt-world-exploration-metal-final.log`. The root-run supplemental seven-test capture suite passed in 4.857 seconds at `eaa0497ce2b28f1eba551bf79f3eaf2e222ace57`. The configured reference RGB is `[20, 29, 34]` for all three images. Corrected changed-pixel coverage is 27,053 pixels (5.64%) for overview, 311,271 (64.85%) for valley castle and 168,725 (35.15%) for sky citadel. Corresponding colored-pixel counts are 26,080, 310,869 and 168,297. These are thresholded image differences from a rendered clear reference, not an exact geometric silhouette-area measurement.

SHA-256 comparison confirms each corrected PNG is byte-identical to its preserved original PNG. The image behavior did not change; the receipt measurement was corrected. Direct visual observations and renderer counts in the table apply to both image sets. No visual blocker was identified for this bounded evidence set, with the scale and framing limitations noted above.

Root additionally reported live packaged-app checks: overview showed 280 visible placements; castle showed 102 visible, 22 detailed and 80 coarse with zero bounds; citadel showed four visible and zero bounds. Root reported actual W/D/E and drag changing the view while Undo/Redo stayed disabled. Those native interaction results are reported by root, not independently executed or visually inspected by this reviewer. The reviewer's direct visual evidence is the six opened offscreen PNGs and their receipts.

These checks do not establish on-screen FPS, dense billion-voxel GPU rendering, collision simulation, portability to other graphics hardware, human approval, or a release/publication result.
