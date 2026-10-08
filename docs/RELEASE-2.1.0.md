# ThreeMD 2.1.0 preparation

Status: preparing. Not tagged. Not published.

On 2026-10-07 Leif approved the structured-payload library work and asked for a
pull request, then preparation for 2.1. Package manifests read 2.1.0. The
library and the docs for the tag are pull request 73, branch
`leif/readme-visuals`. Pull request 72 is the earlier structured-payload
review. This preparation does not merge, tag, publish, or weaken a trust
gate.

Storage has no fixed size stop. A file is parsed and saved when the process
can hold it. Local runs saved a 1 GB cube in Swift, TypeScript, and Rust, and
a 5 GB plane in Rust. A 10 GB file has not been measured. CI does not allocate
those files.

The approved SpecSync change is
`add-a-structured-binary-document-payload-kind-2-to-threemd-2-1-in-swift-typescript-and-rust-with-fast-checksums-cli`.
It is not accepted or archived. `fledge trust verify` has passed on this pull
request. It still has to pass on the exact commit that is tagged.

Publishing still happens only when a GitHub release is published. Until then
npm serves `@corvidlabs/threemd` and `@corvidlabs/three-md-element` at 2.0.0,
and crates.io stays at the last published `threemd` release. Swift resolves
`from: "2.1.0"` only after the `v2.1.0` tag exists. The VS Code extension is a
local VSIX (`threemd-2.1.0.vsix` once built from this branch) and is not
published to a marketplace.

## What is on the branch

SPEC.md 1.2 adds the binary save, payload kind 2, inside the version 1
container. The text file stays the `.3md`. The Swift, TypeScript and Rust
libraries implement kind 2, and `.binary` writes it. Kind 1 is deprecated.
`encodeTextContainer` still writes those ThreeMD 2.0 bytes, and readers still
open them. Kind 3 is reserved.

Shared structured fixtures are committed. The three writers agree on those
fixtures. The element bundle committed with the library work is 48,840 bytes
and contains no storage codec. The web component and the VS Code extension
stay text-only.

Also in the libraries, and called out because they change bytes or acceptance:

- Rust canonical numbers use the shortest round-trip spelling. That changes
  the canonical text of 92 powers of two that 2.0 misspelled.
- Swift trims with the frozen 19-scalar whitespace set W. See
  [MIGRATION-2.1.md](MIGRATION-2.1.md).

## Versions

| Surface | Prepared version | Published today |
| --- | --- | --- |
| Swift `ThreeMD` | Git tag not cut | `v2.0.0` |
| `@corvidlabs/threemd` | `2.1.0` in `js/package.json` | npm `2.0.0` |
| Rust `threemd` | `2.1.0` in `rust/Cargo.toml` | last crates.io release |
| `@corvidlabs/three-md-element` | `2.1.0` in `element/package.json` | npm `2.0.0` |
| VS Code `corvidlabs.threemd` | `2.1.0` in `editor/vscode/package.json` | local VSIX only |

## Capability matrix

| Capability | Swift | TypeScript | Rust |
| --- | --- | --- | --- |
| Text grammar 1.0 | Unchanged | Unchanged | Unchanged |
| Payload kind 1, deprecated (`encodeTextContainer`) | Yes, old files and 2.0 readers | Yes, old files and 2.0 readers | Yes, old files and 2.0 readers |
| Payload kind 2 (`.binary`) | Yes | Yes | Yes |
| Header-only `containerInfo` | Yes | Yes | Yes |
| Read a ThreeMD 2.0 `.3mdb` | Yes | Yes | Yes |
| CLI `convert` / `inspect` / binary input | No | n/a | n/a |
| Interchange protocol `3md-interchange-2` | No | No | No |
| Optional LZFSE | Apple Compression when available | Explicit unsupported-backend error | Explicit unsupported-backend error |
| Element and VS Code storage UI | No | No | n/a |

## Still open before a tag

