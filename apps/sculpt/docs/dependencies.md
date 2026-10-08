# Dependencies

RookCore and RookApp use the system SDK. RookSculpture links one package: ThreeMD, the `ThreeMD` product from the `3md` package at `../..`. There is no other package dependency. Native readable saves retain text grammar `1.0` and the existing Sculpt schemas. Explicit portable copies additionally use upstream general binary and composition storage, retained identities and atomic edit snapshots. RookRendering uses Core Text, Core Image, MetalKit and SceneKit without another package. Runtime use remains offline.

Development tools stay outside the app:

| Tool | Pin |
| --- | --- |
| `hi` | 0.8.0 at `/tmp/rook-tools/hi` |
| `specsync` | 6.0.0 at `~/.cargo/bin/specsync` |
| `fledge` | 1.7.2 at `/opt/homebrew/bin/fledge` |
| Swift | 6.3.3 from Xcode |
| `swift-format` | 604.0.0 at `/opt/homebrew/bin/swift-format` |

`hi check` is structural. `specsync check` does not run the product tests. Fledge is a development convenience and is not embedded in the app.
