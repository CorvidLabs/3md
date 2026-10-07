# ThreeMD 2.1 performance gate

This is the repository copy of the performance gate from the ThreeMD 2.1 specification package. It was committed with
the SpecSync change
`add-a-structured-binary-document-payload-kind-2-to-threemd-2-1-in-swift-typescript-and-rust-with-fast-checksums-cli`
(WP0) so that every reference to "perf-gate section N" resolves in the repository. The section numbers are
unchanged. "The SpecSync change" below is that change, `plan.md` is its `plan.md`, and "spec21"
is the specification package. The measurement sources cited in section 5 (`review-perf/`, `binv2/`) are result files
in the lead session's scratch area and are not committed; their numbers are copied here and in the change's
`research.md`.

Adaptations made on copying: section 2 now names the committed input generators (they moved from WP11 to WP1), the
end of section 8 says the gate leaves the verify lane unchanged apart from G6, and four table cells that held a dash
now say "none" or "n/a". Nothing else changed.

The SpecSync change for 2.1 requires: kind-2 decode at least 4 times faster than the bounded text decode and faster
than the legacy parser in all three languages; kind-1 decode within 10% of the bounded text decode thanks to a fast
CRC; and a CI performance gate that enforces both. This file defines the harnesses, inputs, method, thresholds,
calibration and CI workflow. Speed is not part of the format (SPEC 11.3.16); a slow but correct reader conforms to
the specification and fails only this release gate.

## 1. What is measured

Operations, timed in the same process on the same inputs:

| Operation | Swift | TypeScript | Rust |
|---|---|---|---|
| `legacy_parse` | `Parser().parse(String(decoding: text, as: UTF8.self))` | `parse(new TextDecoder().decode(text))` | `threemd::parse(str::from_utf8(text))` |
| `bounded_text_decode` | `DocumentStorageCodec.decode(text)` | `DocumentStorageCodec.decode(text)` | `storage::decode(text, ..)` |
| `kind1_decode` | `DocumentStorageCodec.decode(encodeTextContainer(d))` | same | same |
| `kind2_decode` | `DocumentStorageCodec.decode(encode(d, .binary))` | same | same |
| `text_encode` | `encode(d, .text)` | same | same |
| `kind2_encode` | `encode(d, .binary(.none))` | same | same |

`text` is the canonical text of each input, `d` its bounded decode. TypeScript runs the portable path only: no
`node:zlib` CRC and no other host built-ins.

## 2. Inputs

| Input | How it is produced | Size of canonical text |
|---|---|---|
| Examples corpus | the 293 `Examples/*.3md` files; one sample decodes all of them (one aggregate) | 1,188,086 B |
| Largest example | `Examples/conways-game-of-life.3md` | 17,509 B |
| Median example | `Examples/corvid-voxel-wordmark.3md` | 3,974 B |
| synthetic-2000 | `scripts/bench/generate-synthetic.mjs` (seed `0x3d3d2000`, 2,000 planes of mixed Markdown); the generator asserts the SHA-256 of the generated source, `b64e50d34e2d1fdf4a06d11638bdb1b3cb4cc912d5921f58317f46064de0c459` (generated source: 4,037,470 B) | 4,037,480 B (canonical text) |
| sculpt-4096 | `scripts/bench/generate-sculpt.mjs` (seed `0x5c0197`, 4,096 layers of 32 × 20 voxels, one label and three attributes each); asserts the SHA-256 of the generated source, `dae524d9ea9bab4a027b9213082c19eb2621ff788890a6f25eb20bddd4ea667d` (generated source: 3,031,335 B) | 3,031,345 B (canonical text) |

The two generators are committed under `scripts/bench/` (WP1). They started in the design study as
`study/load-benchmarks/ts-bench/generate-synthetic.mjs` and `binv2/proto-speed/tools/generate-sculpt.mjs` in the lead
session's scratch area; the committed versions produce byte-identical output (the metadata of each document still
names its original generator, because that text is part of the hash). They run under Node, because `Math.sin` is not
specified bit for bit across engines, and each writes its file to `--out DIR` only when the generated text has the
pinned size and SHA-256. The generated files are not committed; the repository-root `bench/` directory is ignored by Git.

## 3. Method

1. Build release: `swift build -c release` in `scripts/bench/swift`, `cargo build --release --example bench_storage`
   in `rust`, `bun run build` in `js`.
