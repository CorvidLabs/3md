# Distribution

This checkout builds Sculpt against the ThreeMD sources in the parent repository by path. None of the adoption checks below have been started. This move does not change Sculpt file formats, notarize a build, or cut a Sculpt release.

ThreeMD `v2.1.0` is tagged. This app has not started the checks below. The path dependency compiles against the library sources in this checkout, and the default compact `.3mdb` save stays the app-specific container.

Before a Sculpt release, these checks are still open:

- `Package.swift` and `Package.resolved` move from `exact: "2.0.0"` to that tag.
- Portable binary output is re-verified against kind 2. Current portable copies are the 2.0 uncompressed envelope.
- The default compact `.3mdb` save stays the app-specific LZFSE container until that adoption chooses otherwise.
- Linked compositions still refuse a binary root by name, and self-contained bundles still use their current uncompressed envelope.
- `docs/dependencies.md`, `docs/3md-2-adoption.md`, and the RookSculpture pin sentences are updated to the tagged revision.
- A full Trust lane runs on the new pin. Notarization, a site download, and any holder distribution come after that lane.

App Store versus direct download is undecided. Nothing here is notarized or uploaded.

The entitlement file enables `com.apple.security.app-sandbox` and `com.apple.security.files.user-selected.read-write`. There is no broader file entitlement, no bookmark entitlement, and no network client entitlement.

`swift run --quiet RookTool package` builds and ad-hoc signs `dist/Rook.app`. The bundle contains the executable and `Info.plist`. It has no Resources payload. That signature cannot be notarized. The tool does not enable the Hardened Runtime.

No updater ships. Appearance is the `rook.appearance` default. It is not a secret. A sculpture leaves the Mac only when the person saves or exports a file.
