---
change: add-a-structured-binary-document-payload-kind-2-to-threemd-2-1-in-swift-typescript-and-rust-with-fast-checksums-cli
artifact: plan
---

# Plan

Target: ThreeMD 2.1.0 (SPEC 1.2) in Swift, TypeScript and Rust. Format: SPEC.md 11.3 to 11.5. API: `design.md`.
Tests: `testing.md`. Requirements: `requirements.md` (SB-01 to SB-36). The specification package's goldens and
prototypes are the fixture source for WP1. "Test-plan section N" means `docs/design/threemd-2.1/test-plan.md` and
"perf-gate section N" means `docs/design/threemd-2.1/perf-gate.md`, the committed copies of the package's test plan
and performance gate (WP0).

## Ground rules

- Branch `leif/structured-binary-2.1` from main `b7ac436` (`1ebe67d` plus one commit that touches only `.specsync/`;
  the goldens and prototypes were generated from the `1ebe67d` archive, and no file they read differs).
- This one SpecSync change carries all the work. Lifecycle records name the executing agent and never claim a human
  review that did not happen.
- Use the pinned Fledge 1.7.2, SpecSync 6.0.0 and Trust 1.2.2 binaries (AGENTS.md). Reach for `fledge run <task>` and
  `fledge lanes run verify` first. `fledge trust verify` must pass on the exact tip before the work is called
  complete, and no lifecycle, contract, risk or provenance gate may be weakened.
- Every package keeps `fledge lanes run verify` green when it lands. WP3 to WP6 land together in one integration
  merge (below). A package that would break another directory's tests carries those test changes or waits for the
  package that owns them.
- Swift follows the CorvidLabs conventions: explicit access control, no force unwraps, Swift 6 strict concurrency,
  `Sendable` types. TypeScript runs with Bun and `bun test`. Rust adds no dependency.
- Merging, tagging and publishing happen only when every gate is green, through the merge with the maintainer bypass
  that Leif chose, followed by the 2.1.0 release. No work package below merges, tags or publishes on its own.

## Owners and directory ownership

| Owner | Directories it owns in this change |
|---|---|
| Spec lead (root) | `SPEC.md`, `specs/`, `.specsync/changes/<this change>/` |
| Fixtures | `conformance/structured/`, the new `*.structured.3mdb` files, `conformance/extensions/numeric-powers.json`, `conformance/interchange/invalid-binary-kind-3.3mdb`, `scripts/structured/`, `scripts/bench/generate-synthetic.mjs`, `scripts/bench/generate-sculpt.mjs`, the `/bench/` entry in `.gitignore` |
| Swift | `Sources/ThreeMD/`, `Sources/CLI/`, `Tests/ThreeMDTests/` except the interchange tests |
| TypeScript | `js/`, `scripts/check-element-bundle.mjs` |
| Rust | `rust/` except `rust/examples/interchange.rs` |
| Interchange | `Sources/ThreeMDInterop/`, `js/scripts/interchange.mjs`, `rust/examples/interchange.rs`, `conformance/interchange/` except the WP1 fixture `invalid-binary-kind-3.3mdb`, the existing manifests in `conformance/extensions/` and `Examples/Extensions/`, `Tests/ThreeMDTests/InterchangeConformanceTests.swift` |
| Tooling and CI | `.github/workflows/`, `fledge.toml`, `scripts/bench/` except the two WP1 input generators, `scripts/compat/`, `js/scripts/bench-storage.ts`, `rust/examples/bench_storage.rs` |
| Docs and release | `README.md`, `CHANGELOG.md`, `ROADMAP.md`, `AGENTS.md`, `docs/` except `docs/design/threemd-2.1/` (spec lead, WP0), `Examples/*.md`, `js/README.md`, `element/README.md`, `editor/vscode/README.md`, `docs.3md`, `web/docs.3md`, version fields |

Files touched by more than one package, in order: `Tests/ThreeMDTests/ExtensionConformanceTests.swift` and
`DocumentStorageTests.swift` (WP5, then WP6); `fledge.toml` (WP6, WP7, then WP11); `specs/ThreeMDCLI/` (WP0, then
WP8); `scripts/check-element-bundle.mjs` (WP2, then WP3 if the budget moves); `specs/ThreeMD/ThreeMD.spec.md` (WP0,
then the WP2 TypeScript and Rust commits, then the integration merge; see "Staged contract entries" under WP0).

## Order

