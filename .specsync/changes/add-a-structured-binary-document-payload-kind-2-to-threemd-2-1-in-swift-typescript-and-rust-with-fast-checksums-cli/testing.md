---
change: add-a-structured-binary-document-payload-kind-2-to-threemd-2-1-in-swift-typescript-and-rust-with-fast-checksums-cli
artifact: testing
---

# Testing

Every item runs in Swift, TypeScript and Rust unless it says otherwise. Unless its row names another place, it is
wired into `fledge lanes run verify` (and therefore the Linux workflow and Trust). Three kinds of item run elsewhere:
the performance gate runs in its own `perf` lane and workflow (only its size gate G6 also runs in the unit tests);
the ThreeMD 2.0.0 compatibility job runs as `fledge run compat-2-0` and the `compat-2-0` Linux job, not in the
verify lane; and the platform checks that need a particular runner run there (the i686 Rust test in `linux.yml`, the
arm64_32 compile in `perf.yml`). `fledge trust verify` must pass on the exact tip before the work is called
complete. All evidence below is **planned**; implementation replaces "Planned" with the result, the commit and the
counts. "Test-plan section N" means `docs/design/threemd-2.1/test-plan.md`.

## Test layers

| Layer | What it checks | Where |
|---|---|---|
| Goldens | 54 kind-2 files (45 anchors in `conformance/structured/`, 4 `conformance/extensions/*.structured.3mdb`, 2 `Examples/Extensions/*.structured.3mdb`, 3 worked examples). Per port and file: (1) `encode(D, .binary(.none))` equals the file; (2) `decode(file)` equals D, compared on `utf8` and number bits in Swift, `documentsEqual` plus `Object.is` in TypeScript, `==` in Rust; (3) `encode(decode(file))` equals the file; (4) `containerInfo` reports version 1, kind 2, compression 0, flags 0, reserved 0, lengths `bytes − 40` and the manifest CRC; (5) where a `textContainerFile` exists, it decodes to D and `encodeTextContainer(D)` equals it; (6) composition envelopes decode as compositions and re-encode to the profile text; (7) SHA-256 equals the manifest | `DocumentStorageStructuredTests.swift`, `js/test/structured.test.ts`, `rust/tests/structured.rs` |
| Vectors | 156 vectors of `conformance/structured/vectors.json` (142 hostile and edge, 14 limit edges; 29 carry `limits`; 131 errors and 25 `ok`), each decoded under its own limits and required to give `expected` | the same three suites, and the interchange driver |
| Unit checklist | Var boundaries; number forms; CRC; Swift UTF-8 rule; chunked UTF-8; TypeScript two-call chunked decoding; segment scanner; metrics; key order and equivalence; canonical numbers; `containerInfo`; `encodeTextContainer`; writer edges; LZFSE (Swift on Apple) | the same three suites |
| Fuzz | P1 to P8 (below) with fixed seeds | the three suites and the interchange step |
| Limits, cancellation, memory, platforms | cancellation points; amplification; memory under 4 times the input; buffer ownership; 32 concurrent tasks; i686 and arm64_32 arithmetic; Linux | the three suites, `linux.yml`, `perf.yml` |
| Interchange | protocol `3md-interchange-2`, catalog `3md-interchange-catalog-2` (83 cases), nine writer and reader pairs for `binaryHex` and `textContainerHex`, vector replay, fixed protocol cases, `structuredReplay`, files cases | `swift run threemd-interchange` |
| 2.0.0 compatibility | v2.0.0 adapters and v2.0.0 libraries on the anchors and vectors | `fledge run compat-2-0`, `linux.yml` job `compat-2-0` |
| CLI | binary input, storage errors, `convert`, `inspect` | `Tests/ThreeMDTests/CLITests.swift` (macOS and Linux) |
| Element bundle | markers absent, at most 50,000 bytes, drift check | `scripts/check-element-bundle.mjs` |
| Migrations | every existing assertion that assumed `.binary` meant kind 1 (test-plan section 10, `docs/design/threemd-2.1/test-plan.md`) | existing Swift, TypeScript and Rust tests |
| Performance gate | G1, G2, K1, G4, G6 on five gated inputs | `fledge lanes run perf`, `.github/workflows/perf.yml` |