2. Warm up for 3 seconds, cycling every operation on every input.
3. Interleave: each sample round times every operation once. Each sample repeats the operation until it lasts at
   least 1 ms (2 ms for the corpus and the large inputs) and records the time per repetition.
4. Take 21 samples for the corpus, 31 for the largest and median examples, and 15 for synthetic-2000 and sculpt-4096.
   Each run reports the median per operation and input.
5. Run 3 separate processes per language and runtime. The gate uses the median of the 3 run medians.
6. Ratios are computed only from numbers taken in the same run. If the spread of a gated ratio across the 3 runs is
   more than 15% of its median, run 3 more processes and use the median of all 6.
7. Record per-file kind-2 and bounded decode times for the 293 Examples (report only).

**Receipt.** Each harness writes `bench/receipt-<language>-<runtime>-<os>.json` with the machine model, CPU count,
OS version, the load average at start and end, the toolchain versions (Swift, Node, Bun, Rust, ICU), every run's
medians, the per-file distribution, and the gate results. Release receipts are committed under
`docs/evidence/release-2.1.0/`.

## 4. Gates

Every gated input (corpus aggregate, largest, median, synthetic-2000, sculpt-4096) must satisfy every row. Per-file
ratios inside the corpus are report-only.

| Gate | Swift | TypeScript, Node 24 | TypeScript, Bun 1.4.2 | Rust | Floor from the change |
|---|---|---|---|---|---|
| **G1** kind-2 decode ÷ bounded text decode | ≤ 0.07 | ≤ 0.12 | ≤ 0.25 | ≤ 0.25 | ≤ 0.25 (4 times faster) |
| **G2** kind-2 decode ÷ legacy parse | ≤ 0.15 | ≤ 0.50 | ≤ 0.50 | ≤ 0.45 | < 1.0 (faster than the legacy parser) |
| **K1** kind-1 decode ÷ bounded text decode | ≤ 1.10 | ≤ 1.10 | ≤ 1.10 | ≤ 1.10 | ≤ 1.10 (within 10%) |
| **G4** kind-2 encode ÷ kind-2 decode | ≤ 2.0 | ≤ 3.5 | ≤ 3.5 | ≤ 2.0 | none |
| **G6** size (deterministic) | Examples kind-2 total ≤ 0.98 × canonical; every Example file ≤ its canonical text; synthetic-2000 ≤ 0.995; sculpt-4096 ≤ 0.98 | same | same | same | none |

Report-only: kind-2 encode ÷ text encode; the per-file G1 and G2 distributions (minimum, median, 95th percentile,
maximum); the absolute times.

Changes against the final design's gate, from the two critiques:

- The old G3 (kind-2 decode ÷ kind-1 decode) is deleted. With the fast CRC in kind 1 it is G1 plus a few percent,
  and it failed on correct implementations (Rust synthetic 0.225 against 0.15; Bun corpus 0.152 against 0.10). K1
  replaces it and proves that the 2.0 "binary slower than text" regression is gone.
- TypeScript is gated per runtime. Bun's bounded text decode is about 2.5 times faster than Node's while kind-2 decode
  costs the same, so one G1 ceiling cannot fit both. No row is privileged: every ceiling in the table, including
  TypeScript Node G1 ≤ 0.12, blocks on a runner gated with `--blocking true` once that runner is calibrated, and the
  floors and G6 block as section 6 states. G2 is stable across the two runtimes, so it is the one row with a single
  ceiling shared by Node and Bun; G1 keeps per-runtime ceilings and the 4-times floor.
- TypeScript G2 is ≤ 0.50, not the 0.45 the critique proposed: sculpt-4096 reaches 0.39 to 0.41 (section 5), and the
  largest Example (`conways-game-of-life.3md`, 17,509 B) reached 0.431 on Node in the critic's per-file run
  (`review-perf/ts-node-perfile.json`: 56.18 µs against 130.21 µs). A 0.45 ceiling would leave about 4% margin on that
  file before calibration on slower runners; 0.50 keeps about 16%.
- G4 is kind-2 encode ÷ kind-2 decode. Against the text encoder (about 300 ms on 4 MB in Swift and TypeScript) the
  old G4 measured the text writer, not the binary writer. The new ratio bounds the self-check cost directly.
- Swift ceilings come from the Swift measurements in section 5 (about 2 times the worst aggregate), not from a
  projection.