- CLI binary input, `convert` and `inspect`. Today's commands stay text-only.
- Interchange protocol 2. The development adapter is still `3md-interchange-1`.
- The 2.0.0 reader compatibility job.
- The CI performance gate in `docs/design/threemd-2.1/perf-gate.md`: harnesses,
  `perf.yml`, and the three-run calibrated receipt. That gate is not this
  preparation.
- Release evidence under `docs/evidence/release-2.1.0/`: fuzz counts, perf
  receipts, and an interchange receipt. That directory does not exist yet.
- `fledge lanes run verify` and `fledge trust verify` on the exact release tip.
- README pictures and a regenerated `docs.3md` are on pull request 73.
  The CLI and interchange protocol 2 docs stay open with those features.
- A maintainer merge of pull request 73, then the tag. This branch does not do either.

## Local library check, not the gate

One release process per language, on the library sources that became commit
`63f58a8`, before `swift-format` and `cargo fmt`. Warmup was 1 second. Each
figure is the median of 9 samples, and each sample ran at least 2 ms. This is
not the performance gate. The gate warms up for 3 seconds, takes more samples,
and uses the median of 3 processes. Node 24 was not measured. Bun was 1.4.0,
not the gate's pinned 1.4.2. No speed below is a CI result.

Ratios are kind-2 decode divided by bounded text decode (G1), kind-2 decode
divided by the legacy parser (G2), and kind-1 decode divided by bounded text
decode (K1). The size ratio is kind-2 bytes divided by canonical text bytes.
The same kind-2 sizes came out of all three writers: 3,998,362 bytes for
synthetic-2000 and 2,934,090 bytes for sculpt-4096.

| Check | Swift | TypeScript, Bun 1.4.0 | Rust release |
| --- | ---: | ---: | ---: |
| synthetic G1 (ceiling 0.07 / 0.25 / 0.25) | 0.037 | 0.121 | 0.233 |
| sculpt G1 | 0.023 | 0.116 | 0.125 |
| synthetic G2 (ceiling 0.15 / 0.50 / 0.45) | 0.079 | 0.244 | 0.378 |
| sculpt G2 | 0.047 | 0.206 | 0.151 |
| synthetic K1 (ceiling 1.10) | 1.009 | 0.995 | 1.043 |
| sculpt K1 | 1.016 | 1.056 | 1.026 |
| synthetic kind-2 decode | 9.8 ms | 8.5 ms | 5.4 ms |
| synthetic size ratio (ceiling 0.995) | 0.990311 | 0.990311 | 0.990311 |
| sculpt size ratio (ceiling 0.98) | 0.967917 | 0.967917 | 0.967917 |

Kind-2 encode divided by kind-2 decode, synthetic then sculpt: Swift 0.40 and
0.85, Bun 1.57 and 1.64, Rust 0.94 and 0.68. Those ceilings are 2.0 for Swift
and Rust and 3.5 for TypeScript.

Rust synthetic G1 at 0.233 is under the 0.25 floor and close to it. The change
plan keeps the floor. A fallback optimization waits until two macOS calibration
runs show under 10% margin. This single run is not that calibration. Swift's
synthetic G1 is a ratio against a slow bounded-text baseline of about 0.264 s
on that input. Rust's bounded text on the same input was about 0.023 s, and
Bun's was about 0.071 s.

## Limits that stay

- Uncompressed storage is the portable contract. LZFSE stays Apple-only.
- The element and the VS Code extension stay text surfaces.
- Cross-port string agreement for kind 2 covers code points assigned in
  Unicode 13.0 on the pinned CI toolchains (SPEC 11.3.15).
- Linux performance stays report-only until a runner is calibrated. Windows
  execution is not verified for 2.1.
- CRC detects corruption. It does not authenticate content.
- A finite fixture set is not a proof for every input.

## Next step

Finish the open CLI, interchange, compatibility and performance work on this
pull request, then run `fledge lanes run verify` and `fledge trust verify` on
that tip before anyone cuts `v2.1.0`.