```
WP0 spec and lifecycle ──┬─> WP1 fixtures ───────────────┐
                         └─> WP2 prerequisite fixes ──────┤
                                                          ├─> WP3 TypeScript ─┐
                                                          ├─> WP4 Rust ───────┼─> WP6 interchange ─┬─> WP12 verification
                                                          └─> WP5 Swift ──────┤   WP7 2.0.0 job    │   and release readiness
                                                                              ├─> WP8 CLI          │
                                                                              ├─> WP9 docs ────────┤
                                                                              ├─> WP10 versions ───┤
                                                                              └─> WP11 perf gate ──┘
```

WP3, WP4 and WP5 run in parallel on disjoint directories. WP6 to WP11 can run in parallel once the three ports are in.

**Integration point.** Each port changes outputs that the interchange step compares across languages: `.binary`
becomes kind 2 (the nine-pair `binaryHex` comparison), and a kind-2 reader turns the committed
`invalid-binary-kind.3mdb` from `unsupportedPayloadKind` into `checksumMismatch` (one `expectedError` per catalog
case). The interchange step can therefore be green only when all three ports and the WP6 catalog, fixture and adapter
changes are present together. WP3, WP4 and WP5 are each developed and reviewed on their own branch with their own
suites green, then merged into `leif/structured-binary-2.1` together with WP6 in one integration merge. `fledge lanes
run verify` must be green on that merge and on every commit after it.

---

## WP0. Spec text and lifecycle (owner: spec lead)

Files:

- `SPEC.md`: Parts A, B and C of the specification text (header 1.2; sections 11, 11.1, 11.2; new 11.3 to 11.5;
  section 12 and 13 edits). Sections 1 to 10 do not change.
- `specs/ThreeMD/ThreeMD.spec.md`, `requirements.md`, `testing.md`, `tasks.md`: the new public API (`design.md`), the
  behavior change of `.binary`, the error mapping, the Rust number fix and the frozen whitespace set.
- `specs/ThreeMDCLI/*`: binary input for every subcommand, `convert`, `inspect`, the new error cases.
- `specs/ThreeMDElement/*`: the bundle invariant (no storage code, size budget).
- `docs/design/threemd-2.1/test-plan.md` and `docs/design/threemd-2.1/perf-gate.md`: the specification package's
  test plan and performance gate, committed so that every "test-plan section" and "perf-gate section" reference in
  this change, the specs, `conformance/structured/README.md` and `scripts/structured/generate.mjs` resolves in the
  repository. Each starts with a note that maps the package's own paths to repository paths and lists the few
  adaptations made on copying.
- `.specsync/changes/<this change>/`: this definition (all eight artifacts, the canonical deltas for the three
  affected specs) and `affected_paths` extended with `Examples/README.md`, `Examples/LinkedVillage/README.md`,
  `element/README.md`, `editor/vscode/README.md` and `.gitignore` (`scripts/structured/`, `scripts/bench/` and
  `scripts/compat/` are already covered by `scripts`). `Package.swift` and `js/package.json` stay out: no test
  target is added and no runtime minimum is declared.

**Staged contract entries.** `specsync check --strict --require-coverage 100` (which Trust runs after the verify
lane) fails on a `files:` entry whose source does not exist and on a Public API row whose export does not exist. So
WP0 adds to `specs/ThreeMD/ThreeMD.spec.md` the prose, invariants, error mapping and behavioral examples of 2.1, and
the remaining contract entries land in the commits that create their source:

- The WP2 TypeScript commit that creates `js/src/number.ts` and `js/src/checksum.ts` adds both to `files:` and
  documents any export they add (`canonicalNumber` already has a row; a TypeScript CRC export joins the `crc32`
  row). The WP2 Rust commit that creates `rust/src/checksum.rs` adds it to `files:`. This is the one exception to
  the spec lead owning `specs/`.
- The integration merge (WP3 to WP6) adds `Sources/ThreeMD/DocumentStorageStructured.swift`, `js/src/structured.ts`
  and `rust/src/structured.rs` to `files:`, and the rows below. The three port branches do not edit the spec, so
  they cannot conflict there. The first fifteen rows go after the `compressionFailed` row, the last five after the
  `HEADER_BYTE_COUNT` row:

