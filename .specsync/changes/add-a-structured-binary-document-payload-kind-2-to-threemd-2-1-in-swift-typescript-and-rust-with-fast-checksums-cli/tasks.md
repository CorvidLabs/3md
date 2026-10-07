---
change: add-a-structured-binary-document-payload-kind-2-to-threemd-2-1-in-swift-typescript-and-rust-with-fast-checksums-cli
artifact: tasks
---

# Tasks

Implementation tasks only. Lifecycle steps are tracked by SpecSync itself. Work package numbers refer to `plan.md`;
requirement IDs to `requirements.md`. "Test-plan section N" means `docs/design/threemd-2.1/test-plan.md`.

## WP0. Contract text

- [ ] Apply the SPEC.md 1.2 edits (header; sections 11, 11.1, 11.2; new 11.3 to 11.5; sections 12 and 13) without changing sections 1 to 10 (SB-01).
- [ ] Update `specs/ThreeMD/` (spec, requirements, testing, tasks) for the kind-2 API, the `.binary` behavior change, the error mapping, the Rust number fix and the frozen whitespace set.
- [ ] Update `specs/ThreeMDCLI/` for binary input, `convert`, `inspect` and the storage error output.
- [ ] Update `specs/ThreeMDElement/` for the bundle invariant (no storage code, 50,000-byte budget) and the package version sentence.
- [ ] Commit the specification package's test plan and performance gate as `docs/design/threemd-2.1/test-plan.md` and `perf-gate.md`, with a path map, and point every "test-plan" and "perf-gate" reference at them.
- [ ] Leave the new `files:` entries and Public API rows of `specs/ThreeMD/ThreeMD.spec.md` to the commits that create their source (plan.md, WP0, "Staged contract entries"), so `specsync check --strict --force --require-coverage 100` passes on the WP0 commit.

## WP1. Shared fixtures

- [ ] Add `conformance/structured/` with the 45 anchors, 3 worked examples, `manifest.json`, `sizes.json`, `vectors.json` (156 vectors), `invalid/`, `limits/` and `README.md` (SB-21).
- [ ] Add the four `conformance/extensions/*.structured.3mdb` files and the two `Examples/Extensions/*.structured.3mdb` files.
- [ ] Add `conformance/extensions/numeric-powers.json` (4,318 vectors).
- [ ] Add `scripts/structured/unicode-13.0-assigned.json` (SB-18).
- [ ] Add `scripts/structured/generate.mjs` with `--write` and `--check` modes and the Unicode 13.0 string filter.
- [ ] Add the catalog fixture `conformance/interchange/invalid-binary-kind-3.3mdb` (written by the generator; the manifest case is WP6).
- [ ] Add `scripts/bench/generate-synthetic.mjs` and `scripts/bench/generate-sculpt.mjs` with their pinned SHA-256 assertions, and the anchored `/bench/` entry to `.gitignore`.
- [ ] Confirm every committed fixture's SHA-256 matches the golden manifest and both input generators reproduce their pinned SHA-256.

## WP2. Prerequisite fixes

- [ ] Swift: slicing-by-8 `DocumentStorageChecksum` over `UnsafeRawBufferPointer`; remove the header and payload `Data` copies in decode (SB-31).
- [ ] TypeScript: add `js/src/checksum.ts` (lazy slicing-by-16 tables) and use it in `storage.ts` (SB-31).
- [ ] Rust: add private `rust/src/checksum.rs` (`const` slicing-by-16 tables) and `#![forbid(unsafe_code)]` in `lib.rs` (SB-31); add `rust/src/checksum.rs` to the `files:` of `specs/ThreeMD/ThreeMD.spec.md` in the same commit.
- [ ] Add CRC tests in each port: check value `0xCBF43926`, 10,000 random buffers of length 0 to 300 at every alignment against a bytewise reference, kind-1 anchors unchanged.
- [ ] Rust: fix `canonical_number` and `swift_double`; add the `numeric-powers.json` test; keep the tie and existing numeric tests passing (SB-32).
- [ ] Swift: add internal `ThreeMDWhitespace` and replace `.whitespaces` trimming in `Parser.swift`, `Axis.swift`, `DocumentStorageValidation.swift` and `Serializer.swift`; add the test pinning the 19 W scalars and the 6 excluded spaces (SB-33).
- [ ] TypeScript: move `canonicalNumber` to `js/src/number.ts`; remove top-level side effects from `storage.ts`; add the marker and 50,000-byte assertions to `scripts/check-element-bundle.mjs` (SB-28).
- [ ] TypeScript: add `js/src/number.ts` and `js/src/checksum.ts` to the `files:` of `specs/ThreeMD/ThreeMD.spec.md` in the commit that creates them, and document any export they add.

