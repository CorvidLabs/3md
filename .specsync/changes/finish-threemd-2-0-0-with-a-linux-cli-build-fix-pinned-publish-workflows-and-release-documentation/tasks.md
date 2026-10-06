---
change: finish-threemd-2-0-0-with-a-linux-cli-build-fix-pinned-publish-workflows-and-release-documentation
artifact: tasks
---

# Tasks

- [x] Record definition approval (agent:claude acting on Leif's scope approval of 2026-10-06).
- [x] Route CLI standard-error writes through FileHandle.standardError (`b1f5937`), then make failed writes non-fatal like `fputs` after the scoped review found a crash (`d6eb66f`).
- [x] Pin the npm upgrade in publish.yml to npm@^11.5.1 (`b1f5937`).
- [x] Replace the cargo-publish version rewrite with a tag/version check, CARGO_REGISTRY_TOKEN and non-tag refusal (`b1f5937`, tightened to require a tag ref in `d6eb66f`; the check was simulated locally for `v2.0.0` and a branch ref).
- [x] Run the 39-case CLI parity check: macOS transcripts for main `87edafb` and `d6eb66f` are identical; Linux Swift 6.0.3 and 6.3.3 exit 1 for every closed-standard-error case.
- [x] Run Linux aarch64 container suites and interchange on an exact `git archive d6eb66f` copy; logs in docs/evidence/release-2.0.0/.
- [x] Pinned Trust 1.2.2 on `d6eb66f` (macOS, 48 s) with a commit and tool-version header in the log.
- [x] Update release documentation and regenerate docs.3md and web/docs.3md.
- [ ] Strict SpecSync and pinned Trust 1.2.2 on the final delivery tip, recorded by `specsync change check` and in the pull request.
- [ ] Scoped review of the final delivery tip, then finalization on the same pull request (review.json and finalization.json are written by those commands).

The Trust 1.2.2 gate on `d6eb66f` ran 268 Swift tests, 157 TypeScript tests with typecheck and build, 49 Rust tests plus 3 doctests, strict Clippy, editor grammar, element bundle drift and the nine-pair interchange (479 cases, 17,451 imports, 1,939 per pair); augur proceed (risk 27); provenance degraded under the soft policy. Linux aarch64 at `d6eb66f`: Swift 6.0.3 and 6.3.3 build and 262 tests, Rust 49 + 3 doctests, TypeScript 157, interchange 479 cases. Publication outcomes (npm, crates.io, Homebrew) are recorded on the GitHub release, not here.