| Export | Contract |
|--------|----------|
| `DocumentPayloadKind` | Swift RawRepresentable, Hashable, Sendable, CustomStringConvertible struct for header byte 10 that represents every UInt8, so future kinds stay additive; TypeScript frozen constant object with a number type alias. |
| `canonicalText` | Payload kind 1: canonical UTF-8 3md text behind the binary header (ThreeMD 2.0, SPEC.md 11.1). |
| `structuredDocument` | Payload kind 2: structured document records (ThreeMD 2.1, SPEC.md 11.3). |
| `description` | DocumentPayloadKind name: canonicalText, structuredDocument or reserved(N). |
| `DocumentContainerInfo` | Swift Hashable, Sendable struct, TypeScript readonly interface and Rust non-exhaustive Copy struct of the raw fixed header fields, reported without validating them, the payload or the checksum. |
| `payloadKind` | DocumentContainerInfo payload kind byte; Swift DocumentPayloadKind, TypeScript number. |
| `compression` | DocumentContainerInfo raw compression identifier; compare it with DocumentCompression.rawValue. |
| `flags` | DocumentContainerInfo raw feature flags. |
| `reserved` | DocumentContainerInfo raw reserved field. |
| `encodedPayloadByteCount` | DocumentContainerInfo declared encoded payload byte count; Swift UInt64, TypeScript bigint. |
| `decodedPayloadByteCount` | DocumentContainerInfo declared decoded (uncompressed) payload byte count; Swift UInt64, TypeScript bigint. |
| `checksum` | DocumentContainerInfo declared CRC-32/ISO-HDLC value, not verified by inspection. |
| `supportedPayloadKinds` | Payload kinds this release decodes, canonicalText and structuredDocument: Swift Set<DocumentPayloadKind>, TypeScript frozen readonly number[] [1, 2]. |
| `containerInfo` | containerInfo(_ data: Data) throws -> DocumentContainerInfo? reads at most the first 40 bytes; nil (TypeScript null) without the binary magic; invalidContainer when the magic is present and fewer than 40 bytes exist. |
| `encodeTextContainer` | encodeTextContainer(_:compression:limits:) throws -> Data writes payload kind 1, byte-identical to the ThreeMD 2.0 `.binary` output, with the 2.0 binary writer's validation and error order; TypeScript takes optional compression, limits and AbortSignal. |
| `PAYLOAD_KIND_CANONICAL_TEXT` | Rust payload kind 1 constant, canonical UTF-8 text. |
| `PAYLOAD_KIND_STRUCTURED_DOCUMENT` | Rust payload kind 2 constant, structured document records. |
| `SUPPORTED_PAYLOAD_KINDS` | Rust [u8; 2] payload kinds this release decodes, [1, 2]. |
| `container_info` | Rust header-only inspection: Ok(None) without the binary magic, Err(InvalidContainer) when the magic is present and fewer than 40 bytes exist. |
| `encode_text_container` | Rust payload kind 1 writer with explicit compression, limits and OperationOptions, byte-identical to the 2.0 encode with Binary(c) and with its errors. |

Done when: `specsync check --strict --force --require-coverage 100` passes on the WP0 commit, and on every later
commit because each commit above adds its own entries; the change validates in its current state; the SPEC diff is in
the delivery pull request for Leif to read (context.md records why the merge does not wait for a separate review).

## WP1. Shared fixtures (owner: fixtures)

Files (all new; no existing manifest is edited here, so no existing test changes):

- `conformance/structured/`: the 45 anchors and 3 worked examples, `manifest.json` (schema `3md-structured-golden-1`,
  paths rewritten to repository locations), `sizes.json`, `vectors.json` (schema `3md-structured-vectors-1`, 156
  vectors merged from the invalid and limits manifests), `invalid/*.3mdb`, `limits/*.3mdb`, `README.md` (layout,
  schemas, the annotated worked examples).
- `conformance/extensions/{document-unicode,unicode-key-order,unicode-source-collision,composition-instances}.structured.3mdb`.
- `Examples/Extensions/{canopy,shared-grove}.structured.3mdb`.
- `conformance/extensions/numeric-powers.json` (schema `3md-canonical-numbers-1`, 4,318 vectors, 4,316 distinct
  values).
- `scripts/structured/unicode-13.0-assigned.json` (schema `3md-unicode-assigned-1`): the DerivedAge 13.0 assigned
  ranges of SPEC 11.3.15, read by the generator and by the P4 and P7 filters.
- `scripts/structured/generate.mjs`: the port of the prototype generator and size script onto the built TypeScript
  library. No prototype is vendored. Until WP3 lands, the generator runs through `--library PATH` with an
  uncommitted adapter that presents the specification package's TypeScript prototype under the 2.1 API names; after
  WP3 it must reproduce every committed byte with the real library (`js/dist/index.js`, the default) in `--check`
  mode, which WP6 wires into the verify lane. It fails when any anchor or `vectors.json` string holds a code point
  outside the Unicode 13.0 set.