### Differential properties

| ID | Property | CI volume | Release volume |
|---|---|---|---|
| P1 | Totality: every mutated input gives a value or exactly one typed error | 10^4 per port | 10^6 per port |
| P2 | Canonical bijection: `decode(x) = D` implies `encode(D) == x` | all accepted mutants | all accepted mutants |
| P3 | Text agreement: decoded values equal the bounded text decode of their canonical text | all | all |
| P4 | Cross-language outcomes: the three ports give the same code for every mutant and the same bytes on re-encode | 3 × 10^4 | 10^6 |
| P5 | Writer and reader agree: `encode(D, L)` succeeds exactly when `decode(encode(D, L), L)` does | 10^4 | 10^6 |
| P6 | Equivalence with the 2.1 `validate` under standard and random lowered limits, and decode equals the text decode | 10^4 + 3 × 10^4 per port | 10^6 per port |
| P7 | Cross-language writers: same code and identical bytes for documents without equivalent keys or lone surrogates | 2 × 10^4 | 2 × 10^5 |
| P8 | Number canonicality: form selection and bit-exact round trip agree; Rust `canonical_number` equals TypeScript | 10^5 | 10^7 |

P4 and P7 exclude inputs with canonically equivalent keys, LZFSE and code points outside Unicode 13.0. A failing case
is minimized and added to `vectors.json`. Release-volume counts and seeds go to
`docs/evidence/release-2.1.0/fuzz.json`.

## Requirement evidence

