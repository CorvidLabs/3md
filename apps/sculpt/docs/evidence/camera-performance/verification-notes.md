# Solar camera performance repair

Leif reported slow movement of the solar system. This is a bounded SCULPTURE-29 repair, with feature-branch publication to PR30. No merge or lifecycle approval, review or finalization is claimed.

## Baseline

The previous live Cubes path rebuilt camera-visible faces from the voxel volume and rasterized a complete bitmap on every camera request. Its packaged executable came from the debug configuration. The Core Image Metal view displayed that bitmap; it did not move voxel geometry on the GPU.

`Baseline.swift` was compiled separately against the existing debug and optimized release objects before renderer changes. Each probe decoded the existing compact solar example and measured three camera poses at 1100 by 700 pixels, opacity 0.35, selected layer 128, no ghosts. Decoding and file access are excluded. Each pose produced 37,776 visible faces. Raw samples are in `baseline-debug.json` and `baseline-release.json`.

The debug projection took 3008–3097 ms per pose, plus 164–177 ms for bitmap rasterization. Optimized projection took 42–46 ms and rasterization 125–150 ms. These are CPU construction timings, not measured on-screen frame rates.

## Implementation and verification

The final pinned seven-step lane passed in 532.658 seconds: formatter, 31-test harness, 195 complete-suite tests in nine suites (499.402 seconds), hi at 36 active criteria and 53 retired, strict SpecSync at five specs with zero warnings and 45/45 files and 8193/8193 lines, source boundaries and release fixtures. Source and native signing were then packaged in the optimized release configuration. CPU image and turntable export paths retain their existing renderer and limits. Automated offscreen layout captures do not establish live GPU behavior.

Raw logs and receipts are preserved in `final/tests/` and `final/harness/`. Thirty-two fresh editor layout images and their receipt are in `final/layout/`; actual native Metal fixture snapshots at three poses are in `final/native-gpu/`, and the 65,536-target grid image and receipt are in `final/dense-grid/`. The latter confirms a visible blue cube while dense edges are hidden and retains all 131,072 empty-cell triangles. These are new evidence, not rewritten earlier baselines.

## Initial focused/native checks

The first compile identified a SceneKit option-key type mismatch; the key now uses `SCNView.Option.preferredRenderingAPI.rawValue`. Nineteen focused tests passed after correction, covering surface bounds/cancellation, solar mesh identity reuse, camera matching, nearest cube/ghost picking, boundary faces, native Metal snapshots and optimized packaging.

The first optimized native package reopened `/private/tmp/sculpt-compact-native-solar-20261004-1345.3mdb` with 185,400 occupied cells and no unsaved changes. Actual CUA interaction orbited the solar scene and changed zoom from 1 to 1.15. In Paint mode, a face click added cell (174, 130, 68), raising occupancy to 185,401; Cmd-Z returned to 185,400 and no unsaved changes. Those coordinates are zero-based; the UI reported (175, 131, 69). Camera movement did not edit the document.

Native inspection also exposed a dense amber ghost-grid plane at 256-cell resolution. The correction hides only ghost edges below 2.5 projected AppKit points per cell, including foreshortening. All empty fill faces remain faint and pickable. Its separate dense-grid regression passes. The final native package shows the faint plane with the planets clearly visible. A native drag across that empty solar slice added 21 cells at z=128; one Cmd-Z restored all 21, returning to 185,400 occupied cells and no unsaved changes. A click in Orbit selected slice 154 without editing the document. The final solar scene is left open in Sculpt/Cubes with Paint off. `native-interaction.json` records these actual observations.

`LiveBenchmark.swift` measures the actual public live view/controller using optimized release objects, an attached but unordered AppKit window, and synchronous offscreen SceneKit Metal snapshots. After eight warmup frames, the initial 120 samples had median camera submission 0.104 ms and median completed GPU snapshot 8.866 ms, with maxima 2.236 and 32.302 ms. Surface extraction was 29.320 ms; host creation and mesh installation together were 355.042 ms. Exactly one mesh was installed. These timings exclude decode/file access and do not establish on-screen FPS. `live-initial-release.json` preserves that first run; final measurements will be recorded separately.

The benchmark initially failed its Metal readiness gate in the restricted terminal environment. Running the same binary with the authorized native GPU verification access succeeded. The product's sandbox and entitlements were not changed.

## Final performance measurement

The final renderer was rebuilt by the verified release lane and remeasured with the same 1100 by 700, 4× MSAA probe. `live-release.json` records 120 measured camera updates after eight warmup frames: median submission 0.109 ms, maximum 2.704 ms; median synchronous offscreen Metal snapshot 9.225 ms, maximum 60.393 ms. Extraction was 44.885 ms and initial host/mesh installation 279.909 ms. The document mesh installation count remained one. `solar-metal.png` retains the final probe's actual GPU image, visually inspected alongside the dense-grid image. The maximum snapshot latency and the offscreen methodology mean this is not a guarantee of constant 60 FPS in the app.

Private feature-branch publication updates PR30. New GitHub CI remains separate from local tests and native observations. No merge, release, deployment or lifecycle approval/review/finalization is claimed.