- `conformance/interchange/invalid-binary-kind-3.3mdb` (113 bytes, SHA-256
  `5e2547b1950d7008e0c009a3f7710f4119afb412a6ec6cc489eb66593c0a1357`), written by the generator. No test reads it
  until WP6, which owns only the catalog manifest edit that adds the `invalid-binary-kind-3` case.
- `scripts/bench/generate-synthetic.mjs` and `scripts/bench/generate-sculpt.mjs` (moved here from WP11): the two
  large performance-gate inputs of perf-gate section 2. Each runs under Node, writes its file to `--out DIR` and
  refuses to write unless the generated text has the pinned size and SHA-256 (`synthetic-2000.3md`, 4,037,470 B,
  `b64e50d3...`; `sculpt-4096.3md`, 3,031,335 B, `dae524d9...`). Without `--inputs`, `generate.mjs` runs them into a
  temporary directory, so the `sizes.json` check needs no WP11 file and no committed input.
- `.gitignore`: `/bench/`, the repository-root directory where the generators and the WP11 harnesses write when run
  by hand (anchored, so `scripts/bench/` stays tracked).

Done when: the files are committed in a commit of their own, SHA-256 values match the golden manifest, both input
generators reproduce their pinned SHA-256, and the verify lane is green (no test reads the fixtures yet).

## WP2. Prerequisite fixes (owners: Swift, TypeScript, Rust, in parallel)

These change no format bytes and can land before the ports. They ship in 2.1.0; there is no 2.0.1.

- **Fast CRC for kind 1.**
  - Swift: `DocumentStorageChecksum` becomes a slicing-by-8 loop over `UnsafeRawBufferPointer`; `decode` stops copying
    `Data(data.dropFirst(40))` and `Data(data.prefix(36))`.
  - TypeScript: new `js/src/checksum.ts` (lazy slicing-by-16 `Int32Array` tables), used by `storage.ts`.
  - Rust: new private `rust/src/checksum.rs` (`const` slicing-by-16 tables); `#![forbid(unsafe_code)]` in `lib.rs`.
  - Done: every kind-1 anchor byte-identical; CRC check value and random-buffer tests; K1 ≤ 1.10 measured with the
    bench scripts on the reference machine.
- **Rust number spelling.** Fix `storage::canonical_number` and `swift_double`; add a test that reads
  `conformance/extensions/numeric-powers.json`; the existing tie test still passes. Done: 4,318 of 4,318 vectors and
  the 45 existing vectors match; the CHANGELOG notes the bug fix (92 powers of two).
- **Swift frozen whitespace.** Internal `ThreeMDWhitespace` (set W, scalar-wise trim) replaces
  `trimmingCharacters(in: .whitespaces)` in `Parser.swift`, `Axis.swift`, `DocumentStorageValidation.swift` and
  `Serializer.swift`. Done: a test pins all 19 W scalars (U+0009, U+0020, U+00A0, U+1680, the 12 scalars U+2000 to
  U+200B, U+202F, U+205F and U+3000) and the excluded spaces (U+0085, U+000B, U+000C, U+180E, U+2028, U+FEFF); the full
  Swift suite and the interchange gate are unchanged on macOS and Linux.
- **TypeScript bundle hygiene.** Move `canonicalNumber` to `js/src/number.ts` (re-exported from `storage.ts`); audit
  `storage.ts` for top-level side effects; extend `scripts/check-element-bundle.mjs` with the markers and the
  50,000-byte budget. Done: the element bundle is byte-identical to 2.0.0 and the new assertions pass.

## WP3. TypeScript port (owner: TypeScript)

Files:

- `js/src/structured.ts` (new, internal): cursor (Var, Count, Number forms, Str), chunked UTF-8 decoding with a lazy
  fatal `TextDecoder` (chunks split at scalar boundaries, every chunk including the last decoded by a non-streaming
  call, so the shared decoder never holds pending bytes), segment rules on strings, byte-order key checks,
  equivalence with `normalize("NFC")`, R2, R3, R9, Phase L metrics with the bound shortcut, Phase Q through `parse` on
  a minimal document, `readDocument` (materialize flag), the writer (cap, code point key order, merge, the W2
  pre-check with lone-surrogate rejection). No top-level side effects.
- `js/src/storage.ts`: `DocumentPayloadKind`, `DocumentContainerInfo`, `supportedPayloadKinds`, `containerInfo`,
  `encodeTextContainer`, `.binary` routed to kind 2, kind dispatch with the D10 bound.
