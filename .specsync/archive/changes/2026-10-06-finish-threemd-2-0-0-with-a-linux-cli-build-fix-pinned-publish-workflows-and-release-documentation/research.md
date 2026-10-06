---
change: finish-threemd-2-0-0-with-a-linux-cli-build-fix-pinned-publish-workflows-and-release-documentation
artifact: research
---

# Research

- Linux: official swift:6.0-noble (6.0.3) and swift:6.3-noble (6.3.3) images on linux/aarch64 reproduce the ThreeMDCLI error "reference to var 'stderr' is not concurrency-safe" at every `fputs(..., stderr)`. Writing through `FileHandle.standardError` compiles on both and on macOS; with that change 262 Swift tests pass on Linux (the 7 Apple Compression tests are compiled out; the explicit unsupported-LZFSE test runs instead). x86_64 was exercised only under Rosetta emulation. The scoped review then found that `FileHandle.write(_:)` raises (macOS, exit 134) or traps (Linux, exit 133) when standard error cannot be written, while `fputs` ignored the failure; POSIX `write` on the same descriptor keeps the old behaviour (39-case transcripts identical to main).
- npm: `npm view npm@latest` is 12.2.0 with engines ^22.22.2 || ^24.15.0 || >=26.0.0. `npm@^11.5.1` resolves to 11.21.0 (engines ^20.17.0 || >=22.9.0) and still satisfies the >=11.5.1 OIDC trusted-publishing requirement. Moving to Node 24 is a larger, separately verified change.
- crates.io: reproducing the v1.8.1 workflow on a scratch clone shows the sed rewrite leaves `rust/Cargo.toml` modified and `cargo publish` refuses uncommitted changes. For 2.0.0 the committed version already matches, so a check-instead-of-rewrite is sufficient and also prevents a dispatch from a branch publishing an arbitrary version. `cargo publish --token` is deprecated in favour of CARGO_REGISTRY_TOKEN.
- Element publishing does not depend on the registry copy of the parser (it bundles ../../js/src), so the two npm jobs cannot race.
