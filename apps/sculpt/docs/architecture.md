# Architecture

Sculpt.3md is the product name of this native Mac app, developed in the `CorvidLabs/sculpt-3md` repository. Its modules, executable, and bundle identifier remain Rook. One SwiftUI window uses the id `main` and edits 3md volumes as translucent cubes, ASCII, or spatial slices, up to 256 cells per axis. A Settings scene edits appearance. A menu bar extra offers Show Sculpt.3md, Settings, and Quit Sculpt.3md. Show Sculpt.3md opens that same window again.

The compile target is macOS 14 and Swift 6. `Package.swift` sets `swiftLanguageModes: [.v6]`.

## Package shape

Reference documents add a self-contained composition graph and a sparse world of shared model placements. Individual models stay at 256 cells per axis; sparse worlds use exact Int64 origins without a fixed dense cube extent. Composition and world editing run as native sheets on the same window. Their codecs never follow paths, and a separate immutable save job prepares reference files away from the main actor. Viewing focus and render/detail distances remain session state. The world renderer subtracts integer focus before local GPU conversion, caches each used model's geometry, and bounds active detailed/proxy instances independently of stored placements. [Composition](composable-3md.md) and [sparse worlds](sparse-worlds.md) record these contracts.

| Target | Responsibility | Direct dependencies |
| --- | --- | --- |
| `RookCore` | `AppAppearance`: system, light, dark | None |
| `RookSculpture` | Volume, native and portable scene codecs, identity-preserving snapshots, projection frame, example catalog, voxel OBJ export, atomic document and shared-model commands | ThreeMD 2.0.0 (exact) |
| `RookRendering` | Bounded cube geometry and picking, translucent cube raster, Core Text ASCII raster, Core Image Metal view, GIF/MP4 turntable export | RookSculpture |
| `RookApp` | Window, Settings, menu bar, sculpture editor | RookCore, RookSculpture, RookRendering |
| `RookVerification` | Development-only Swift test-log assessment | None |
| `RookTooling` | Development-only checks and resource-free packaging | None |
| `RookTool` | Development-tool entry point, example artifact generation, file-based structured editing | RookVerification, RookTooling, RookSculpture, RookRendering |

RookApp does not depend on RookTool, RookTooling, or RookVerification. RookCore does not depend on the sculpture modules.

```text
RookApp -> RookCore, RookSculpture, RookRendering
RookRendering -> RookSculpture -> ThreeMD
RookTool -> RookVerification, RookTooling, RookSculpture, RookRendering
```

The app sandbox is on. The entitlement file also grants `com.apple.security.files.user-selected.read-write` and does not grant network access. Closing the window does not quit the app, so the menu bar can show the same window again. The editor frame minimum is 940 by 650. The contract is `docs/ascii-sculpture.md`.