- `js/src/index.ts`: the two new exports.
- `js/test/structured.test.ts` (new): golden checks, vectors, the unit checklist, P1 to P6 at CI volume,
  cancellation, buffer ownership.
- Migrations of test-plan section 10.3 (`docs/design/threemd-2.1/test-plan.md`) inside `js/test/` (not
  `js/scripts/interchange.mjs`, which is WP6).

Done when: every golden is byte-identical and decodes to the text decode; all 156 vectors give their codes under their
limits; the two chunked-UTF-8 tests pass on Node and Bun; P6 at CI volume shows 0 disagreements; `bun run typecheck &&
bun run build && bun test` passes; the element bundle check passes.

## WP4. Rust port (owner: Rust)

Files:

- `rust/src/structured.rs` (new, private): as WP3, with `str::from_utf8` per string (chunked above 65,536 bytes), a
  SWAR LF scan, `unicode-normalization` for equivalence and Phase Q order, `HashSet<u64>` for L0, checked arithmetic.
- `rust/src/storage.rs`: constants, `DocumentContainerInfo` (`#[non_exhaustive]`), `container_info`,
  `encode_text_container`, `Binary(c)` routed to kind 2, kind dispatch.
- `rust/src/lib.rs`: re-exports.
- `rust/tests/structured.rs` (new): golden checks, vectors, unit checklist, property tests with a seeded in-crate
  generator, the P4 blob replay, cancellation, `Send + Sync`.
- Migrations of test-plan section 10.4 (`docs/design/threemd-2.1/test-plan.md`) inside `rust/tests/` (not
  `rust/examples/interchange.rs`).

Done when: as WP3, plus `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`, `cargo test --all-targets`,
`cargo test --doc` and `cargo test --target i686-unknown-linux-gnu --test structured` pass. The i686 run happens in the
`swift:6.3.3-noble` Linux container after `rustup target add i686-unknown-linux-gnu` and
`apt-get install -y gcc-multilib`, with `CARGO_TARGET_I686_UNKNOWN_LINUX_GNU_LINKER=clang` (the image has clang but no
`cc`); WP7 makes the same steps permanent in `linux.yml`. The port uses the measured Rust techniques (slicing-by-16,
SWAR LF scan, Phase L bound shortcut, no per-plane allocation in the decode loop, one `str::from_utf8` per string), and
WP4 measures G1 on synthetic-2000 before WP11.

## WP5. Swift port (owner: Swift)

Files:

- `Sources/ThreeMD/DocumentStorageStructured.swift` (new): reader over `withUnsafeBytes` with `loadUnaligned`;
  `String(decoding:)` plus byte equality for UTF-8 (chunked); `memchr` segment scan; byte-order keys with
  `utf8.lexicographicallyPrecedes`; `Set<String>` equivalence; R2 on `utf8`; Phase L; Phase Q through `Parser` with
  keys in `String <` order; `Set<UInt64>` for L0; the writer with keys sorted by `utf8`.
- `Sources/ThreeMD/DocumentStorage.swift`: `DocumentPayloadKind`, `DocumentContainerInfo`, the updated comments and
  descriptions.
- `Sources/ThreeMD/DocumentStorageCodec.swift`: `supportedPayloadKinds`, `containerInfo`, `encodeTextContainer`,
  `.binary` routed to kind 2, kind dispatch with the D10 bound; `Data` slices with a nonzero `startIndex` handled.
- `Sources/ThreeMD/DocumentStorageCompression.swift`: LZFSE for kind 2 with the D10 cap.
- `Tests/ThreeMDTests/DocumentStorageStructuredTests.swift` (new): golden checks, vectors, unit checklist, property
  tests, LZFSE round trips (Apple), cancellation through `Task`, the concurrency test.
- Migrations of test-plan section 10.1 (`docs/design/threemd-2.1/test-plan.md`), except
  `InterchangeConformanceTests.swift` and the manifest-field parts of `ExtensionConformanceTests.swift` and
  `DocumentStorageTests.swift` lines 12 to 40 (WP6).

Done when: as WP3, plus `swift-format lint --strict`, `swift build` and `swift test` on macOS and in the Linux
container, and the TSan job.

## WP6. Interchange protocol 2 and fixture wiring (owner: interchange)

Files:

