# Blockhaven and large-map optimization

This iteration adds the original Blockhaven landscape and addresses large-map preparation, world placement reuse, slice drawing and cube animation exports. It preserves existing capacity limits, file formats, product sandbox boundaries and historical lifecycle evidence.

## Editable content and artifacts

The same deterministic 192 × 64 × 192 landscape contains 827,937 occupied cells and 136,274 exterior faces. Its self-contained composition and sparse world share 36 contiguous 32 × 64 × 32 chunks. The castle, village, farms, bridge, river, lake, trees, hills, caves and ruin are authored in Swift without downloaded assets. This is a Sculpt.3md example, not a Minecraft Java or Bedrock file.

`Examples/Blockhaven/` contains composition and world sources, a compact expanded voxel document, PNG, GIF, MP4 and OBJ. The compact voxel copy is 58,016 bytes. Manifest/source/compact equivalence, actual media decoding and OBJ faces/materials/bounds/winding have dedicated tests. SHA256 artifact receipts are retained in `baseline/` and `final/`.

## Release performance measurements

Measurements use the actual map on this Mac, the same exterior geometry and an optimized Swift build. Receipts retain individual samples and native Metal snapshots. Preparation and installation are separate operations, and a first synchronized snapshot is not an on-screen frame-rate measurement.

| Operation | Earlier path | Optimized path |
| --- | ---: | ---: |
| Exterior extraction, median of five | 18.45 ms | 11.06 ms |
| Mesh installation on the main actor | 81.22 ms | 4.70 ms |
| Mesh byte preparation on a worker | Included in installation | 7.70 ms |
| First synchronized native snapshot | 124.13 ms | 77.30 ms |
| Four scalar projection poses | 55.58–64.67 ms each | 54.65–58.02 ms each |
| Same poses using one prepared scene | Not available | 36.31–39.50 ms each |

The final prepared buffers contain 27,254,800 bytes, including exact per-layer selection indices. The main-actor installation reduction is about 17×; this moves CPU preparation to an immutable worker result rather than removing all of that work. Selection streams increase the earlier 22,894,032-byte optimized buffer footprint to repair actual native outline rendering. Camera submissions were already constant and cheap: 240 submissions take roughly 1.1–1.2 ms; no improvement is claimed for that number.

Initial world preparation takes 24.61 ms. Re-preparing the same model library after a placement change takes 0.11 ms and retains buffer identities. Camera, opacity, selection and title-only edits retain unchanged document mesh sources. Changing the selected layer replaces only its small outline index element. Native tests check that near/far edge detail does not remove fills, selected outlines or pick targets.

The slice canvas draws visible cells with a one-cell fringe instead of allocating the whole enlarged drawing surface. A 256-square slice at 16× in a 384-point viewport draws 324 cells in a 432-square-point backing, while retaining the 6,144-square-point logical scroll and hit area. Cube animation prepares exterior geometry once per job; scenes exceeding that extraction budget keep the bounded per-frame fallback.

## Verification retained so far

The content baseline passed the pinned seven-step lane in 266.253 seconds: 262 product tests, 31 harness checks, hi at 39 active criteria and 53 retired, strict SpecSync at five specs with zero warnings and 55/55 files and 12,923/12,923 lines, source boundaries, formatting and release fixtures.

The optimized lane passed in 231.659 seconds: 283 product tests across 20 suites, 31 harness checks, hi at 40 active criteria and 53 retired, strict SpecSync at five specs with zero warnings and 57/57 files and 13,410/13,410 lines. `final/` retains this lane. Subsequent native scrolling exposed another issue; these receipts predate that repair and are not the closing verification for it.

An initial focused run caught two genuine verification issues. A thumbnail color-space mismatch was repaired using explicit sRGB without weakening channel assertions. An invalid even-height fallback fixture was replaced with an odd-height fixture that still exceeds 500,000 exterior faces while staying within the unchanged 250,000 visible-quad limit. The corrected release run passed all 23 focused checks. Details remain in `preliminary-checks.json`.

The closing seven-step lane passed in 156.851 seconds: 287 tests across 21 suites, 31 harness checks, hi at 40 active criteria and 53 retired, strict SpecSync at five specs with zero warnings and 57/57 files and 13,531/13,531 lines. Formatting, source boundaries and release fixtures passed. `closing/` retains the complete test/harness receipts, fresh native presentation and renderer captures, the final optimized performance receipt, artifact hashes and frozen source/test/configuration hashes. Offscreen presentation captures establish layout separately from actual live Metal checks. The initial post-outline-repair lane rejected 23 outdated cache-identity assertions; its original log is retained in `selection-cache-test-first-run/` alongside the corrected final evidence.

## Actual native checks and selection repairs

The refreshed optimized app opened `blockhaven.3mdb` and reported Blockhaven valley, 827,937 cells, and no unsaved changes. Selecting sidebar Slice 92 selected layer 91. A 16× grid stroke painted cells 1 through 4 in its first row, adding four cells; one Undo restored the original count. Right, Down and Space painted precisely cell 5,2; Undo restored the clean original. Clicking the visible castle flag selected cell 55,15 in Slice 27, matching its source coordinates at z=26.

Scrolling that enlarged slice exposed a blank canvas although the logical hit area remained. Its bounded Canvas used a visual offset that native scroll clipping could cull, and SwiftUI preference measurements did not cross the native scroll hosting boundary. True-layout placement and an object-scoped native clip-bounds observer repair both faults. Two native regressions check glyph pixels at 35%, 75% and 100% scroll offsets and observer teardown. In the actual app, five pages of scrolling at 16× retained visible grid and terrain glyphs. Clicking painted cell 1,42; Undo restored the count. Right and Space painted cell 2,42; Undo restored the clean original. Clicking visible sidebar slices 92 and 95 selected their layers without recentering the list under the pointer. An asymmetric thumbnail-row regression passes: the apparent flipped thumbnail was rectangular content padded inside a square, not reversed rows.

The native outline originally kept drawing earlier slices after selection changed. A new actual Metal snapshot test reproduced this with asymmetric occupied cells at depths 1 and 7. Replacing a primitive range alone did not repair it; the final path installs only the exact selected layer's prepacked line indices and shares the immutable vertex source. The regression now checks amber pixels at depths 1, 7 and 1, with one mesh installation. The earlier solar cache test was updated to require unchanged fill/global-edge geometry and vertex sources while validating exact selected-layer indices, instead of incorrectly requiring the small outline element to remain unchanged.

After packaging this repair, the actual app reopened the compact map at 827,937 cells. Sidebar selection changed the visible amber outline from slice 97 to 100. Clicking the castle flag selected cell 55,15 in slice 27 and moved its outline to the castle section. Cube Draw added cell 54,14,27, increasing occupancy to 827,938; one Undo restored the clean original. A pointer drag orbited the live map while retaining the correct selected outline. No user document was overwritten.

No completed native map save, video/GIF/OBJ save, on-screen FPS guarantee, new lifecycle approval, independent human diff review, PR30 merge or release is claimed by this record.
