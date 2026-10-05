# Lesson bundle — implement-generic-binary-storage-and-document-composition-with-specsync-6-and-trust-1-2-2

Material for folding this change's lessons into the affected specs' `context.md`.
Synthesise from what actually happened below; do not restate the change description.

## What this change was

- **Title**: Implement generic binary storage and document composition with SpecSync 6 and Trust 1.2.2
- **Kind**: Feature
- **Specs**: ThreeMD
- **Paths**: Sources/ThreeMD/, Tests/ThreeMDTests/, Examples/, SPEC.md, README.md, AGENTS.md, .specsync/, specs/, .github/workflows/trust.yml, .trust.toml
- **Acceptance**: General ThreeMD documents round-trip through bounded portable uncompressed binary and optional Apple LZFSE envelopes; named document composition stores shared definitions once and validates references without I/O; malformed, oversized, cyclic, cancelled or corrupt input fails without partial success; existing text conformance and Rook legacy format discrimination remain intact; strict SpecSync 6 workflow-v2 SDD and the immutable Trust 1.2.2 gate pass the existing native cross-language lane without weakening risk or provenance policies.

## Evidence

- Verification commit: `7405db4bf4a21b94e257e957a22067979194ed15`
- Base commit: `8712c686b91a54a972b1ffcb7512055513990d73`
- Verified by: `specsync check --spec ThreeMD`

## From the change's context.md

# Context

<!-- What led here: the problem, and how it was noticed. -->

<!-- What a session picking this up mid-flight needs to know: constraints,
     prior attempts, anything already ruled out. -->

Leif directly instructed: "make sure 3md is using spec-sync 6 and full sdd and I approve all. and also latest trust.. and make sure all of it is working". This authorizes this local definition scope and its approval, not a claim of human implementation-diff review, independent review, authenticated signature or completed verification.

Work is isolated at /private/tmp/3md-binary-composition-20261004 on leif/binary-composition-sdd from origin/main 8712c686b91a54a972b1ffcb7512055513990d73. The sibling checkout and Rook pin remain unchanged. SpecSync 6.0.0 workflow-v2 adoption was run, preserving historical workflow-v1 evidence. A scratch unapproved workflow-v1 draft created before adoption was removed before adopting; it had no approval or verification evidence.

Scope: general Document binary storage, self-contained named in-memory Document references, canonical contracts/docs and Trust 1.2.2 orchestration. No voxel expansion, language-port implementation, external resource resolver, UI or renderer.

## From the change's design.md

# Design

## Binary v1

New DocumentStorage.swift, DocumentStorageCodec.swift, DocumentStorageValidation.swift and DocumentStorageCompression.swift. Public DocumentCompression(UInt8 none0/lzfse1), DocumentStorageFormat(text/binary), DocumentDecodeLimits, DocumentStorageError; codec encode/decode/isBinary/validate. APIs are synchronous throwing and Sendable, permitting caller-chosen executors.

40-byte little-endian header: magic "3mdbin\\r\\n" bytes0..<8, UInt16 version1@8, UInt8 UTF8Document payloadkind1@10, compression@11, UInt32 flags0@12/reserved0@16, UInt64 encodedbytes@20/decodedbytes@28, UInt32 CRC@36. CRC-32/ISO-HDLC covers header0..<36 then encoded payload; reflected polynomial EDB88320, init/finalxorFFFFFFFF; check123456789=CBF43926. It detects corruption, not authorship. Marker is disjoint from Rook's voxel 3MDB header.

New storage canonical source writer quotes scalars to preserve valid single-quote literals, leaving Serializer untouched. Programmatically created Documents are validated. Apple LZFSE imports are conditional; unsupported platforms report unavailable backend. Exact one stream, EOF, decoded count and input exhaustion are mandatory. Cancellation propagates.

## Composition v1

New DocumentComposition.swift, DocumentCompositionLimits.swift, DocumentCompositionCodec.swift and DocumentCompositionJSON.swift. Public immutable DocumentReference(targetID,attributes), DocumentEntry(id,document,references), DocumentComposition(rootID,entries,limits,documentLimits), rootEntry/entry(id:), limits and errors. Codec document(for:), encode, decode(Data/Document) and isComposition(Document).