- `Sources/ThreeMDInterop/{Protocol,SwiftAdapter,main,FileCases,FileBundleHost}.swift`, `js/scripts/interchange.mjs`,
  `rust/examples/interchange.rs`: schema `3md-interchange-2`; the optional `limits` object on document and
  composition requests, validated like the files `documentLimits` and applied to the input decode only;
  `textContainerHex`; formats with `textContainer`; vector replay with per-vector limits, the `binaryHex` check for
  `ok` vectors and the LZFSE skip; the five fixed protocol cases; `structuredReplay` for P4 and P7; kind-1 and kind-3
  files cases; `--text-container` in the bundle host.
- `conformance/interchange/manifest.json` (schema `3md-interchange-catalog-2`: `binaryFile` renamed
  `textContainerFile`, a new kind-2 `binaryFile` for 49 cases, `vectorsFile`; `invalid-binary-kind` expects
  `checksumMismatch`; new case `invalid-binary-kind-3` expecting `unsupportedPayloadKind`; 83 cases),
  the new case that names `conformance/interchange/invalid-binary-kind-3.3mdb` (the fixture itself lands in WP1),
  `README.md` (83 source cases, 49 valid and 34 invalid, and the new request and output totals), `PROTOCOL.md`
  (protocol 2, including `limits`).
- `conformance/extensions/manifest.json`: `structuredFile`, `structuredBytes`, `documentStructuredFile`,
  `sourceCollisionStructuredFile`, `payloadKind`.
- `Examples/Extensions/manifest.json`: the two structured files with `bytes`, `sha256` and `payloadKind`; existing
  entries gain `payloadKind: 1`.
- `Tests/ThreeMDTests/InterchangeConformanceTests.swift` (catalog count 83, invalid count 34, the rows of test-plan
  section 10.1), the manifest parts of `ExtensionConformanceTests.swift`, `DocumentStorageTests.swift` lines 12 to
  40, and the TypeScript and Rust extension tests that read the new fields.
- `fledge.toml`: the `scripts/structured/generate.mjs --check` step in the verify lane. It needs no committed input:
  the WP1 generators rebuild the two large `sizes.json` inputs in a temporary directory.
- Sequencing: `invalid-binary-kind` fails `testEveryInvalidCatalogSourceReportsItsRequiredTypedError` and the
  interchange driver as soon as a port decodes kind 2, so the catalog change (including the `invalid-binary-kind-3`
  case) and the Swift test update are part of the integration merge with WP3 to WP5.

Done when: `swift run threemd-interchange` passes with the new totals (nine pairs for `binaryHex` and
`textContainerHex`, all 156 vectors under their limits, the fixed protocol cases, P4 and P7 at CI volume); every
reader consumes every writer's kind 1 and kind 2; the generator check passes.

## WP7. ThreeMD 2.0.0 compatibility job (owner: tooling and CI)

Files: `.github/workflows/linux.yml` (new job `compat-2-0`; also the `rustup target add i686-unknown-linux-gnu` and
`apt-get install -y gcc-multilib` steps and the `CARGO_TARGET_I686_UNKNOWN_LINUX_GNU_LINKER: clang` variable for the
i686 Rust test of WP4), `fledge.toml` (task `compat-2-0`), `scripts/compat/run-2-0.sh` (creates a temporary `v2.0.0`
worktree, builds its three adapters and the three harnesses, and runs both parts of the job),
`scripts/compat/decode-2-0.mjs`, `scripts/compat/rust/` (`Cargo.toml` and `src/main.rs`; the script writes the
`threemd` path dependency) and `scripts/compat/swift/` (`Package.swift` and one source file).

The job is not part of the verify lane: it builds a second copy of all three libraries and adapters from the
`v2.0.0` tag, which also needs the tag in the checkout. WP12 runs it on the exact tip.

Done when: the job is green and fails if any 2.0 reader returns anything but the expected outcome: through the v2.0.0
adapters, with `3md-interchange-1` requests and no limits, `unsupportedPayloadKind` for the 54 anchors (and the 4
composition envelopes as composition requests) and `expected20` for the 127 limit-free vectors; through the v2.0.0
libraries, `expected20` for all 156 vectors under their limits.

## WP8. CLI (owner: Swift)

Files: `Sources/CLI/main.swift` (binary input for every subcommand; `ErrorOutput` gains the storage branch with
`code`, `message`, `detail` and `line`; the `threemd: <path>: <code>: <description>` stderr line; `convert` with format
inference, the usage exits and the atomic write; `inspect` with the three JSON shapes),
`Tests/ThreeMDTests/CLITests.swift` (wrapped in `#if os(macOS) || os(Linux)` because `Process` is missing on iOS,
tvOS, watchOS and visionOS; it runs the built `threemd` binary, so no new test target and no `Package.swift` change),
`specs/ThreeMDCLI/*`, usage text, the README CLI section (with WP9).

