---
change: finish-threemd-2-0-0-with-a-linux-cli-build-fix-pinned-publish-workflows-and-release-documentation
artifact: tasks
---

# Tasks

- [x] Record definition approval (agent:claude acting on Leif's scope approval of 2026-10-06).
- [x] Route CLI standard-error writes through FileHandle.standardError (`b1f5937`).
- [x] Pin the npm upgrade in publish.yml to npm@^11.5.1 (`b1f5937`).
- [x] Replace the cargo-publish version rewrite with a tag/version check, CARGO_REGISTRY_TOKEN and non-tag refusal (`b1f5937`; the check step was simulated locally for `v2.0.0` and a non-tag ref).
- [x] Run Linux aarch64 container suites and interchange on an exact `git archive b1f5937` copy; logs in docs/evidence/release-2.0.0/.
- [x] Update release documentation and regenerate docs.3md and web/docs.3md.
- [x] Strict SpecSync (`specsync check --spec ThreeMD --strict`: 0 warnings) and pinned Trust 1.2.2 on `b1f5937` (macOS, 59 s); repeated on the exact delivery tip before review.
- [x] Scoped review and finalization on the delivery PR, recorded in review.json and finalization.json.

The Trust 1.2.2 gate on `b1f5937` ran 268 Swift tests, 157 TypeScript tests with typecheck and build, 49 Rust tests plus 3 doctests, strict Clippy, editor grammar, element bundle drift and the nine-pair interchange (479 cases, 17,451 imports, 1,939 per pair); augur proceed (risk 27); provenance degraded under the soft policy. Linux aarch64: Swift 6.0.3 and 6.3.3 build and 262 tests, Rust 49 + 3 doctests, TypeScript 157, interchange 479 cases. Publication outcomes (npm, crates.io, Homebrew) are recorded on the GitHub release, not here.