- G5 (kind 3) is gone with kind 3.

## 5. Evidence for the thresholds

All measurements: Mac Studio, M1 Ultra, 20 cores, shared, load average 24 to 42. Ratios are same-run medians.

| Ratio | Swift 6.3.3 | TypeScript, Node 26.10 | TypeScript, Bun 1.4.0 | Rust 1.95 | Sources |
|---|---|---|---|---|---|
| G1 aggregates | 0.020–0.034 | 0.055–0.072; spec21 prototype 0.061–0.076 | 0.138–0.157; spec21 0.141–0.211 | 0.129–0.229 (final prototype, slicing-by-16); spec21 0.160–0.281 | a, b, c, d, e |
| G1 per Example file | max 0.042 | max 0.140 | max 0.318 (report only) | n/a | a, c |
| G2 aggregates | 0.042–0.066 | 0.23–0.44 (sculpt 0.35); spec21 0.255–0.390 | 0.252–0.276; spec21 0.256–0.413 | 0.15–0.29; spec21 0.19–0.36 | a, b, c, d, e |
| G2 per Example file | max 0.084 | max 0.48 | max 0.48 (report only) | n/a | a, c |
| K1 (fast-CRC kind 1) | 0.999–1.009 | 1.011–1.026; spec21 1.018 | 1.030–1.062; spec21 1.030–1.036 | 1.035–1.051 (slicing-by-16); spec21 1.053–1.086 (slicing-by-8) | a, c, d, e |
| G4 encode ÷ decode | 0.68–1.00 | 1.24–2.09 (source-value self-check); spec21 1.63–2.30 (byte self-check) | spec21 1.15–1.68 | 0.82–1.03; spec21 0.81–0.98 | a, b, d, e |
| Encode ÷ text encode (report only) | 0.018–0.026 | 0.04–0.09 | 0.15–0.19 | 0.09–0.24 | a, b, d, e |

Sources:

- a. Critic's Swift kind-2 reader and writer (`review-perf/swift-proto`), two runs: `review-perf/swift-run1.json`,
  `swift-run2.json`.
- b. Final-design prototypes, three runs each: `binv2/final-work/proto/results/bench-summary.json`.
- c. Critic's per-file and Bun runs: `review-perf/ts-node-perfile.json`, `ts-bun-perfile.json`.
- d. Critic's Rust run with a 2.1-style kind 1: `review-perf/rust-g3/rust-bench-run1.json`.
- e. spec21 correctness prototypes (byte-order keys, byte-based self-check, slicing-by-8 CRC, not tuned):
  `binv2/spec21/proto/results.json`.

Margins and risks:

- **Rust G1 on synthetic-2000** is the tightest row: 0.229–0.233 with the final prototype against the 4-times floor of
  0.25 (about 8% margin), and 0.281 with the untuned spec21 prototype. The Rust port must use the final prototype's
  techniques: slicing-by-16 CRC (2.98 GB/s against 1.89 GB/s for slicing-by-8), a SWAR LF scan, the Phase L bound
  shortcut, no per-plane allocations in the decode loop, and one `str::from_utf8` per string. If calibration
  (section 6) shows less than 10% margin, see "Open questions" in `plan.md`.
- **Rust K1** reaches 1.086 with slicing-by-8; slicing-by-16 brings it to about 1.05.
- **TypeScript G2 on sculpt-4096** reaches 0.39 to 0.41 (legacy parse of uniform voxel lines is fast); the 0.50
  ceiling keeps about 20% margin. **Bun G1 on sculpt-4096** reaches 0.20 to 0.21 against the 0.25 floor.
- **TypeScript G4** reaches 2.30 on Node with the byte-based self-check required by SPEC 11.3.9; 3.5 keeps 1.5 times
  margin.

## 6. Calibration and blocking

The thresholds in section 4 are provisional ceilings from the reference machine. The gating runners are slower,
shared VMs with different toolchains (Node 24 instead of 26), so each runner is calibrated before its ceilings block.

**Calibration.**

1. Calibration runs: on macOS, the first two runs of the workflow; on Linux, the release-tag runs of two consecutive
   releases (see "Per runner").
2. After them, each ceiling becomes `min(provisional ceiling, 2 × the worst value observed in the calibration runs)`,
   rounded up to two significant digits, and never looser than the floor column. The calibrated table is committed
   per runner in `scripts/bench/gate.json`, with the two calibration receipts. A runner without a committed table is
   *uncalibrated*.