## WP3. TypeScript port

- [ ] Add internal `js/src/structured.ts`: cursor, Var, Count, Number forms, Str, chunked fatal `TextDecoder` decoding with non-streaming calls, segment rules, byte-order keys, NFC equivalence, R2, R3, R9, Phase L metrics, Phase Q, `readDocument` and the writer (SB-03 to SB-10, SB-14).
- [ ] In `js/src/storage.ts`: add `DocumentPayloadKind`, `DocumentContainerInfo`, `supportedPayloadKinds`, `containerInfo` and `encodeTextContainer`; route `.binary` to kind 2; dispatch by kind with the D10 bound (SB-02, SB-19, SB-20).
- [ ] Export the two new names from `js/src/index.ts` and nothing else.
- [ ] Add `js/test/structured.test.ts`: goldens, vectors under their limits, the unit checklist, the two chunked-UTF-8 call sequences, P1 to P6 at CI volume, cancellation and buffer ownership.
- [ ] Migrate `js/test/` per test-plan section 10.3 (writer assertions to `encodeTextContainer`, kind-2 siblings, the `tooManyPlanes` branch) (SB-34).

## WP4. Rust port

- [ ] Add private `rust/src/structured.rs` with the measured techniques (chunked `str::from_utf8`, SWAR LF scan, Phase L bound shortcut, no per-plane allocation, `HashSet<u64>` for L0, checked arithmetic) (SB-03 to SB-10, SB-14, SB-15).
- [ ] In `rust/src/storage.rs` and `lib.rs`: add the payload kind constants, `DocumentContainerInfo`, `container_info` and `encode_text_container`; route `Binary(c)` to kind 2; dispatch by kind; re-export (SB-19, SB-20).
- [ ] Add `rust/tests/structured.rs`: goldens, vectors, unit checklist, seeded property tests, P4 blob replay, cancellation and `Send + Sync`.
- [ ] Migrate `rust/tests/` per test-plan section 10.4 (SB-34).
- [ ] Measure Rust G1 on synthetic-2000 before WP11 and apply the remaining measured techniques if the margin is under 10%.

## WP5. Swift port

- [ ] Add `Sources/ThreeMD/DocumentStorageStructured.swift`: reader with `loadUnaligned`, `String(decoding:)` plus byte equality (chunked), `memchr` segment scan, byte-order keys, `Set<String>` equivalence, Phase L, Phase Q through `Parser`, and the writer (SB-03 to SB-10, SB-14).
- [ ] In `DocumentStorage.swift` and `DocumentStorageCodec.swift`: add `DocumentPayloadKind`, `DocumentContainerInfo`, `supportedPayloadKinds`, `containerInfo` and `encodeTextContainer`; route `.binary` to kind 2; dispatch by kind with the D10 bound; handle `Data` slices; update doc comments and the two error descriptions (SB-13, SB-19, SB-20).
- [ ] In `DocumentStorageCompression.swift`: LZFSE for kind 2 with the D10 cap (SB-11).
- [ ] Add `Tests/ThreeMDTests/DocumentStorageStructuredTests.swift`: goldens, vectors, unit checklist, property tests, LZFSE round trips on Apple platforms, `Task` cancellation and the 32-task concurrency test.
- [ ] Migrate the Swift tests of test-plan section 10.1 owned by WP5 (SB-34).

## WP6. Interchange protocol 2