Done when: the CLI tests pass on macOS and Linux; `swift run threemd inspect
conformance/structured/worked-document.3mdb` prints kind 2 and `ok`; the existing CLI behavior on text is
byte-identical.

## WP9. Documentation (owner: docs and release)

Files: `README.md`, `docs/MIGRATION-2.1.md` (new), `docs/RELEASE-2.1.0.md` (new), `docs/FILE-COMPOSITION.md`,
`docs/EDITING-RELEASE.md`, `js/README.md`, `Examples/README.md`, `Examples/LinkedVillage/README.md`,
`conformance/README.md`, `CHANGELOG.md`, `ROADMAP.md`, `AGENTS.md`, and `docs.3md` and `web/docs.3md` regenerated with
`scripts/build-docs-3md.mjs`. `docs.md` lists each change.

Done when: the docs drift checks pass; every statement about binary payloads says which kind; no ratio is quoted
without its language, runtime and baseline.

## WP10. Versions 2.1.0 (owner: docs and release)

Files: `js/package.json`, `rust/Cargo.toml` and `rust/Cargo.lock`, `element/package.json`,
`editor/vscode/package.json`, the rebuilt `web/assets/three-md.js` and `element/dist/three-md.js` if a version string
is embedded, the CHANGELOG release header, and the version lines of `element/README.md` (lines 29 to 33: version,
release guide link) and `editor/vscode/README.md` (lines 25 to 34: version, `threemd-2.1.0.vsix`, release guide
link), which name 2.0.0, `threemd-2.0.0.vsix` and `docs/RELEASE-2.0.0.md` today; their text-only statements stay.
The Swift package version is the release tag.

Done when: `cargo package --list` and `bun pm pack --dry-run` show 2.1.0; the two READMEs name 2.1.0,
`threemd-2.1.0.vsix` and `docs/RELEASE-2.1.0.md`; the element bundle check passes.

## WP11. Performance harnesses and workflow (owner: tooling and CI)

Files (the two input generators already landed in WP1): `scripts/bench/swift/` (package with `threemd-bench`),
`js/scripts/bench-storage.ts`, `rust/examples/bench_storage.rs`, `scripts/bench/gate.mjs`, `scripts/bench/gate.json`,
`fledge.toml` (tasks `bench-inputs`, `bench-storage`, `perf-gate`, lane `perf`), `.github/workflows/perf.yml`.

`scripts/bench/gate.mjs` implements the blocking rules: G6 always blocks; floors and calibrated ceilings block only
with `--blocking true` (ceilings only once the runner has a calibrated table); every other failure is a warning; a
receipt from an unpinned toolchain fails the job.

Done when: the workflow runs on both runners; two calibration runs are committed with the calibrated macOS table in
`gate.json`; the macOS gate passes with `--blocking true` and is a required check for release branches and tags; the
Linux job runs with `--blocking false` (G6 blocking, everything else reported); G6 runs in the unit tests.

## WP12. Verification and release readiness (owner: spec lead)

- Run `fledge lanes run verify`, the Linux workflow, the compatibility job and the perf workflow on the exact tip.
- Run the release-candidate fuzz volumes and commit their counts and seeds to
  `docs/evidence/release-2.1.0/fuzz.json`, with the perf receipts and the interchange receipt.
- Run `fledge trust verify` on the exact tip; move this change through check, review and finalization with truthful
  records; open the release PR.

Done when: every package's done criteria hold on one commit; Trust is green on that commit; the evidence files are
committed. Then the merge with the maintainer bypass and the 2.1.0 release follow, as Leif decided.

## Acceptance criteria and their evidence