| Requirement | Canonical requirement | Planned tests | Evidence |
|---|---|---|---|
| SB-01 Container and payload kinds | REQ-ThreeMD-037 | Golden check 4; vectors for version 2 and kinds 0, 3, 4 and 255; catalog case `invalid-binary-kind-3`; `specsync check --strict` on the SPEC 1.2 contract | Planned |
| SB-02 Decoder check order | REQ-ThreeMD-037 | Container vectors D4 to D13, including kind 3 with a corrupt CRC (the kind wins), `container-decoded-over-2dmax-bad-crc` (the bound wins) and decoded length `Emax − 39`; the D10 boundary limit vector; Swift LZFSE test of the kind-2 bound on compressed input; the compatibility job (2.0 readers stop at D6) | Planned |
| SB-03 Primitive encodings | REQ-ThreeMD-037 | Unit Var tests at 0, 127, 128, 16,383, 16,384, 2,097,151, 2,097,152 and 2^28 − 1 and every V1 to V3 rejection; form selection for the boundary list (−0, ±2^27, 2^24 + 1, 0.1, 2^53 + 2, 5e-324 and others); zigzag edges; vectors for Var, Count and remaining (remaining + 1 with 1- and 2-byte Vars), strings, flags and numbers; Swift Count tests with `Int32` values; P1 | Planned |
| SB-04 Payload layout | REQ-ThreeMD-037 | Golden checks 1 to 3; worked examples (CRCs `8A5B3B70`, `DB5A2326`, `649EB26B`); vectors for count framing, `count-planes-over-pmax-and-remaining` and the S10 trailing byte | Planned |
| SB-05 Key byte order and equivalence | REQ-ThreeMD-037 | Vectors `order-*` (decreasing, identical, NFC order, UTF-16 order), equivalence (`e` + U+0301 with U+00E9, `K` with U+212A, the same for attributes) and the valid mixed set; `worked-keys`; unit comparison of byte order against code point and `utf8` order and of equivalence against `normalize("NFC")`, `nfc()` and `Set<String>`; per-port writer vectors (TypeScript merge payload `00 01 31 00 01 03 65 cc 81 04 6c 61 73 74 00`; Rust `BTreeMap` with both spellings is `invalidDocument`; Swift dictionary keeps one entry) | Planned |
| SB-06 Representability rules | REQ-ThreeMD-037 | Vectors for R2, R3, R9, duplicate z, preamble without planes, G1 to G6 (blank edges with NBSP and U+3000, `@plane` forms, fence cases including a backtick fence holding `~~~`, open fences) and Phase Q (`a'b`, `a"b`, `a''b`, `a'b c'd`, `"x y"`, injected `z=` and `label=`); unit segment scanner against the 2.0 parser on 100,000 random bodies; P6 | Planned |
| SB-07 Canonical encoding and determinism | REQ-ThreeMD-037 | Golden checks 1 and 3; P2; P4 re-encode; P7 identical bytes; nine-pair `binaryHex` equality; `ok` vectors whose `binaryHex` equals the vector file | Planned |
| SB-08 Decoding phases and precedence | REQ-ThreeMD-037 | Precedence vectors (L0 over L3, L3 over L4, L4 over L5, field order across planes, Phase S before Phase L); unit metrics against the real 2.0 writer on every Example and 100,000 generated documents (Swift 10,000); TypeScript result shape (property order, `Object.create(null)`, `__proto__` as an own key); P4 | Planned |
| SB-09 Text equivalence | REQ-ThreeMD-037 | P3, P5 and P6 under standard and lowered limits with 0 disagreements and 0 value mismatches; golden check 2 | Planned |
| SB-10 Writer | REQ-ThreeMD-038 | Unit writer tests: W1b at `Emax` 39, exact `Emax`, `Emax − 1`; −0 payload `00 01 31 00 00 01 01 00 00 01 61`; TypeScript `unsupportedCompression` for identifier 7; TypeScript and Rust `compressionUnavailable` after the self-check; TypeScript lone surrogates in every string field and in a merge-dropped value; P5, P6, P7 | Planned |
| SB-11 Compression bound | REQ-ThreeMD-038 | Swift (Apple) LZFSE round trips, a compressed file whose uncompressed payload exceeds `Emax − 40` (`oversizedOutput`), concatenated and truncated streams, declared sizes `payload ± 1`; the `requiresNoLZFSE` vector on TypeScript, Rust and Swift on Linux; migrated `DocumentStorageCompressionTests` | Planned |
| SB-12 Limits | REQ-ThreeMD-037 | `limits/` vectors (Dmax = T, Lines, Planes, R on the longest directive, Emax = file size, the preamble at R 31 and 30, the D10 boundary, 80 empty planes under `Emax = 1000`); P6 lowered limits; the file-resolver test with a kind-2 branch expecting `tooManyPlanes` | Planned |
| SB-13 Errors | REQ-ThreeMD-037 | `expected` and `errorType` of every vector; composition decode of kind-1, kind-2 and kind-3 envelopes; Swift description tests for `invalidContainer` and `unsupportedPayloadKind`; catalog `expectedError` values; CLI `error.code` values | Planned |
| SB-14 Cancellation | REQ-ThreeMD-037 | Cancellation before entry, mid-CRC on 64 MiB, inside a 1 MiB scalar scan, between UTF-8 chunks of an 8 MiB body, before plane k of 65,536, in Phase L, around a Phase Q parse, mid-emission and mid-self-check, each with no partial output and an identical decode afterwards; chunked UTF-8 tests at 65,535, 65,536, 65,537 and 200,000 bytes with a 4-byte scalar on every boundary position; the TypeScript two-call test (`E2 82` then `AC 62`) on Node and Bun | Planned |
| SB-15 Resource bounds and platforms | REQ-ThreeMD-037 | Amplification test (65,536 planes, Phase Q parse count 0, under 1 second); memory under 4 times the input for the 64 MiB worst cases; `cargo test --target i686-unknown-linux-gnu --test structured`; `xcodebuild ... ARCHS=arm64_32 build` on the macOS perf job; Swift 32-task concurrency (TSan) and Rust threaded tests | Planned |
| SB-16 Compatibility with 2.0 | REQ-ThreeMD-038 | Golden check 5; `encodeTextContainer` byte-equal to every kind-1 anchor and with the 2.0 error order; SHA-256 of every committed 2.0 `.3mdb` unchanged; existing text and kind-1 suites unchanged; nine-pair `textContainerHex`; the compatibility job | Planned |
| SB-17 Compositions and kind 3 | REQ-ThreeMD-038 | Golden check 6; vectors `container-kind-3*`; catalog case `invalid-binary-kind-3`; files cases with kind-2 bundles, a text-container leaf and a refused kind-3 child; `DocumentCompositionCodecTests` on `shared-grove.structured.3mdb` | Planned |
| SB-18 Unicode guarantee | REQ-ThreeMD-039 | `generate.mjs --check` rejects strings outside `unicode-13.0-assigned.json`; P4 and P7 filters; per-port skew vectors (U+0897 after U+0316; U+10D50 and U+10D70) only in single-port suites; Unicode versions recorded in CI and release receipts | Planned |
| SB-19 Public API additions | REQ-ThreeMD-039 | TypeScript export-surface test (exactly the two new names); Rust re-exports and `Send + Sync` assertions; Swift strict-concurrency build with `Sendable` types; doc tests; `specsync check --require-coverage 100` | Planned |
| SB-20 Header inspection only | REQ-ThreeMD-039 | Unit `containerInfo`: no magic, 8 to 39 bytes with the magic, 40 bytes and more including a reserved kind and nonzero flags reported without error; golden check 4; CLI `inspect` | Planned |
| SB-21 Conformance fixtures | REQ-ThreeMD-040 | Golden checks 1 to 7 in every port; all 156 vectors; `generate.mjs --check` in the verify lane, which rebuilds the `sizes.json` inputs with `scripts/bench/generate-synthetic.mjs` and `generate-sculpt.mjs` (each asserts its pinned SHA-256) | Planned |
| SB-22 Differential properties | REQ-ThreeMD-040 | P1 to P8 at CI volume on every push; release volume once on the release tip; `fuzz.json` | Planned |
| SB-23 Interchange protocol 2 | REQ-ThreeMD-040 | Driver totals asserted against `conformance/interchange/README.md`; the five fixed protocol cases (`limits: null`, unknown field, `1.5`, `0`, `limits` on a files request); vector replay with per-vector limits; `structuredReplay`; files cases; `InterchangeConformanceTests` (83 cases, 34 invalid) | Planned |
| SB-24 2.0.0 compatibility job | REQ-ThreeMD-040 | Part 1: v2.0.0 adapters return `unsupportedPayloadKind` for 54 anchors and 4 composition envelopes and `expected20` for 127 vectors; part 2: v2.0.0 library harnesses return `expected20` for 156 vectors under their limits | Planned |
| SB-25 CLI binary input | REQ-ThreeMDCLI-011 | `validate`, `info`, `html`, `links`, `check-links` on `worked-document.3mdb` match the canonical text output and on `canopy.3mdb` work; a corrupt CRC gives the exact stderr line and, with `--json`, `checksumMismatch` with `detail` and `line` absent; kind 3 gives `detail` `"3"`; `invalidText` gives the inner code and line; `invalidDocument` gives its detail; binary standard input; existing text behavior unchanged | Planned |
| SB-26 CLI convert | REQ-ThreeMDCLI-012 | Text to binary, binary to text, binary to text-container and back, byte-equal to the library; extension inference; `--format` override; uninferable output and `-` without `--format`; `--lzfse` with text output; existing output without `--force`; `compressionUnavailable` on Linux; stdout output; no output file after a failure | Planned |
| SB-27 CLI inspect | REQ-ThreeMDCLI-013 | Text, kind 1, kind 2, corrupt CRC and truncated header, plain and `--json`; JSON key snapshots for the three shapes; exit status follows `decode.ok` | Planned |
| SB-28 Element bundle invariant | REQ-ThreeMDElement-022 | `scripts/check-element-bundle.mjs`: markers absent, size at most 50,000 bytes, drift check | Planned |
| SB-29 Performance floors | REQ-ThreeMD-041 | Perf gate rows G1, G2, K1 and G6 on the corpus aggregate, largest and median Example, synthetic-2000 and sculpt-4096 for Swift, Node 24, Bun 1.4.2 and Rust; G6 unit test from `sizes.json` | Planned |
| SB-30 Performance gate in CI | REQ-ThreeMD-041 | `perf.yml` runs on `macos-15` and Linux; two calibration receipts and the calibrated macOS table committed; `gate.mjs` blocking behavior (G6 always, floors with `--blocking true`, ceilings after calibration, unpinned toolchain fails) | Planned |
| SB-31 Fast CRC | REQ-ThreeMD-041 | CRC check value, 10,000 random buffers at every alignment against a bytewise reference, kind-1 anchors unchanged; K1 in the perf gate; Swift `Data` slice decode | Planned |
| SB-32 Rust canonical numbers | REQ-ThreeMD-041 | `numeric-powers.json` test in all three ports (4,318 of 4,318); the 45 numeric vectors; the 3 tie vectors of `rust/tests/extensions.rs`; P8 | Planned |
| SB-33 Swift frozen whitespace set | REQ-ThreeMD-041 | Swift test pinning the 19 W scalars and the 6 excluded spaces; full Swift suite and interchange gate unchanged on macOS and Linux | Planned |
| SB-34 Existing tests and fixtures | REQ-ThreeMD-040 | The migrations of test-plan sections 10.1 to 10.5 (`docs/design/threemd-2.1/test-plan.md`) (writer assertions on `encodeTextContainer` plus kind-2 siblings; kind row 3 for header corruption; the `tooManyPlanes` branch); full suites green | Planned |
| SB-35 Documentation | REQ-ThreeMD-042 | Docs drift checks after `scripts/build-docs-3md.mjs`; an agent review pass (recorded as an agent review, not a human review) that every binary statement names its kind and every ratio names language, runtime and baseline | Planned |
| SB-36 Verification and 2.1.0 release | REQ-ThreeMD-042 | `fledge lanes run verify`, the Linux workflow and macOS suites, the compatibility job and the perf workflow on one tip; `fledge trust verify` (Trust 1.2.2); `specsync check --strict --force --require-coverage 100`; `cargo package --list` and `bun pm pack --dry-run` show 2.1.0; evidence under `docs/evidence/release-2.1.0/` | Planned |

## Manual checks

These are agent checks, recorded as the executing agent's review and never as a human review.

- Read the rendered SPEC.md 11.3 against the worked examples (offsets, CRCs, metrics).
- Read the README, migration guide and release notes for kind names, quoted ratios and the 2.0 reader message.
- Confirm on the release tip that the CI receipts record each runtime's Unicode version and toolchain.

## Pre-implementation evidence

The specification package's prototypes (Mac Studio M1 Ultra, Node 26.10, Bun 1.4.0, Rust 1.95, Swift 6.3.3) already
showed: the 54 goldens byte-identical across TypeScript, Rust and Swift writers and equal to each port's 2.0 bounded
text decode; 156 of 156 vectors in TypeScript and Rust and 155 of 155 in Swift (the LZFSE vector skipped); the 2.0.0
readers of all three languages agreeing on `expected20`; P6 in TypeScript with 0 disagreements on 100,000 documents
under standard limits and 300,000 under lowered limits; P7 with 0 mismatches on 223,875 documents (TypeScript
against Rust); P4 with identical outcomes in all three ports on 34,200 and 102,600 mutants; and the fixed Rust number
spelling equal to TypeScript on 1,003,863 values. These results justify the plan; they are not implementation
evidence and do not fill any row above.