**Blocking rules.** `scripts/bench/gate.mjs` sorts every row into one of three classes and exits 1 only when a row
of a blocking class fails:

| Class | Rows | Blocks |
|---|---|---|
| G6 | the size gate | always, on every runner and in every run, whatever `--blocking` says; it is deterministic and also runs in the unit tests (`conformance/structured/sizes.json`) |
| Floors | G1 ≤ 0.25, G2 < 1.0, K1 ≤ 1.10 (the change's acceptance criteria) | only with `--blocking true` |
| Ceilings | the per-language and per-runtime values of section 4, including G4 | only with `--blocking true` and a calibrated table for the runner named by `--runner`; on an uncalibrated runner they are reported against the provisional values |

Every failure that does not block is printed in the table and emitted as a `::warning::` annotation, so it is
visible without failing the job. A receipt whose recorded toolchain differs from the pinned one (Swift 6.3.3, Bun
1.4.2, Rust 1.95.0, Node major version 24) is a configuration error and fails the job on every runner, so a run on
the wrong compiler can never pass or calibrate the gate.

**Per runner.**

- **macOS arm64 (`macos-15`), `--blocking true`.** The floors block from the first run, because they are the
  acceptance criteria and the reference measurements clear them on the same architecture. The ceilings block once
  the two calibration runs are committed. The job is a required check for release branches and release tags.
- **Linux x86_64 (`ubuntu-24.04`, container `swift:6.3.3-noble`), `--blocking false`.** Floors and ceilings are
  reported only, because x86_64 has never been measured: on the reference machine Rust G1 on synthetic-2000 had only
  about 8% margin (0.229 to 0.233 against 0.25) and Rust K1 reached 1.086 with slicing-by-8. After two consecutive
  releases have been measured on it, Linux gets its own calibrated table and its matrix value changes to `true`, in
  a commit that records both receipts.

A calibrated ceiling may be tightened in a later release; loosening it needs a recorded reason in the CHANGELOG.

## 7. Harnesses

| Language | Path | Build and run |
|---|---|---|
| Swift | `scripts/bench/swift/Package.swift` (separate package, executable `threemd-bench`, depends on the repository root by path, so the library's products do not change) | `swift run -c release --package-path scripts/bench/swift threemd-bench --run N --out bench/` |
| TypeScript | `js/scripts/bench-storage.ts` (imports `js/dist`) | `node js/scripts/bench-storage.ts --run N` and `bun js/scripts/bench-storage.ts --run N` |
| Rust | `rust/examples/bench_storage.rs` (no new dependency; `std::time::Instant`) | `cargo run --release --example bench_storage -- --run N` |
| Inputs | `scripts/bench/generate-synthetic.mjs`, `scripts/bench/generate-sculpt.mjs` | `node scripts/bench/generate-*.mjs --out bench/inputs` |
| Gate | `scripts/bench/gate.mjs` reads all receipts and `scripts/bench/gate.json`, prints the table and exits 1 on a blocking failure (section 6) | `bun scripts/bench/gate.mjs bench --runner <os> --blocking <true|false>` |

`fledge.toml` gains tasks `bench-inputs`, `bench-storage` (inputs, then 3 runs of each harness and runtime) and
`perf-gate`, and a lane `perf = ["bench-inputs", "bench-storage", "perf-gate"]`. The perf lane is not part of
`verify`.

## 8. CI workflow

New `.github/workflows/perf.yml`. It pins the same toolchains as `linux.yml` and pins every third-party action to a
commit SHA, as `trust.yml` does. The YAML below is the design; `<sha>` placeholders are filled with the SHAs of the
action versions `linux.yml` already uses, and the macOS Swift installation step is verified on the runner before
the workflow is merged.

```yaml
name: perf

permissions:
  contents: read

on:
  workflow_dispatch:
  schedule:
    - cron: "17 3 * * *"            # nightly
  push:
    branches: ["release/**"]
    tags: ["v2.*"]
  pull_request:
    types: [labeled, synchronize]   # runs when the PR carries the "perf" label

jobs:
  perf:
    if: github.event_name != 'pull_request' || contains(github.event.pull_request.labels.*.name, 'perf')
    strategy:
      fail-fast: false
      matrix:
        include:
          - os: macos-15          # arm64; floors block from run 1, ceilings after the 2 calibration runs, G6 always
            blocking: true
          - os: ubuntu-24.04      # x86_64, container swift:6.3.3-noble; floors and ceilings report until Linux's own
            container: swift:6.3.3-noble  # calibration (two releases), then true; G6 always blocks
            blocking: false
    runs-on: ${{ matrix.os }}
    container: ${{ matrix.container }}
    timeout-minutes: 40
    steps:
      - uses: actions/checkout@<sha>        # v4
      - name: Swift 6.3.3 (macOS)
        if: runner.os == 'macOS'
        run: |                              # swiftly, pinned toolchain
          curl -fsSL https://download.swift.org/swiftly/darwin/swiftly.pkg -o swiftly.pkg
          installer -pkg swiftly.pkg -target CurrentUserHomeDirectory
          ~/.swiftly/bin/swiftly init --quiet-shell-followup --assume-yes
          ~/.swiftly/bin/swiftly install 6.3.3 --use
          # swiftly init edits shell profiles, which later steps do not read; without this line they would build
          # with Xcode's Swift instead of 6.3.3.
          echo "$HOME/.swiftly/bin" >> "$GITHUB_PATH"
      - uses: oven-sh/setup-bun@<sha>       # v2
        with: { bun-version: 1.4.2 }
      - uses: actions/setup-node@<sha>      # v4
        with: { node-version: 24 }          # exact patch recorded in the receipt
      - uses: dtolnay/rust-toolchain@<sha>
        with: { toolchain: 1.95.0 }
      - name: Toolchain versions (each harness also writes them into its receipt; gate.mjs rejects a mismatch)
        run: |
          mkdir -p bench
          { swift --version; node --version; node -p process.versions.unicode; bun --version;
            bun -e 'console.log(process.versions.unicode)'; rustc --version; } | tee bench/toolchains.txt
      - name: Builds
        run: |
          (cd js && bun install --frozen-lockfile && bun run build)
          (cd rust && cargo build --release --locked --example bench_storage)
          swift build -c release --package-path scripts/bench/swift
      - name: arm64_32 compile check (macOS only; Xcode toolchain and watchOS SDK)
        if: runner.os == 'macOS'
        run: xcodebuild -scheme ThreeMD -destination 'generic/platform=watchOS' ARCHS=arm64_32 build
      - name: Inputs, 3 runs per language and runtime, gate
        run: |
          node scripts/bench/generate-synthetic.mjs --out bench/inputs
          node scripts/bench/generate-sculpt.mjs --out bench/inputs
          for run in 1 2 3; do
            swift run -c release --package-path scripts/bench/swift threemd-bench --run $run --out bench
            node js/scripts/bench-storage.ts --run $run --out bench
            bun js/scripts/bench-storage.ts --run $run --out bench
            (cd rust && cargo run --release --locked --example bench_storage -- --run $run --out ../bench)
          done
          bun scripts/bench/gate.mjs bench --runner ${{ matrix.os }} --blocking ${{ matrix.blocking }}
      - uses: actions/upload-artifact@<sha> # v4
        if: always()
        with:
          name: perf-${{ matrix.os }}
          path: |
            bench/*.json
            bench/*.txt
```

Time budget: about 10 minutes of builds and 10 to 15 minutes of measurement per runner (3 runs × 4 runtimes × about
60 seconds), inside the 40-minute timeout. The workflow does not run on ordinary pushes to `main`, so it does not slow
the verify loop. The performance gate leaves the `fledge lanes run verify` lane and `trust.yml` unchanged, except that
G6 also runs in the unit tests.

Platform matrix summary:

| Runner | Architecture | Swift | Node | Bun | Rust | Role |
|---|---|---|---|---|---|---|
| macos-15 | arm64 | 6.3.3 (swiftly) | 24 | 1.4.2 | 1.95.0 | `--blocking true`: G6 and floors from run 1, ceilings after calibration |
| ubuntu-24.04, container `swift:6.3.3-noble` | x86_64 | 6.3.3 | 24 | 1.4.2 | 1.95.0 | `--blocking false`: G6 blocks; floors and ceilings report until two releases are measured |
| Reference machine (manual) | M1 Ultra | 6.3.3 | 26.10 | 1.4.0 | 1.95.0 | the numbers in section 5 |
