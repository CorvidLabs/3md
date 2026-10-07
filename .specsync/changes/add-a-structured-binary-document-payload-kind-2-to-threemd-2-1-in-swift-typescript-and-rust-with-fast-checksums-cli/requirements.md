---
change: add-a-structured-binary-document-payload-kind-2-to-threemd-2-1-in-swift-typescript-and-rust-with-fast-checksums-cli
artifact: requirements
---

# Requirements

IDs `SB-01` to `SB-36` are local to this change and stable. They use the `SB` prefix so they never collide with the
SPEC 11.3 rule names (R2, R3, R7, R8, R9, G1 to G6, W1 to W6) or the gate names (G1, G2, K1, G4, G6). Unless a
requirement names a port, it holds in Swift, TypeScript and Rust. "SPEC" means SPEC.md 1.2; `design.md` has the
public API in full. The canonical requirements these become are in `deltas/`: REQ-ThreeMD-037 to REQ-ThreeMD-042,
REQ-ThreeMDCLI-011 to REQ-ThreeMDCLI-013 and REQ-ThreeMDElement-022. The "Requirement evidence" table of
`testing.md` maps each SB ID to its canonical ID. "Test-plan section N" means
`docs/design/threemd-2.1/test-plan.md`.

## Format

- **SB-01 Container and payload kinds.** Kind 2 uses the unchanged version 1 container (40-byte header, magic,
  little-endian lengths, CRC-32/ISO-HDLC) with header byte 10 = 2. Storage decode accepts text, kind 1 and kind 2;
  kinds 0 and 3 to 255 give `unsupportedPayloadKind(k)`. SPEC.md becomes version 1.2 with the section 11, 11.1, 11.2,
  12 and 13 edits and the new sections 11.3 to 11.5; sections 1 to 10 do not change.
- **SB-02 Decoder check order.** A binary input is checked in the order D1 to D14 (SPEC 11.1). D10 bounds the
  declared decoded length by `maximumDecodedBytes` for kind 1 and by `min(maximumEncodedBytes − 40,
  2 × maximumDecodedBytes)` for kind 2, before the CRC and before any decompression allocation. The kind check (D6)
  wins over a corrupt CRC, and the D10 bound wins over a corrupt CRC.
- **SB-03 Primitive encodings.** Readers apply SPEC 11.3.3 exactly: Var is minimal unsigned LEB128 of 1 to 4 bytes
  (V1 to V3); Count(min) divides rather than multiplies and reserves nothing before its check; Str runs Str1 to Str4
  in order; numbers use forms 0 to 3 with the canonical-form rules, and −0 has no encoding; undefined flag bits are
  `invalidContainer`. "Remaining" is measured after the field's own length prefix.
- **SB-04 Payload layout.** The payload is exactly one DocumentRecord (S1 to S10) and its PlaneRecords (P1 to P8), in
  the listed field order, with no offsets, index, string pool, padding or alignment. Trailing bytes are
  `lengthMismatch`; Count framing precedes the S8 `maximumPlanes` check.
- **SB-05 Key byte order and equivalence.** Keys in each map are stored in strictly increasing raw UTF-8 byte order;
  a key not greater than the previous one (including identical bytes) is `invalidContainer`. After the last entry,
  canonically equivalent keys are `invalidDocument`. The TypeScript writer sorts by code point and never with `<`.
