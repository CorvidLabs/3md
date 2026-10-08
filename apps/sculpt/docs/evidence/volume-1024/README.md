# 1024-cubed execution evidence

The Swift case study physically initialized and verified **1,073,741,824 bytes**, exactly 1 GiB. It also created two supported reusable worlds within a 1024-cubed address domain, opened the landscape in Sculpt, and measured actual offscreen Metal rendering.

| Result | Measured value |
| --- | ---: |
| Dense raw bytes initialized and compared | 1,073,741,824 |
| Dense LZFSE bytes | 53,965,390 |
| Final dense encode including hash/write/fsync | 6.076145084 seconds |
| Final dense decode including hash/full comparison | 0.803959292 seconds |
| Final decode physical-footprint increase | 3,768,344 bytes |
| First decode physical-footprint increase | 56,541,232 bytes |
| Solid world occupied cells through shared instances | 1,073,741,824 |
| Solid native world bytes | 608,772 |
| Landscape occupied cells | 28,057,022 |
| Landscape native world bytes | 2,249,314 |
| Cross-language transfers | 144, all passed |
| Complete app/development suite | 371 tests in 32 suites, all passed |
| Verification harness | 31 tests, all passed |
| Actual Metal cases and retained PNGs | 10 cases, 20 PNGs |

The synthetic dense pattern and the solid/landscape worlds are different payloads. Their sizes compare representation strategies, not interchangeable compression of the same document. Ordinary editing remains bounded to 256 cells per model axis. Sparse placement, graph, storage and renderer budgets remain unchanged.

[Dense analysis](dense-analysis.md) preserves the first run and the final run after replacing per-chunk Foundation reads with one POSIX buffer. Both runs have identical full-volume and encoded SHA256 values. The experimental compressed payload is raw byte benchmark data, not a ThreeMD or Sculpt file. Its large payload remains in temporary local output directories and is not committed.

[World files](worlds/README.md) include native readable worlds and explicit portable text/binary copies. Each retained file reopens with its exact scene and revision where applicable. [Native observations](native/observations.md) record the actual Open, focus, orbit and Save workflow. The saved native landscape is byte-identical to its generated native source.

[Metal measurements](metal/README.md) separate CPU camera submission from synchronized offscreen snapshots. Median frame times across cases are 1.626438 to 3.153271 ms on this Apple M1 Ultra. The world is rendered with shared geometry, bounded detail, proxies, omitted instances and distance culling. These measurements do not establish on-screen FPS or drawing a billion individual cubes.

[Interchange receipt](interchange/receipt.json) records 12 producer imports and 144 transfers across all nine Swift, TypeScript and Rust pairs, exactly 16 per pair. It verifies both original portable text and binary inputs for both worlds, canonical and binary bytes, adoption, revisions, edits and stale-edit rejection. Node and Rust preserve the Sculpt profile as opaque ThreeMD content; this does not claim they interpret the app's world schema. The SDK Swift [driver](interchange/Verify.swift) runs existing public adapters rather than a new product interface. Its total runtime is not a storage benchmark.

Source and commands:

- The definition was approved before implementation in `aad8f29` by `agent:codex-root` under Leif's request. This is agent evidence, not Leif's diff review, a GitHub approval or a signature.
- The initial dense run and world fixtures were generated at `6644ed2a9f8bfe5c5475ee3e86b00dc8e786d550`.
- The decoder repair, complete suite, final dense run and opt-in rendering use frozen Source/Test commit `619a0efc2fd41b51e02daacbce4e7404546fd8d9`. Later prose and lifecycle commits do not change those sources.
- Host: Mac13,2, Apple M1 Ultra, 64 GiB memory, 20 logical processors, arm64, macOS 26.5.2 build 25F84.
- Observed compiler: Apple Swift 6.3.3, swiftlang 6.3.3.1.3. The expected version inside the dense receipt is a repository pin, independently checked with `/usr/bin/swift --version`.
- Observed tools: hi 0.8.0 at `/tmp/rook-tools/hi`, SpecSync 6.0.0 at `/Users/leif/.cargo/bin/specsync`, Fledge 1.7.2 at `/opt/homebrew/bin/fledge`, swift-format 604.0.0.
- Final optimized RookTool SHA256: `af3f5484c67f24ac5b9bb2beecf31c71fd3586dbea9c387d2966d9662b6a4cc5`.
- Full run: `/opt/homebrew/bin/fledge lanes run verify`, with the pinned tools on PATH.
- Dense: `.build/release/RookTool volume-study --output /private/tmp/sculpt-dense1024-final-20261005 --dense-1024`.
- World files: `.build/release/RookTool volume-worlds --output /private/tmp/sculpt-1024-case-study-20261005/docs/evidence/volume-1024/worlds`.
- Rendering: `ROOK_VOLUME_STUDY_RENDERING=1 ROOK_VOLUME_STUDY_RENDERING_DIRECTORY=/private/tmp/sculpt-1024-case-study-20261005/docs/evidence/volume-1024/metal ROOK_VOLUME_STUDY_SOURCE_REVISION=619a0efc2fd41b51e02daacbce4e7404546fd8d9 /usr/bin/swift test --configuration release --no-parallel --filter SculptureVolumeStudyRenderingTests`.

The full verify lane passed format, the 31-test harness, all 371 tests and hi's 43 active criteria with 53 retired. It then correctly rejected five undocumented API symbols, counted as six strict warnings including the aggregate coverage warning. Adding their exported-symbol table rows changed only prose. The retained [first lane log](verification/verify.log) is unchanged. Subsequent pinned checks passed [strict specs](verification/spec-final.log), [source boundaries](verification/boundaries-final.log) and [release fixture scan](verification/release-fixture-final.log). Strict specs report five modules, zero warnings, 68/68 source files and 17,262/17,262 lines. [Complete test receipt](verification/full-swift-test-result.json) and [harness receipt](verification/harness-swift-test-result.json) preserve runner assessment and raw child logs.

The opt-in renderer actually executed and passed two tests in 23.262 seconds, including the 23.189-second stress test. The ordinary suite's same test returns when opt-in is absent and is not GPU stress evidence by itself. Eight focused dense tests also passed after the decoder repair. The earlier 21 focused release tests passed before that repair.

The bounded scope and current contracts remain explicit. [Scoped agent review](agent-review.md) is technical evidence, not an independent human review. [Official lifecycle status](lifecycle.md) records draft PR36 and the existing missing retired-module contracts that block SpecSync closing. The approved requirement deltas were materialized, but the official check exited 1. Passing current-module checks does not claim project-wide lifecycle completion, finalization, attestation, release or deployment. GitHub checks are recorded on the pull request separately from these local execution receipts.
