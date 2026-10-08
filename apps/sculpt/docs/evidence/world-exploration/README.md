# World exploration evidence

The implementation and full passing lane were pinned to `afa827b772984ef64d537c7645c9d5aac9d282d5`. The lane ran all seven steps in 276.558 seconds: 394 tests in 35 suites, 31 harness tests, formatting, hi (44 active criteria and 53 retired), strict validation of five current specifications, product boundaries and the optimized release fixture scan. Current coverage was 70/70 files and 17,956/17,956 source lines. Structural coverage is distinct from behavioral coverage.

The original full run exposed an Orbit edge regression. Its failed receipt is preserved alongside the ten-test repair run and final complete passing receipt. An optional capture assertion was added during the original failing run; that run is not final verification. The passing lane began and ended with the same committed implementation and tests.

`metal/` preserves the first three actual SceneKit Metal captures. Its `changedPixels` metric is invalid because the unconfigured empty reference used a different background. It must not be used as occupied image coverage. The images, installed face counts and zero-bounds assertions remain historical evidence.

`metal-final/` contains new captures at `eaa0497ce2b28f1eba551bf79f3eaf2e222ace57`, after correcting only the optional capture test to configure a zero-placement reference with the same library, camera, mode and background. All seven tests in that suite passed in 4.857 seconds. Corrected coverage is 27,053 pixels for the overview, 311,271 for the valley castle and 168,725 for the sky citadel. Each frame has zero bounds fallbacks, retains eight installed reusable meshes, and stays below the 512-instance and 500,000-face limits. Source world bytes remain equal after capture.

The separate `agent-review.md` records source and visual inspection by an agent. It is not independent human review, a GitHub approval or a signed attestation. `native-observations.md` records actual interaction in the optimized app, distinct from synchronized offscreen captures. None of these establishes on-screen FPS or dense billion-voxel GPU rendering.

The final documentation pass corrects the coarse helper's picking comment without changing behavior. Source geometry and current user files are unchanged by navigation. Publication and the official lifecycle result are recorded separately in `lifecycle.md`.