- **SB-06 Representability rules.** Readers enforce the frozen whitespace set W, R2 (axis), R3 (metadata keys), R9
  (attribute keys of planes without quote characters), the scalar rule on values, R7 (unique z, at L0), R8 (a
  preamble needs a plane), the segment rules G1 to G6 (a fence closes only with the character that opened it) and
  Phase Q (the directive round trip through the port's 2.0 parser for planes whose keys contain quotes).
- **SB-07 Canonical encoding and determinism.** Every `Document` has exactly one uncompressed kind-2 encoding: for
  any uncompressed kind-2 input `x`, if `decode(x, L)` succeeds, `encode(decode(x, L), .binary(.none), L) == x`.
  With compression 0 the three writers produce identical bytes for every document all three accept; maps with
  canonically equivalent keys and LZFSE output are the only exclusions and never appear in cross-port vectors.
- **SB-08 Decoding phases and precedence.** The decoder runs Phase S, then Phase L (L0 to L5), then Phase Q, and
  reports the first failing check in that order. The canonical text metrics (T, Lines, DirLen, frontmatter line
  lengths) equal the real 2.0 writer's output exactly. The result has the port's 2.0 shape: Swift `Document`,
  TypeScript plain objects in the pinned property order with `Object.create(null)` maps, Rust `Document` with
  `BTreeMap` maps.
- **SB-09 Text equivalence.** Under limits `L`, a kind-2 file decodes exactly when its document passes the 2.1
  `validate` under `L` and the uncompressed container fits `maximumEncodedBytes`, and the decoded value equals the
  bounded text decode of the canonical text (with `maximumEncodedBytes` raised to at least T). The differential fuzz
  shows zero disagreements.
- **SB-10 Writer.** `encode(_, .binary(compression:))` writes kind 2 through W1 to W6: W1b rejects
  `maximumEncodedBytes < 40` with `oversizedInput`; W2 normalizes per port (−0 to +0; TypeScript merges equivalent
  keys after the 2.0 `validateRecords` pre-check and rejects lone surrogates; Rust rejects equivalent keys); W3 emits
  into a buffer capped at `Emax − 40` with checked arithmetic; W4 self-checks with the same reader routine that decode
  uses. Acceptance equals the 2.1 `validate`, except that the file (not T) must fit `Emax`.
- **SB-11 Compression bound.** LZFSE applies to kind 2 on Swift Apple platforms with the CRC over the compressed
  bytes. The kind-2 D10 bound also applies to LZFSE input, so a lowered `maximumDecodedBytes` bounds decompression,
  and a file whose uncompressed payload exceeds `Emax − 40` is `oversizedOutput` even when the compressed file fits.
  TypeScript and Rust report `compressionUnavailable(lzfse)` after the CRC on decode and after the self-check on
  encode.
- **SB-12 Limits.** `DocumentDecodeLimits` is unchanged and no limit is added. For kind 2: `Emax` bounds the input and
  the uncompressed container and is never compared with T; `Dmax` bounds T (L4) and `n ≤ 2 × Dmax` (D10); `Lmax`
  bounds Lines (L5); `Pmax` bounds the plane count at S8, before L5; R bounds each scalar, the preamble (R − 1), each
  body, every frontmatter and directive line, and R ≥ 3.
- **SB-13 Errors.** No error code or enum case is added in any port. Kind-2 failures map to the existing codes as
  SPEC 11.3.12 lists. Inside composition decode and the file resolver, envelope `oversizedInput`, `oversizedOutput`
  and `oversizedRecord` become `profileBytesExceeded` and every other storage code keeps its storage type (Rust:
  `DocumentCompositionError::Storage(code)`). Only the Swift descriptions of `invalidContainer` and
  `unsupportedPayloadKind` change.
- **SB-14 Cancellation.** Decode and encode check cancellation at every point of SPEC 11.3.13, with at most 65,536
  bytes of scanning or validation (or one string construction or Phase Q parse of at most R bytes) between checks,
  and return no document and no bytes when cancelled. Long strings
  are UTF-8 validated in chunks split at scalar boundaries; TypeScript decodes every chunk, including the last, with a
  non-streaming call, so no bytes carry over between strings or calls.
- **SB-15 Resource bounds and platforms.** Phase Q runs only after L3 and L4. The amplification case (65,536 planes
  with quoted keys and labels over R) is rejected before any Phase Q parse in under 1 second; peak memory stays under
  4 times the input for the 64 MiB worst cases. Cap and count arithmetic cannot overflow on 32-bit targets
  (`i686-unknown-linux-gnu`, `arm64_32`).

## Compatibility and Unicode

- **SB-16 Compatibility with 2.0.** Text and kind 1 decode exactly as in 2.0, including leniency and every error.
  Every committed 2.0 `.3mdb` keeps its name and bytes. `encodeTextContainer` writes the 2.0 kind-1 bytes, with the
  2.0 validation and error order. A 2.0 reader stops at D6 with `unsupportedPayloadKind(2)` (or earlier with
  `oversizedInput`) in storage decode, composition decode (Rust: `Storage(UnsupportedPayloadKind(2))`) and the file
  resolver. `isBinary`, the error enums and the limit types do not change; `validate` keeps its signature.
- **SB-17 Compositions and kind 3.** `DocumentCompositionCodec.encode` still writes the readable `3md-composition-1`
  profile. Composition decode accepts text and kind-1 and kind-2 envelopes; the file resolver accepts children of
  text, kind 1 and kind 2. Kind 3 is reserved: no constant names it, and storage decode, composition decode and the
  resolver refuse it with `unsupportedPayloadKind(3)`.
- **SB-18 Unicode guarantee.** Kind-2 bytes never depend on Unicode data. The three ports agree on acceptance, code
  and decoded value for inputs whose strings hold only Unicode 13.0 assigned code points, on the pinned CI toolchains
  (Swift 6.3.3, Node 24, Bun 1.4.2, Rust 1.95 with `unicode-normalization` 0.1.25).
  `scripts/structured/unicode-13.0-assigned.json` (283,506 code points in 686 ranges) is committed; the generator
  rejects anchor and vector strings outside it, and P4 and P7 exclude such inputs. Skew vectors run only in per-port
  suites. No runtime minimum is declared.

## Public API

- **SB-19 Public API additions.** Swift adds `DocumentPayloadKind`, `DocumentContainerInfo`,
  `DocumentStorageCodec.supportedPayloadKinds`, `containerInfo(_:)` and `encodeTextContainer(_:compression:limits:)`.
  TypeScript adds `DocumentPayloadKind` (frozen constants and a number type), the `DocumentContainerInfo` type,
  `supportedPayloadKinds`, `containerInfo` and `encodeTextContainer`, and exports only those two new names from
  `index.ts`. Rust adds `PAYLOAD_KIND_CANONICAL_TEXT`, `PAYLOAD_KIND_STRUCTURED_DOCUMENT`, `SUPPORTED_PAYLOAD_KINDS`,
  `DocumentContainerInfo` (`#[non_exhaustive]`), `container_info` and `encode_text_container`, re-exported from
  `lib.rs`. Swift types are `Sendable`; Rust types are `Send + Sync`.
- **SB-20 Header inspection only.** `containerInfo` reads at most 40 bytes, reports the raw header fields without
  validating them, the payload or the CRC, returns `nil`/`null`/`None` without the magic and throws
  `invalidContainer` when the magic is present with fewer than 40 bytes. No lazy or partial-access API is added.

## Conformance and interchange

- **SB-21 Conformance fixtures.** `conformance/structured/` holds the 45 anchors, the 3 worked examples (CRCs
  `8A5B3B70`, `DB5A2326`, `649EB26B`), `manifest.json`, `sizes.json`, `vectors.json` (156 vectors), `invalid/`,
  `limits/` and `README.md`; four `conformance/extensions/*.structured.3mdb` and two
  `Examples/Extensions/*.structured.3mdb` files are added. SHA-256 values match the golden manifest. Each port's
  writer reproduces every anchor byte for byte and decodes it to the text decode; every vector gives its `expected`
  code under its own limits. `scripts/structured/generate.mjs --check` reproduces every committed byte in the verify
  lane.
- **SB-22 Differential properties.** P1 to P8 run at CI volume on every push and at release volume once on the
  release tip, with zero disagreements, zero cross-port code or byte mismatches and zero re-encode failures; seeds and
  counts are committed to `docs/evidence/release-2.1.0/fuzz.json`.
- **SB-23 Interchange protocol 2.** The gate speaks `3md-interchange-2`. Document and composition requests accept an
  optional `limits` object, validated like the files `documentLimits` and applied only to decoding the input.
  `binaryHex` is kind 2 and the new `textContainerHex` is kind 1. The catalog (`3md-interchange-catalog-2`) has 83
  cases (49 valid, 34 invalid): `binaryFile` is renamed `textContainerFile`, a kind-2 `binaryFile` exists for each of
  the 49 valid cases, `invalid-binary-kind` expects `checksumMismatch` and the new `invalid-binary-kind-3` expects
  `unsupportedPayloadKind`. The driver replays all 156 vectors, the 5 fixed protocol cases and `structuredReplay`
  (P4, P7); every reader consumes every writer's kind 1 and kind 2 in all nine pairs.
- **SB-24 ThreeMD 2.0.0 compatibility job.** `compat-2-0` (a Linux workflow job and a Fledge task, not part of the
  verify lane) shows that the v2.0.0 adapters, sent `3md-interchange-1` requests without limits, return
  `unsupportedPayloadKind` for the 54 kind-2 anchors (and the 4 composition envelopes as composition requests) and
  `expected20` for the 127 limit-free vectors, and that harnesses built on the v2.0.0 libraries return `expected20`
  for all 156 vectors under their limits.

## CLI

- **SB-25 CLI binary input.** `validate`, `info`, `html`, `links` and `check-links` read bytes from a path or `-`.
  Input with the binary magic goes through storage decode with standard limits; other input keeps the 2.0 path and
  output byte for byte. A storage failure prints `threemd: <path>: <code>: <description>` to stderr and exits 1;
  with `--json`, `ErrorOutput` carries `code`, `message`, and `detail` and `line` only when they exist.
- **SB-26 CLI convert.** `threemd convert <input> <output> [--format text|binary|text-container] [--lzfse] [--force]`
  infers the format from `.3md` or `.3mdb`, exits 1 with the usage line when it cannot infer or when `--lzfse` meets
  text output, refuses an existing output without `--force`, writes through a temporary file and rename so a failure
  leaves no output, and writes stdout for `-` only with `--format`. Outputs equal the library encoders.
- **SB-27 CLI inspect.** `threemd inspect [--json] <file>` reads the header with `containerInfo`, decodes the whole
  input with standard limits, reports a failed decode inside its output and exits 0 only when the decode succeeds.
  JSON output has exactly one of the three shapes of `design.md` (binary, truncated binary with `null` header fields,
  text). The web viewer and the element stay text-only.

## Element bundle

- **SB-28 Element bundle invariant.** The freshly built element bundle contains none of `TextDecoder`, `Int32Array`,
  `Float32Array`, `DocumentStorageError`, `Scalar fields cannot contain`, `structured payload` and `getBigUint64`, is
  at most 50,000 bytes, and still matches `web/assets/three-md.js` and `element/dist/three-md.js`. `storage.ts`,
  `structured.ts` and `checksum.ts` have no top-level side effects, and `canonicalNumber` moves to `js/src/number.ts`.

## Performance

- **SB-29 Performance floors.** On every gated input (Examples corpus aggregate, largest and median Example,
  synthetic-2000, sculpt-4096), in Swift, TypeScript on Node 24 and on Bun 1.4.2, and Rust: G1 (kind-2 decode ÷
  bounded text decode) ≤ 0.25; G2 (kind-2 decode ÷ legacy parse) < 1.0; K1 (kind-1 decode ÷ bounded text decode)
  ≤ 1.10. G6 holds: Examples kind-2 total ≤ 0.98 × canonical, every Example ≤ its canonical text, synthetic-2000
  ≤ 0.995, sculpt-4096 ≤ 0.98.
- **SB-30 Performance gate in CI.** `.github/workflows/perf.yml` runs the three harnesses (3 runs per language and
  runtime) on `macos-15` with `--blocking true` (floors from the first run, calibrated ceilings after two committed
  calibration runs, a required check for release branches and tags) and on Linux with `--blocking false`. G6 always
  blocks and also runs in the unit tests. A receipt from an unpinned toolchain fails the job. The perf lane is not
  part of `verify`.

## Prerequisite fixes

- **SB-31 Fast CRC.** Kinds 1 and 2 use a table-driven CRC that consumes at least 8 bytes per step (Swift
  slicing-by-8; TypeScript and Rust slicing-by-16), with the check value `0xCBF43926` and agreement with a bytewise
  reference at every alignment. The Swift decoder no longer copies the header and payload into new `Data` values.
  There is no hardware CRC path. Every kind-1 anchor keeps its bytes.
- **SB-32 Rust canonical numbers.** `storage::canonical_number` and `swift_double` emit the shortest round-trip
  spelling. All 4,318 vectors of `conformance/extensions/numeric-powers.json` (every signed power of two from 2^-1074
  to 2^1023 and ±10^k for k from −30 to 30) match TypeScript; the 45 existing numeric vectors and the 3 tie vectors
  still pass; Rust `validate` accepts the 92 powers of two it rejected in 2.0.
- **SB-33 Swift frozen whitespace set.** An internal `ThreeMDWhitespace` with the 19 W scalars (U+0009, U+0020,
  U+00A0, U+1680, U+2000 to U+200B, U+202F, U+205F, U+3000) replaces `trimmingCharacters(in: .whitespaces)` in
  `Parser.swift`, `Axis.swift`, `DocumentStorageValidation.swift` and `Serializer.swift`. A test pins the 19 scalars
  and the excluded U+0085, U+000B, U+000C, U+180E, U+2028 and U+FEFF. The Swift suite and the interchange gate are
  unchanged on macOS and Linux.

## Migration, documentation and release

- **SB-34 Existing tests and fixtures.** Every existing assertion that assumed `.binary` meant kind 1 (test-plan
  section 10, `docs/design/threemd-2.1/test-plan.md`) keeps its kind-1 check through `encodeTextContainer` and gains
  a kind-2 counterpart; no kind-1 check is deleted. The Examples/Extensions and extensions manifests record
  `payloadKind` and the structured files.
- **SB-35 Documentation.** Every documentation statement about binary payloads names the payload kind; no speed ratio
  is quoted without its language, runtime and baseline, and kind-2 speedups are quoted only against the bounded text
  decode and the 2.1 kind-1 decoder. `docs/MIGRATION-2.1.md` and `docs/RELEASE-2.1.0.md` exist, the CHANGELOG has a
  2.1.0 entry, and the docs drift checks pass with `docs.3md` and `web/docs.3md` regenerated.
- **SB-36 Verification and 2.1.0 release.** On one exact tip: `fledge lanes run verify`, the Linux workflow (Swift,
  TypeScript and Rust suites on Linux) and the macOS suites, the compatibility job and the perf workflow are green;
  pinned Trust 1.2.2 (`fledge trust verify`) and strict SpecSync (`specsync check --strict --force
  --require-coverage 100`) pass; release evidence is committed under `docs/evidence/release-2.1.0/`. The package
  versions read 2.1.0 (`js/package.json`, `rust/Cargo.toml` and `Cargo.lock`, `element/package.json`,
  `editor/vscode/package.json`), and 2.1.0 is released from that tip after the merge with the maintainer bypass that
  Leif chose.

## Acceptance criterion coverage

| Clause of the acceptance criterion in `change.md` | Requirements |
|---|---|
| Kind 2 inside the unchanged version 1 container, specified in SPEC.md 11.3 | SB-01 to SB-04 |
| Byte-identical writers; decode equals the text decode; validity equals 2.0 validation; differential fuzz with zero disagreements | SB-06 to SB-10, SB-21, SB-22 |
| `.binary` writes kind 2; `encodeTextContainer` writes the 2.0 kind-1 bytes; 2.0 files readable byte-unchanged; 2.0 readers fail with `unsupportedPayloadKind(2)` | SB-10, SB-16, SB-24, SB-34 |
| Kind 2 at least 4x faster than bounded text and faster than the legacy parser; kind 1 within 10% thanks to a fast CRC; a CI gate enforces it | SB-29 to SB-31 |
| The CLI reads `.3mdb`, converts and inspects | SB-25 to SB-27 |
| Keys in raw UTF-8 byte order; a lowered `maximumDecodedBytes` bounds decompression; Rust numbers round-trip for all powers of two | SB-05, SB-02, SB-11, SB-32 |
| Nine-pair interchange covers kind 2 and kind 1; Linux and macOS suites pass; Trust 1.2.2 and strict SpecSync on the exact tip; 2.1.0 released | SB-23, SB-36 |
| Compositions keep the readable profile; kind 3 reserved | SB-17 |

The criterion's clause "validity equals the 2.0 canonical-text validation" is met as the 2.1 `validate`, which is the
2.0 `validate` with exactly the two bug fixes of SB-32 (Rust accepts the 92 powers of two it misspelled) and SB-33
(Swift trims with the frozen set W); SPEC 11.3.1 and SB-09 define validity that way, and TypeScript `validate` is
unchanged.

The remaining requirements cover the normative areas the criterion implies: limits (SB-12), errors (SB-13),
cancellation (SB-14), resource bounds (SB-15), Unicode (SB-18), the public API (SB-19, SB-20), the element bundle
(SB-28), the Swift whitespace fix (SB-33) and documentation (SB-35).