| Acceptance criterion | Evidence | Requirements |
|---|---|---|
| Kind 2 in the unchanged version 1 container, SPEC 11.3 | WP0 SPEC diff; `conformance/structured/` | SB-01 to SB-04 |
| Byte-identical writers; decode equals the text decode; validity equals 2.0 validation | WP3 to WP6: goldens, P4, P6, P7 at release volume with 0 disagreements | SB-06 to SB-10, SB-21, SB-22 |
| `.binary` writes kind 2; `encodeTextContainer` writes 2.0 kind-1 bytes; 2.0 files readable byte-unchanged; 2.0 readers fail with `unsupportedPayloadKind(2)` | WP3 to WP7: text-container anchors, the compatibility job | SB-10, SB-16, SB-24, SB-34 |
| Kind 2 at least 4 times faster than bounded text decode and faster than legacy parse; kind 1 within 10% | WP11: G1, G2 and K1 on the calibrated macOS gate | SB-29 to SB-31 |
| CLI reads `.3mdb`, converts and inspects | WP8 | SB-25 to SB-27 |
| Byte-order keys; lowered Dmax bounds decompression; Rust numbers round-trip for all powers of two | vectors `order-*`, `container-decoded-over-2dmax-bad-crc`, `numeric-powers.json` | SB-05, SB-02, SB-11, SB-32 |
| Nine-pair interchange covers kind 2 and kind 1; Linux and macOS pass; Trust 1.2.2 and strict SpecSync on the exact tip; 2.1.0 released | WP6, WP12 | SB-23, SB-36 |
| Compositions keep the readable profile; kind 3 reserved | SPEC 11.5 and 12; vectors `container-kind-3*`; catalog case `invalid-binary-kind-3`; files case with a kind-3 child | SB-17 |

## Risks

| Risk | Mitigation |
|---|---|
| Rust G1 on synthetic-2000 has about 8% margin against the 4-times floor | Port the final prototype's techniques; measure in WP4 before WP11; the fallback below applies if calibration shows under 10% margin |
| A port drifts from the 2.0 validity set | Phase Q reuses the real parser; P6 at 10^6 per port is a release gate; P7 compares writers across ports |
| Error precedence differs between ports | Normative step order; precedence vectors; P4 replay across all three ports |
| Unicode data differs between runtimes | Byte output is table-free; the cross-port guarantee covers Unicode 13.0 code points on the pinned CI toolchains, enforced by `scripts/structured/unicode-13.0-assigned.json` in the generator and the P4 and P7 filters; skew vectors stay per port |
| 2.0 consumers receive kind 2 | `encodeTextContainer`; clean `unsupportedPayloadKind(2)`; the migration guide; the compatibility job |
| The element bundle grows | WP2 bundle assertions; no top-level side effects |
| Tests that assumed kind-1 bytes break in a package that does not own them | Directory ownership, the sequencing notes and the integration point; test-plan section 10 (`docs/design/threemd-2.1/test-plan.md`) lists every assertion |
| Perf gate flakes on shared runners | Same-run ratios; 3 runs and a rerun rule; calibration before ceilings block; Linux report-only at first |

## Open questions and their resolution

The specification plan left two open questions and several choices. The implementing agent (Claude) resolved them
after telling Leif it would make the smaller calls itself (context.md records the exact exchange); each is open to
Leif's veto:

1. **Rust G1 margin.** The 0.25 floor is an acceptance criterion and is never loosened. The fallback (apply any
   measured Rust technique the port has not yet used, then re-measure) runs only if the two macOS calibration runs
   show under 10% margin. The specification plan left one residual case to Leif: the floor passes but the margin
   stays under 10% after the fallback. That case is not covered by the delegated decisions; if it happens, the lead
   records the measured margin in the release evidence and raises it then.
2. **Runtime minimums.** Resolved as the restatement: SPEC 11.3.15 guarantees cross-port agreement for strings of
   Unicode 13.0 code points on the pinned CI toolchains. No `platforms` minimum is added to `Package.swift`, no
   `engines` field to `js/package.json`, and neither file joins the affected paths.
3. **2.0.1.** Not planned: the fast CRC, the Rust `canonical_number` fix and the Swift frozen whitespace set ship in
   2.1.0.
4. **Interchange limits.** The request `limits` object applies only to decoding the input; producers, adoption, edits
   and re-imports use standard limits (running producers under boundary limits would fail 4 of the 7 limit-bearing
   `ok` vectors for reasons unrelated to the reader).
5. **Plane count before lines.** S8 (`tooManyPlanes`) precedes L5 (`tooManyLines`) for kind 2, so the file-resolver
   test with `maximumLines: 1, maximumPlanes: 1` keeps a kind-1 branch expecting `tooManyLines` and adds a kind-2
   branch.
6. **LZFSE bound.** The kind-2 bound `min(Emax − 40, 2 × Dmax)` applies to LZFSE input too, by intent: the
   uncompressed container must fit `Emax`.
7. **Integration.** WP3 to WP5 land together with WP6 in one integration merge.
8. **CLI tests.** They stay in `Tests/ThreeMDTests`; no test target is added, so `Package.swift` is not touched.