- [ ] Update the Swift driver and adapters (`Protocol`, `SwiftAdapter`, `main`, `FileCases`, `FileBundleHost`), `js/scripts/interchange.mjs` and `rust/examples/interchange.rs` for `3md-interchange-2`: request `limits` on the input decode only, `textContainerHex`, the `textContainer` format, vector replay, the five fixed protocol cases, `structuredReplay`, kind-1 and kind-3 files cases and `--text-container` (SB-23).
- [ ] Update `conformance/interchange/manifest.json` to `3md-interchange-catalog-2` with 83 cases, including the `invalid-binary-kind-3` case for the WP1 fixture, and update `README.md` and `PROTOCOL.md`.
- [ ] Update `conformance/extensions/manifest.json` and `Examples/Extensions/manifest.json` with the structured files and `payloadKind`.
- [ ] Update `InterchangeConformanceTests.swift`, the manifest parts of `ExtensionConformanceTests.swift`, `DocumentStorageTests.swift` lines 12 to 40, and the TypeScript and Rust extension tests that read the new fields.
- [ ] Wire `scripts/structured/generate.mjs --check` into the verify lane in `fledge.toml`.
- [ ] In the integration merge, add `Sources/ThreeMD/DocumentStorageStructured.swift`, `js/src/structured.ts` and `rust/src/structured.rs` to the `files:` of `specs/ThreeMD/ThreeMD.spec.md`, and the twenty staged Public API rows (plan.md, WP0).

## WP7. ThreeMD 2.0.0 compatibility job

- [ ] Add `scripts/compat/run-2-0.sh`, `scripts/compat/decode-2-0.mjs`, `scripts/compat/rust/` and `scripts/compat/swift/` (SB-24).
- [ ] Add the `compat-2-0` Fledge task and the `compat-2-0` job in `.github/workflows/linux.yml` (not part of the verify lane).
- [ ] Add the i686 Rust target, `gcc-multilib` and the clang linker variable to `linux.yml` (SB-15).

## WP8. CLI

- [ ] Read input as bytes for every subcommand and route binary input through storage decode (SB-25).
- [ ] Add the storage branch to `ErrorOutput` and the `threemd: <path>: <code>: <description>` stderr line (SB-25).
- [ ] Add `threemd convert` with format inference, usage exits, `--lzfse`, `--force`, atomic writes and stdout output (SB-26).
- [ ] Add `threemd inspect` with the plain output and the three JSON shapes (SB-27).
- [ ] Add `Tests/ThreeMDTests/CLITests.swift` (inside `#if os(macOS) || os(Linux)`) covering test-plan section 8.
- [ ] Update the CLI usage text.

## WP9. Documentation

- [ ] Rewrite the README binary storage section for kind 2 and extend the CLI section (SB-35).
- [ ] Add `docs/MIGRATION-2.1.md` and `docs/RELEASE-2.1.0.md`.
- [ ] Update `docs/FILE-COMPOSITION.md`, `docs/EDITING-RELEASE.md`, `js/README.md`, `Examples/README.md`, `Examples/LinkedVillage/README.md` and `conformance/README.md`.
- [ ] Add the 2.1.0 CHANGELOG entry and update `ROADMAP.md` and the `AGENTS.md` scope paragraph.
- [ ] Regenerate `docs.3md` and `web/docs.3md` with `scripts/build-docs-3md.mjs`.

## WP10. Versions

- [ ] Set 2.1.0 in `js/package.json`, `rust/Cargo.toml`, `rust/Cargo.lock`, `element/package.json` and `editor/vscode/package.json`; rebuild the web and element bundles if a version string is embedded (SB-36).
- [ ] Update `element/README.md` (version, release guide link) and `editor/vscode/README.md` (version, `threemd-2.1.0.vsix`, release guide link) to 2.1.0 and `docs/RELEASE-2.1.0.md`.

## WP11. Performance gate

- [ ] Add the harnesses `scripts/bench/swift/` (`threemd-bench`), `js/scripts/bench-storage.ts` and `rust/examples/bench_storage.rs` with receipts.
- [ ] Add `scripts/bench/gate.mjs` and `scripts/bench/gate.json` with the blocking rules (SB-29, SB-30).
- [ ] Add the `bench-inputs`, `bench-storage` and `perf-gate` tasks and the `perf` lane to `fledge.toml`.
- [ ] Add `.github/workflows/perf.yml` with pinned toolchains and action SHAs.
- [ ] Commit two macOS calibration runs and the calibrated macOS table.
- [ ] Run G6 in the unit tests from `conformance/structured/sizes.json`.

## WP12. Release evidence

- [ ] Run the release-candidate fuzz volumes and commit `docs/evidence/release-2.1.0/fuzz.json` (SB-22).
- [ ] Commit the perf receipts and the interchange receipt under `docs/evidence/release-2.1.0/` (SB-36).
