---
change: add-a-structured-binary-document-payload-kind-2-to-threemd-2-1-in-swift-typescript-and-rust-with-fast-checksums-cli
artifact: research
---

# Research

All measurements were taken on one Mac Studio (M1 Ultra, 20 cores), shared and under load (1-minute load average
between 24 and 128 depending on the run), with release builds. Every ratio compares numbers taken in the same run.
Toolchains: Swift 6.3.3, Node 26.10, Bun 1.4.0, Rust 1.95. The raw results live in the lead session's scratch area
(the 2.0 study results, the three design prototypes, the final-design prototypes, the critics' runs and the
specification package's `proto/results.json`); the figures below are copied from them.

## 1. The 2.0 study (baseline)

Exact archive of `v2.0.0` (`ca2d1e3`); median of 3 runs per language.

| Measure | Swift | TypeScript (Node) | Rust |
|---|---|---|---|
| Legacy `parse(text)`, 4.04 MB synthetic | 152 ms | 43 ms | 19 ms |
| Bounded text decode, synthetic | 296 ms | 186 ms | 26 ms |
| Kind-1 binary decode, synthetic | 318 ms (+7.4%) | 231 ms (+24%) | 60 ms (+131%) |
| Per-file median, binary ÷ text (293 Examples) | 1.063 | 1.248 | 2.07 |
| Examples where binary is more than 2% faster | 0 | 0 | 0 |
| Bounded text decode ÷ legacy parse, per-file median | 1.90 | 4.48 | 1.31 |

Causes found by profiling and reading the source: the CRC loops ran at about 90 to 200 MB/s (Rust bitwise, Swift and
TypeScript one table lookup per byte; Node's native `zlib.crc32` gives the same value at about 29 GB/s), and kind 1
re-runs the bounded text decoder, which makes extra passes (a second line split, UTF-8 length counting, record checks).
LZFSE (Swift only) compressed to 27% of the text and was still 3.6% slower than text. Readers accept non-canonical
text inside a kind-1 header. All 295 canonical and binary forms were byte-identical across the three languages, the
interchange gate passed (479 requests, 17,451 imports), the suites passed (Swift 268, TypeScript 157, Rust 49 tests)
and line coverage was 95.51% (Swift) and 99.65% (TypeScript); Rust coverage was not measured.

## 2. Competing designs

Each design was written as a SPEC draft and prototyped in Rust and TypeScript on an exact archive of main `1ebe67d`.

| Design | Layout | Measured result (Rust; TypeScript on Node) | Defect found by its prototype |
|---|---|---|---|
| **Speed** | Version 1 container, kinds 2 and 3; record stream plus one deduplicated, byte-sorted string heap; NFC key order; writer runs the 2.0 `validate` | Synthetic: 6.76 ms against 26.6 ms bounded and 20.0 ms legacy (Rust); 8.79 ms against 186.8 and 44.4 ms (TypeScript). 3.9 to 7.1 times faster than bounded text in Rust, 14 to 36 times in TypeScript. Encode 1.06 to 1.24 times slower than the text encode | Phase order allowed an amplification attack (a 1.6 MB file sharing one label across 65,536 planes: about 11 minutes to reject); the Rust 2.0 number bug (92 powers of two) made Rust and TypeScript disagree on 8 of 20,000 files |
| **Lazy** | Container version 2, an indexed archive: key table, plane index with declared metrics, z-order, CRC per 64 KiB block; opt-in `DocumentArchiveCodec` | Full decode 2.9 to 5.6 times faster than bounded text in Rust (synthetic 8.9 ms) and 11 to 16 times in TypeScript (11.8 ms); open plus one plane 140 to 300 µs | The quote-free attribute-key rule rejected files its own writer produced (12 of 200,000 fuzz cases) |
| **Simple** | Version 1 container, kinds 2 and 3; flat length-prefixed records in document order; raw binary64 numbers; NFC key order | Synthetic: Rust 6.3 ms against 27.6 ms bounded and 20.6 ms legacy (4.4 to 8.7 times faster than bounded); TypeScript 10.7 ms against 195 and 46 ms (11 to 18 times). Encode 5.5 to 33 times faster than the text encode | A per-key quote rule rejected 157 of 5,364 documents that 2.0 text accepts, so its P6 gate failed as written |

Normalized to the bounded text decode of the same run, the flat layout was the fastest in both languages: Rust
synthetic 0.228 (flat) against 0.254 (speed's heap, with a hardware CRC) and 0.345 (lazy archive); Rust corpus 0.134,
0.183 and 0.241; TypeScript synthetic 0.055, 0.096 and 0.0645. The string heap cost most in TypeScript (a sorted-order
check, an every-string-referenced check and a second decode pass).

## 3. Why kind 2 won

The final design took the simple layout and grafted on the measured winners of the other two: tagged coordinates
(speed and lazy), exact canonical-text limit formulas (speed), the exact directive round trip for quoted attribute keys
run after the limit checks (speed, with the amplification fix), and fast checksum loops (all three). It was then
prototyped again in Rust and TypeScript. The grafts cost 0.98 to 1.08 times the plain simple decoder in Rust and 0.99
to 1.07 times in TypeScript.

- **One forward cursor, no offsets.** Structure is about 1% of the bytes; the cost per byte is in strings (UTF-8
  validation, string construction, line scans) and the CRC. Flat records were fastest and the simplest to make
  canonical.
- **Version 1 container, new kind.** A 2.0 reader checks the version, then the kind, before the CRC, so it fails
  cleanly with `unsupportedPayloadKind(2)`. A version 2 container would also fail cleanly but duplicates header code
  for no measured benefit.
- **Tagged numbers.** Of 17,761 coordinates across 297 inputs, 16,803 (94.6%) are integers, 631 binary32-exact and
  327 need binary64; in the Examples 2,660 of 2,686 (99.0%) are integers. Examples total 1,156,441 B with tagged
  numbers against 1,175,082 B with raw binary64.
- **No pool or key table.** Without deduplication kind 2 is 2.7% smaller than text on the Examples, against 2.2% for
  speed's full pool. A shared key table would make the Examples 995 B larger; it saves 3.0 to 5.3 points only on
  4,096-plane Sculpt-style stacks, so it is reserved as a future payload kind.
- **Exact validity.** Phases S, L and Q accept exactly what 2.0 `validate` accepts. Final TypeScript P6: 60,000
  documents under standard limits and 200,000 under lowered limits with 0 disagreements and 0 re-encode failures.
- **Fast writer.** Emit, then self-check with the reader core. Rust encoded the synthetic file in 6.14 ms against
  28.78 ms for a 2.0 text encode; TypeScript in 12.50 ms against 316.29 ms. Writers that called the 2.0 `validate`
  took 33 to 37 ms (Rust) and 333 to 340 ms (TypeScript). The trade-off: for an invalid document the error code
  follows the structured order (it differed from the text writer's code in 68,199 of 193,011 lowered-limit
  rejections and in none of 54,650 standard-limit rejections); the accept or reject decision never differed.
- **No new error codes**, because Swift and Rust error enums are exhaustive. The final Rust and TypeScript decoders
  gave identical codes on 29,300 resealed mutants.

## 4. Prototype speedups per language

**Final-design prototypes** (Rust 1.95, TypeScript on Node 26.10, median of 3 process runs):

| Input | Language | Kind-2 decode | Legacy parse | Bounded text decode | 2.0 kind 1 | Bounded ÷ kind 2 | Kind 2 ÷ legacy |
|---|---|---|---|---|---|---|---|
| synthetic-2000 (4.04 MB) | Rust | 5.95 ms | 20.33 ms | 25.97 ms | 59.56 ms | 4.4 times | 0.29 |
| synthetic-2000 | TypeScript | 10.05 ms | 43.90 ms | 182.38 ms | 228.17 ms | 18.1 times | 0.23 |
| sculpt-4096 (3.03 MB) | Rust | 3.93 ms | 26.20 ms | 30.36 ms | 55.63 ms | 7.7 times | 0.15 |
| sculpt-4096 | TypeScript | 8.39 ms | 24.29 ms | 132.11 ms | 164.38 ms | 15.7 times | 0.35 |
| Examples corpus (1.19 MB) | Rust | 1.89 ms | 9.96 ms | 12.56 ms | 22.78 ms | 6.6 times | 0.19 |
| Examples corpus | TypeScript | 3.75 ms | 13.94 ms | 56.05 ms | 69.92 ms | 14.9 times | 0.27 |
| Largest Example (17.5 KB) | Rust | 23.2 µs | 117.4 µs | 159.9 µs | 303.8 µs | 6.9 times | 0.20 |
| Largest Example | TypeScript | 56.7 µs | 129.7 µs | 785.8 µs | 979.2 µs | 13.9 times | 0.44 |
| Median Example (4.0 KB) | Rust | 3.98 µs | 22.63 µs | 28.00 µs | 61.18 µs | 7.0 times | 0.18 |
| Median Example | TypeScript | 9.94 µs | 30.33 µs | 166.38 µs | 210.67 µs | 16.7 times | 0.33 |

**Swift** (the second critic's reader and writer, which does the work the real port must do, two runs against the
real 2.0 Swift loaders): synthetic 10.0 ms against 291 to 294 ms bounded, 150 to 152 ms legacy and 312 to 314 ms kind 1
(G1 0.034, G2 0.066); sculpt-4096 6.1 ms (0.027, 0.052); corpus 2.75 ms (0.028, 0.052); worst per file G1 0.042 and G2
0.084. With `String(decoding:)` plus byte equality instead of a validator, synthetic fell to 7.5 ms. Encode took 6.8
to 7.9 ms against 305 to 308 ms for the text encode.

**Bun** (critic's run of the final TypeScript prototype on Bun 1.4.0): the bounded text decode is about 2.5 times
faster than on Node (synthetic 71.3 against 179.2 ms) while kind-2 decode costs the same (9.8 against 9.9 ms), so G1
is 0.157 on the corpus and 0.138 on synthetic, with a per-file maximum of 0.318; G2 is stable (Node 0.239 and 0.282,
Bun 0.252 and 0.276).

**Specification package prototypes** (correctness prototypes with byte-order keys, the byte-based self-check and a
slicing-by-8 CRC, not tuned):

| Runtime | Input | G1 | G2 | K1 | G4 |
|---|---|---|---|---|---|
| Node 26.10 | corpus / synthetic / sculpt | 0.076 / 0.062 / 0.071 | 0.300 / 0.257 / 0.387 | 1.018 / 1.018 / 1.019 | 2.005 / 1.633 / 2.303 |
| Bun 1.4.0 | corpus / synthetic / sculpt | 0.159 / 0.141 / 0.202 | 0.271 / 0.273 / 0.392 | 1.030 / 1.034 / 1.034 | 1.676 / 1.486 / 1.177 |
| Rust 1.95 | corpus / synthetic / sculpt | 0.178 / 0.281 / 0.160 | 0.227 / 0.360 / 0.191 | 1.053 / 1.086 / 1.059 | 0.984 / 0.981 / 0.805 |

Summary of the evidence behind the gate (perf-gate section 5, `docs/design/threemd-2.1/perf-gate.md`): G1 aggregates Swift 0.020 to 0.034, Node 0.055 to
0.076, Bun 0.138 to 0.211, Rust 0.129 to 0.229 with the final prototype and slicing-by-16 (0.160 to 0.281 untuned);
K1 with a fast CRC Swift 0.999 to 1.009, Node 1.011 to 1.026, Bun 1.030 to 1.062, Rust 1.035 to 1.051 with
slicing-by-16 (up to 1.086 with slicing-by-8). The tightest row is Rust G1 on synthetic-2000: 0.229 to 0.233 with the
final prototype against the 0.25 floor, about 8% margin.

**CRC throughput** on the synthetic payload: 2.0 loops 119 MB/s (Rust bitwise) and 164 MB/s (TypeScript bytewise);
slicing-by-8 and 16 between 1.5 and 2.7 GB/s; Rust slicing-by-16 2.98 GB/s against 1.89 GB/s for slicing-by-8;
aarch64 `crc32` instructions 8.1 GB/s.

**Size.** Examples: 1,156,441 B kind 2 against 1,188,086 B canonical text (0.973; every file smaller, maximum 0.992).
synthetic-2000: 3,998,362 against 4,037,480 (0.990). sculpt-4096: 2,934,090 against 3,031,345 (0.968). Bodies are
stored verbatim, so uncompressed savings are modest.

## 5. Critique findings that changed the design

Two agent critiques reviewed the final design (both verdict: needs changes), and an agent review pass checked the
specification package. The critics and the reviewer were agents; no human reviewed the design or the package.

Correctness critique:

- A lowered `maximumDecodedBytes` no longer bounded decompression or materialization (a 100 KB LZFSE file could
  inflate to 64 MiB before L4). Fixed by the kind-2 bound `min(Emax − 40, 2 × Dmax)` at D10, with a proof that it
  never rejects a valid file, and by "should not build maps before Phase L".
- NFC key order depended on each runtime's Unicode tables, so writers could disagree and readers reject each other's
  files (U+0897, assigned in Unicode 16, reorders after U+0316 only with newer tables). Fixed by raw UTF-8 byte order
  for keys plus a separate equivalence check, a named Unicode version for the cross-port guarantee, per-port skew
  vectors, and the Swift frozen whitespace set as a prerequisite (Swift trimmed with the live
  `CharacterSet.whitespaces`).
- The "lossless in both directions" claim was false (80 empty planes decode under `Emax = 1000` with `T = 1056`).
  Reworded, and the case became a vector.
- Ambiguous fence closing, the unstated point where "remaining" is measured, the writer cap when `Emax < 40` (W1b),
  the error domain of composition failures, missing Phase Q cancellation checks, the unpinned TypeScript result shape
  and the missing equivalent-key exemption were each made explicit.

Performance and scope critique:

- G3 (kind 2 ÷ kind 1) could not pass once kind 1 had a fast CRC (Rust 0.225 against 0.15). Deleted; K1 (kind 1
  within 10% of bounded text) replaces it.
- TypeScript was calibrated on Node 26 only, and Bun failed G1 at 0.12. TypeScript is now gated per runtime, with G2
  as the stable cross-runtime row.
- Swift was measured (above), so its ceilings were tightened, and G4 became kind-2 encode ÷ kind-2 decode.
- Swift needs no hand-written UTF-8 validator: `String(decoding:)` plus byte equality is exact and 25% faster.
- The plan lacked CLI support for `.3mdb`, and the fixture, test and documentation migrations; both were added.
- Kind 3 was over-scoped for its evidence (one 1.6 KB input, no final Rust prototype, and the public TypeScript
  constructor path measured at 0.41 against a 0.25 gate). Leif then chose kind 2 now and bundles later.
- The TypeScript port must stay free of top-level side effects or it leaks into the element bundle; a marker and size
  check was added.
- Hardware CRC was dropped (it needs `unsafe` in Rust and saves 0.8 ms on 4 MB), the CRC loop style became an
  informative note, and Rust adds `#![forbid(unsafe_code)]`.
- Published ratios now name the runtime and aggregate, and kind-2 speedups are quoted only against the bounded text
  decode and the 2.1 kind-1 decoder.
- A dedicated pinned perf workflow with calibration replaced an unspecified CI gate, and the impossible watchOS
  arm64_32 simulator run became a compile-only check plus an i686 Rust test.
- The critique suggested shipping the fast CRC and Rust number fix as 2.0.1; under Leif's delegation they ship in
  2.1.0 instead.
- W4 must use the byte-based reader core (one predicate), not a check on source values.

Agent specification review (last pass):

- D1 keeps each port's 2.0 order of limit validation and the entry cancellation check.
- The 2.1 `validate` is defined as the 2.0 `validate` with exactly two corrections (Rust number spelling, Swift
  whitespace set W).
- Non-finite coordinates are emitted by W3 and rejected by W4, so the cap and error order are the same in every port.
- TypeScript chunked UTF-8 decoding must never stream the last chunk: on Node 26 and Bun 1.4 a streamed last chunk
  accepts a string ending in `E2 82` and carries the bytes into the next string. The non-streaming rule and two
  call-sequence tests were added.
- The Unicode guarantee is restated for the pinned CI toolchains with the assigned set committed as
  `scripts/structured/unicode-13.0-assigned.json`.
- The interchange request gains an optional `limits` object (input decode only) with five fixed protocol cases; the
  catalog's `invalid-binary-kind` becomes `checksumMismatch` and a kind-3 fixture is added; the integration point,
  the i686 container setup, the two-part compatibility job, the CLI JSON detail fields and the gate's blocking rules
  were specified; W has 19 scalars, not 17.

Prototype findings that changed the design: the Rust number bug became a prerequisite fix (WP2); the amplification
attack moved Phase Q after Phase L; the simple and lazy quote rules were replaced by the exact Phase Q round trip; and
4 TypeScript P6 disagreements (lone surrogates in values that a key merge drops) led to the W2 pre-check.

## 6. What was ruled out

| Option | Why it was ruled out | Evidence |
|---|---|---|
| A lazy or partial-access API | Leif's decision. Speed's validated view cost 0.54 to 0.92 of a full decode in Rust; the flat layout's best single-plane read still cost 0.27 to 0.43 because the CRC covers the whole file; lazy's archive loaded one plane in 139 µs (Rust) but made the full decode 50% slower in Rust and 18% in TypeScript and brought block tables, declared metrics, partial-validity semantics and a writer and reader mismatch bug. A full 4 MB decode takes 6 to 10 ms (projected about 100 ms in Rust and 170 ms in TypeScript at 64 MiB) | Section 2; final design A.2 item 10 |
| Hardware CRC | Needs `unsafe` `std::arch` intrinsics in a crate with no `unsafe`, has no Swift or TypeScript equivalent, and saved 0.8 ms on 4 MB (5.95 to 5.13 ms) while slicing tables already pass every gate | Critique 1; CRC throughput above |
| Payload kind 3 now | Leif's decision (bundles later). One 1.6 KB input as evidence; no final Rust prototype; the frozen public TypeScript constructor path measured 71.1 µs against 172.6 µs readable (0.41), failing the proposed 0.25 gate; kind-2 envelopes already give bundles a binary container | Critique 1; final design A.2 item 9 |
| Indexed and split layouts | Lazy's indexed archive (index, key table, separate property and body regions) and speed's separate string heap both lost to flat records (Rust synthetic 0.345 and 0.254 against 0.228 of bounded). No purely columnar layout was prototyped; the two split layouts that come closest were measured and lost. An indexed archive stays a candidate future kind | Section 2 |
| A string pool or key table | Made the Examples larger (key table, +995 B) or only slightly smaller (pool, 2.2% against 2.7%), added an amplification risk, a byte-deduplication pitfall in Swift and a slower TypeScript path | Final design A.2 item 4 |
| Container version 2 | Fails cleanly in 2.0 too, but duplicates header code for no measured benefit | Final design A.2 item 2 |
| NFC key order in the payload | Writer bytes would depend on runtime Unicode tables | Critique 0 |
| Compression by default | LZFSE exists only in Swift on Apple platforms, so a compressed default would not be portable (TypeScript and Rust report `compressionUnavailable`); LZFSE bytes are outside the byte-identity contract; in 2.0 LZFSE loaded 3.6% slower than text. Uncompressed stays mandatory, LZFSE optional, and compression identifiers 2 to 255 are reserved for a portable codec | 2.0 study; SPEC 11.3.10 and 11.5 |
| Changing `.binary` to stay kind 1 | Kind 1 is slower than text in every language; Leif chose kind 2 as the default, with `encodeTextContainer` for 2.0 readers | Section 1 |
| A 2.0.1 patch release for the prerequisite fixes | Decided under Leif's delegation: they ship in 2.1.0 | `context.md` |
| A hand-written Swift UTF-8 validator | `String(decoding:)` plus byte equality is exact on every deployment target and faster | Critique 1 |
