# Native exploration observations

Root used the actual app at `/private/tmp/sculpt-1024-case-study-20261005/dist/Rook.app`, packaged from the tested product at `afa827b772984ef64d537c7645c9d5aac9d282d5`. The local ad hoc signature passed verification. The only entitlements are the app sandbox and user-selected file read/write. No network entitlement was added.

Executable SHA-256: `438aaa5dbe10a53874805924cadf7757707a379434c90597a5b9541634c7a4da`.

The earlier app's world Undo/Redo were disabled, and closing the sheet showed no unsaved changes in the parent. Root quit it before opening the final package by its full path, then reopened `docs/evidence/volume-1024/native/landscape-native-save.3md` through the native Open panel. That unchanged file has SHA-256 `753a593c8557c313225e078cc29513590958b8d8716c4f5c24150acd21b2552a`.

Observed flows:

- Initial overview: 280 visible placements, one detailed and 279 colored coarse models, zero bounds, zero outside range and zero omitted. Focus is 511,511,511 with 896-cell range.
- Visit Valley castle: Explore activates and shows the castle gateway, roofs, adjacent trees and terrain. Counts are 102 visible, 22 detailed, 80 coarse, zero bounds, 178 outside range and zero omitted. Focus is 192,960,352.
- Clicked the canvas, pressed W, D and E, and dragged to look. The viewpoint moved forward, sideways and upward, then turned, revealing the castle's side and nearby forest. Undo/Redo stayed disabled.
- Whole World returned to Orbit at exact focus 511,511,511 and showed all 280 placements. With the retained 192-cell detail distance it used two detailed models and 278 coarse, zero bounds and zero omitted.
- Visit Sky citadel showed its floating island, towers, gateway and flag in perspective: four visible models, one detailed and three coarse, zero bounds, 276 outside range and zero omitted.
- Returned to Valley castle in Explore for the user handoff. Navigation did not save or edit the world.

The native app is free exploration, without collision or gravity. These observations and UI screenshots establish actual interaction and rendering on this Mac; they are not timing or FPS measurements. The separate capture suite supplies reproducible PNGs and structured geometry counts.