Outer Document: version0.1,axislayer,metadata profile=3md-composition-1, onez0plane labelledComposition; body fencedJSON manifest schema/rootID/entries. Entrykeys:id/source/references; referencekeys:targetID/attributes. Duplicate/unknown keys fail. IDs1-64 ASCII [A-Za-z0-9][A-Za-z0-9_-]*; library sorts byID,referenceorder preserved. Definitions encode once with shared storage text writer. Explicit20MiB outer record override handles escaped JSON while embedded documents keep supplied policy.

No automatic imports, executable content, axis coercion, geometry, voxel palette, rotation, sparse-world allocation or Markdown flattening. In-memory lookup and validated graph inspection only.

## From the change's testing.md

# Testing

Storagetests: existingtextvectors unchanged; Unicode/customaxes/negativefractional positions/preambles/links/metadata/attributes round-trip; independent fixedheader/CRC vectors; optionalLZFSE and unsupportedplatform/version/algorithm; malformedreservedflags, truncation/trailing/concatenation/checksum/expansion/limitboundaries; invalidconstructedDocuments; cooperativecancel withoutpartialresult.

Compositiontests: shared/nesteddefinitions, deterministiclibrary/referenceorder, mixedaxes/rootlookup andbinarywrapping. Reject duplicate/unknownJSONfields, duplicate/missingIDs, unused-nodecycles, depth/bytes/reference/occurrencebudgets, escapedrecordlimits and cancellation. Imported originals removed proves no hiddenfilesystemresolver. Noflatteningclaim.

Rootexecutes existingFledgeverify (Swift,TypeScript,Rust,bundle/editor checks), strictSpecSync6coverage100, workflow-v2check/audit and pinnedTrustverify. Sourcebuilds/producttests have not run for thisscope yet. Tooldiagnostics are notproducttests. ExistingAttestsigner/reviewer policy stays intact; unavailableauthority is reported rather than bypassed.

## Requirement evidence

| Requirement | Actual evidence and remaining gate |
|-------------|------------------------------------|
| REQ-ThreeMD-021 | DocumentStorageTests and DocumentStorageCompressionTests inspect Unicode/custom-axis text, portable binary and conditional LZFSE. Root's focused new suite passed 43 XCTest methods; actual Examples/Extensions canopy/profile binaries decoded equal. Existing cross-language full lane remains pending. |
| REQ-ThreeMD-022 | DocumentStorageBoundsTests plus fixed-header/CRC/corrupt/truncated/trailing/concatenated/cancellation tests are in the passing focused suite. Root retains the actual test output; no partial-output claim is inferred from structural checks. |
| REQ-ThreeMD-023 | DocumentCompositionTests checks shared/nested references, mixed axes, removed imported files, unused-node failures and graph budgets in the focused passing suite. Definitions stay self-contained. |
| REQ-ThreeMD-024 | DocumentCompositionCodecTests checks strict envelopes, duplicate/unknown JSON, deterministic profiles and binary wrapping. Generated shared-grove fixtures preserve the complete reusable library and decode equal. |
| REQ-ThreeMD-025 | Actual definition approval preceded source implementation; root committed its checkpoint. Strict SpecSync 6 structural check passed all three specs without errors/warnings, and direct isolated Trust 1.2.2 doctor is healthy. Full native/Trust verification, historical delivery audit, truthful scoped review and finalization remain pending. Existing signer policy is unchanged. |

The earlier paragraph records the initial definition-time plan. The focused
result above is later actual evidence, not a claim that the full repository
lane or closing lifecycle gates have already passed. Peer agents are not human
or Claude signer provenance; a SpecSync claim alone is not authenticated identity.

## Actual merge-request follow-up

The later source review found quadratic decimal rejection through the new storage entry point. ParserNumericTests and DocumentStorageDecimalTests now cover preserved finite decimal grammar on all three coordinates, malformed tokens, readable and checksummed-binary rejection within a coarse resource bound, and deterministic cancellation after preflight. All four focused tests pass. The repaired full native lane passes 180 Swift XCTest tests, 79 JavaScript tests and the existing Rust, bundle and editor checks; direct Trust 1.2.2 passes the unchanged progressive provenance gate. Signed Attest remains unsatisfied and no signer authority is invented. Root retains actual logs in the evidence directory and records the later scoped check/review/finalization separately.

## Where these lessons go

- `specs/ThreeMD/context.md`
