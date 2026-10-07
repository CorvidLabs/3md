# Structured document payload (kind 2) for ThreeMD 2.1

## ADDED

### REQUIREMENT REQ-ThreeMD-037

The Swift, TypeScript and Rust libraries SHALL store a Document as payload kind 2, the structured document payload of SPEC.md section 11.3, inside the unchanged version 1 container, and SHALL decode it by the normative check order of SPEC.md 11.1 and 11.3 (D1 to D14, then Phases S, L and Q) to exactly the Document that the bounded text decode of its canonical text yields. A kind-2 file SHALL decode exactly when its Document passes the 2.1 validate under the same limits and the uncompressed container fits maximumEncodedBytes. Every Document SHALL have exactly one uncompressed kind-2 encoding, keys SHALL be stored in strictly increasing raw UTF-8 byte order, no limit field or error code SHALL be added, and decoding SHALL be bounded, cancellable and free of partial results. (Change requirements SB-01 to SB-09 and SB-12 to SB-15.)

Acceptance Criteria:
- Header byte 10 is 2 for kind 2; storage decode accepts text, kind 1 and kind 2 and reports unsupportedPayloadKind for kinds 0 and 3 to 255. D10 bounds a kind-2 declared payload length by min(maximumEncodedBytes − 40, 2 × maximumDecodedBytes) before the CRC and before any decompression allocation, and the kind check and the D10 bound both win over a corrupt CRC.
- Var, Count, Str and the four number forms follow SPEC.md 11.3.3; the payload is one DocumentRecord and its PlaneRecords with no offsets, index, string pool or padding; trailing bytes are lengthMismatch.
- A key not greater than the previous one in raw UTF-8 byte order is invalidContainer, and canonically equivalent keys in one map are invalidDocument. The frozen whitespace set W, R2, R3, R9, R7, R8, the segment rules G1 to G6 and the Phase Q directive round trip decide representability.
- For any uncompressed kind-2 input that decodes, re-encoding with .binary(.none) under the same limits returns the input bytes.
- Phase S, Phase L and Phase Q run in that order and the first failing check is reported; the canonical text metrics equal the 2.0 writer's output; the decoded value has each port's 2.0 shape.
- The differential properties P3, P5 and P6 show zero disagreements with the 2.1 validate and the bounded text decode under standard and lowered limits.
- Kind-2 failures map to the existing DocumentStorageError codes of SPEC.md 11.3.12, including the composition and file-resolver domains; only the Swift descriptions of invalidContainer and unsupportedPayloadKind change.
- Cancellation is checked at every SPEC.md 11.3.13 point with no partial result; the 65,536-plane amplification case is rejected before any Phase Q parse in under 1 second; peak memory stays under 4 times the input for the 64 MiB worst cases; count and cap arithmetic cannot overflow on 32-bit targets.

### REQUIREMENT REQ-ThreeMD-038

Storage encode with .binary(compression:) SHALL write payload kind 2 through the writer steps W1 to W6, with byte-identical uncompressed output in Swift, TypeScript and Rust for every Document that all three accept, and the new encodeTextContainer SHALL write the ThreeMD 2.0 kind-1 bytes with the 2.0 validation and error order. Text and kind-1 decoding, every committed 2.0 .3mdb file, isBinary, the error enums, the limit types and every existing signature SHALL stay unchanged; a ThreeMD 2.0 reader SHALL stop on a kind-2 file with unsupportedPayloadKind(2) before it computes the CRC. Compositions SHALL keep the readable 3md-composition-1 profile, and payload kind 3 SHALL be reserved and refused. (Change requirements SB-10, SB-11, SB-16 and SB-17.)

Acceptance Criteria:
- W1b rejects maximumEncodedBytes below 40 with oversizedInput; W2 normalizes −0 and applies each port's key rules (TypeScript merges equivalent keys after the 2.0 validateRecords pre-check and rejects lone surrogates; Rust rejects equivalent keys); W3 caps the buffer at maximumEncodedBytes − 40; W4 self-checks with the reader routine decode uses.
- LZFSE applies to kind 2 on Swift Apple platforms with the CRC over the compressed bytes and the kind-2 D10 bound; TypeScript and Rust report compressionUnavailable(lzfse).
- encodeTextContainer reproduces every committed kind-1 anchor byte for byte; every committed 2.0 .3mdb keeps its name and bytes; text and kind-1 suites pass unchanged.
- Composition decode and the file resolver accept text, kind-1 and kind-2 envelopes and children, and storage decode, composition decode and the resolver refuse kind 3 with unsupportedPayloadKind(3).

### REQUIREMENT REQ-ThreeMD-039

Swift, TypeScript and Rust SHALL add only DocumentPayloadKind (Rust payload kind constants), DocumentContainerInfo, supportedPayloadKinds, the header-only containerInfo and encodeTextContainer (Rust container_info and encode_text_container), with Sendable Swift types, Send + Sync Rust types and exactly two new TypeScript root exports, and SHALL add no lazy or partial-access API. Kind-2 bytes SHALL never depend on Unicode data, and the three ports SHALL agree on acceptance, error code and decoded value for inputs whose strings hold only Unicode 13.0 assigned code points on the pinned CI toolchains. (Change requirements SB-18 to SB-20.)

Acceptance Criteria:
- containerInfo reads at most 40 bytes, reports the raw header fields without validating them, the payload or the CRC, returns nil, null or None without the magic and throws invalidContainer when the magic is present with fewer than 40 bytes.
- The TypeScript export-surface test finds exactly DocumentPayloadKind and the DocumentContainerInfo type as new root exports; Rust re-exports the new items from lib.rs; the Swift strict-concurrency build accepts the new types as Sendable.
- scripts/structured/unicode-13.0-assigned.json (283,506 code points in 686 ranges) is committed; the fixture generator rejects anchor and vector strings outside it, and the cross-port properties P4 and P7 exclude such inputs; Unicode skew vectors run only in per-port suites.

### REQUIREMENT REQ-ThreeMD-040

The repository SHALL commit the kind-2 conformance fixtures and vectors, SHALL reproduce them byte for byte with every port's writer and with scripts/structured/generate.mjs --check in the verify lane, SHALL run the differential properties P1 to P8, SHALL extend the nine-pair interchange gate to protocol 3md-interchange-2 so that every reader consumes every writer's kind 1 and kind 2, SHALL prove with a ThreeMD 2.0.0 compatibility job that 2.0.0 readers stop cleanly on kind 2, and SHALL migrate every existing assertion that assumed .binary meant kind 1 without deleting a kind-1 check. (Change requirements SB-21 to SB-24 and SB-34.)

Acceptance Criteria:
- conformance/structured/ holds the 45 anchors, the 3 worked examples, manifest.json, sizes.json, vectors.json (156 vectors) and README.md; four conformance/extensions and two Examples/Extensions .structured.3mdb files sit next to their kind-1 files; every SHA-256 matches the golden manifest and every vector gives its expected code under its own limits in every port.
- P1 to P8 run at CI volume on every push and at release volume once on the release tip with zero disagreements, zero cross-port code or byte mismatches and zero re-encode failures; seeds and counts are committed to docs/evidence/release-2.1.0/fuzz.json.
- The interchange catalog has 83 cases (49 valid, 34 invalid) with textContainerFile and a kind-2 binaryFile; invalid-binary-kind expects checksumMismatch and invalid-binary-kind-3 expects unsupportedPayloadKind; the driver replays all 156 vectors under their limits, the five fixed protocol cases and structuredReplay.
- The compat-2-0 job shows the v2.0.0 adapters return unsupportedPayloadKind for the 54 anchors and expected20 for the 127 limit-free vectors, and harnesses built on the v2.0.0 libraries return expected20 for all 156 vectors under their limits.

### REQUIREMENT REQ-ThreeMD-041

Kind-2 decode SHALL take at most 0.25 of the bounded text decode time and less than the legacy parse time, and kind-1 decode at most 1.10 of the bounded text decode time, in Swift, TypeScript on Node 24 and on Bun 1.4.2, and Rust, enforced by a pinned CI performance gate whose size gate G6 always blocks. Kinds 1 and 2 SHALL use a table-driven CRC that consumes at least 8 bytes per step, Rust SHALL spell canonical numbers with the shortest round-trip digits, and Swift SHALL trim with the frozen whitespace set W. (Change requirements SB-29 to SB-33.)

Acceptance Criteria:
- On the Examples corpus aggregate, the largest and median Example, synthetic-2000 and sculpt-4096: G1 at most 0.25, G2 below 1.0, K1 at most 1.10; G6 holds for the Examples total, every Example, synthetic-2000 and sculpt-4096 and also runs in the unit tests.
- .github/workflows/perf.yml runs three runs per language and runtime on macos-15 with blocking floors and, after two committed calibration runs, blocking calibrated ceilings, and on Linux in report-only mode; a receipt from an unpinned toolchain fails the job; the perf lane is not part of verify.
- The CRC matches the check value 0xCBF43926 and a bytewise reference at every alignment; the Swift decoder no longer copies the header and payload into new Data values; every kind-1 anchor keeps its bytes.
- All 4,318 vectors of conformance/extensions/numeric-powers.json match in every port and Rust validate accepts the 92 powers of two it rejected in 2.0; a Swift test pins the 19 W scalars and the six excluded spaces.

### REQUIREMENT REQ-ThreeMD-042

Every documentation statement about binary payloads SHALL name the payload kind, and no speed ratio SHALL be quoted without its language, runtime and baseline. The work SHALL be verified on one exact tip by the verify lane, the Linux workflow and macOS suites, the compatibility job, the perf workflow, pinned Trust 1.2.2 and strict SpecSync, with release evidence committed, before 2.1.0 is released; no lifecycle, contract, risk or provenance gate SHALL be weakened. (Change requirements SB-35 and SB-36.)

Acceptance Criteria:
- docs/MIGRATION-2.1.md and docs/RELEASE-2.1.0.md exist, the CHANGELOG has a 2.1.0 entry, kind-2 speedups are quoted only against the bounded text decode and the 2.1 kind-1 decoder, and the docs drift checks pass with docs.3md and web/docs.3md regenerated.
- fledge trust verify and specsync check --strict --force --require-coverage 100 pass on the tip; evidence lives under docs/evidence/release-2.1.0/.
- js/package.json, rust/Cargo.toml and Cargo.lock, element/package.json and editor/vscode/package.json read 2.1.0, and element/README.md and editor/vscode/README.md name the 2.1.0 release.
