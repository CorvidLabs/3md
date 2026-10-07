---
spec: ThreeMD.spec.md
---

## Context

ThreeMD is Markdown extended along one free Z axis. Documents carry an axis
label and ordered Markdown planes without assigning application semantics to
their content. The original text grammar remains frozen and shared between
Swift, TypeScript and Rust through the existing conformance fixtures.

The current interchange follow-up adds a Swift development coordinator and
language adapters that exercise every writer/reader pair. It repairs existing
Unicode whitespace/source-key interpretation and lossless scalar quoting without
new grammar or parser signatures. Canonical bytes are exact across languages;
legacy text must preserve its representable semantics. Signed zero normalizes
to zero. Optional Apple compression is distinct from portable storage.

The Swift target also contains the existing HTML and Markdown renderers. This
change adds bounded general Document storage and named-document composition.
They do not introduce voxel grids, assets, placement transforms, file resolvers,
network access or automatic flattening. The web component and command-line
tool remain separate consumers; this feature does not add binary/composition
commands or claim implementation in the language ports or viewer. ThreeMD 2.1
later adds binary input, `convert` and `inspect` to the command-line tool
(ThreeMDCLI) and the structured payload to all three language ports; the web
component and hosted viewer stay text-only.

## Design Decisions

- Immutable Sendable value types keep storage/composition safe across task
  boundaries without shared mutable state.
- General binary storage wraps canonical UTF-8 text in an independently
  versioned envelope. Its magic is distinct from Sculpt/Rook's existing
  application-specific voxel container. Portable uncompressed payloads are
  mandatory; conditional system LZFSE is optional.
- CRC-32 checks corruption, not authenticity. Explicit lengths, flags and
  resource limits prevent ambiguous or unbounded decoding.
- A new canonical storage writer quotes all scalar values and checks semantic
  round trips. Narrow legacy compatibility repairs preserve their APIs and syntax.
- Composition stores each named Document once, preserving each axis and opaque
  reference attributes. IDs resolve solely within the supplied library.
- Validation covers unused definitions as well as the root, preventing hidden
  missing targets, cycles and excessive traversal work.
- The readable profile uses one fenced JSON manifest inside existing 3md syntax.
  A bounded scanner rejects duplicate keys and excessive records before JSON
  object decoding. The profile can itself pass through generic binary storage.
- APIs remain synchronous and pure, with cooperative task cancellation. Callers
  choose their executor and filesystem boundary.
- ThreeMD 2.1 adds payload kind 2, the structured document payload of SPEC.md
  11.3, behind the unchanged container. Flat length-prefixed records in document
  order won over a string pool and an indexed archive: structure is about 1% of
  the bytes, and the measured cost is in strings, so the flat layout was the
  fastest prototype and the simplest to make canonical.
- Coordinates use three tagged forms (zigzag integer, binary32, binary64) that
  keep the exact bits with no decimal conversion; −0 has no encoding.
- Kind-2 keys use raw UTF-8 byte order so written bytes never depend on Unicode
  normalization data, while canonically equivalent keys are still rejected, so a
  stored map is always representable as text.
- A kind-2 file decodes exactly when its document passes the 2.1 `validate`, and
  decodes to the bounded text decode of its canonical text. Readers compute the
  canonical text length and line count from the payload with exact arithmetic
  instead of building text; only planes whose keys contain quotes run a
  directive parse through the 2.0 parser (Phase Q).
- No lazy or partial-access API: a full decode of a 4 MB file takes 6 to 10 ms,
  and partial validity was measured to cost more than it saves.
- `.binary` writes kind 2 so the faster format is the default; consumers on
  ThreeMD 2.0 receive `encodeTextContainer` output, the unchanged 2.0 bytes.
- Every port uses the frozen whitespace set W instead of platform character
  tables, and Rust spells canonical numbers with the shortest round-trip digits,
  so the three ports accept the same documents.

## Source Responsibilities

The existing Axis, Plane, Document, Parser, Serializer, link and renderer files
retain the text contract. DocumentStorage.swift defines storage policy/errors;
DocumentStorageCodec.swift owns the envelope; DocumentStorageValidation.swift
owns bounded text validation and canonical writing; DocumentStorageCompression.swift
owns the optional system compression boundary. In ThreeMD 2.1,
DocumentStorage.swift also defines DocumentPayloadKind and DocumentContainerInfo,
DocumentStorageCodec.swift adds supportedPayloadKinds, containerInfo,
encodeTextContainer and kind dispatch with the D10 bound, and the new
DocumentStorageStructured.swift owns the kind-2 reader, writer, segment scan and
canonical text metrics. TypeScript adds the internal js/src/structured.ts, the
slicing CRC in js/src/checksum.ts and the side-effect-free js/src/number.ts that
now holds canonicalNumber. Rust adds the private rust/src/structured.rs and
rust/src/checksum.rs modules.

DocumentComposition.swift owns the graph/value model and graph validation.
DocumentCompositionLimits.swift owns policies and typed failures.
DocumentCompositionCodec.swift owns the profile boundary.
DocumentCompositionJSON.swift owns bounded strict manifest scanning/writing.
The original foundation implementation is Swift. Portable storage/composition
and editing now also exist in TypeScript and Rust. Sources/ThreeMDInterop owns
the development-only coordinator/protocol/Swift adapter; js/scripts and the Rust
example own the corresponding adapters. Process/file I/O is in development
tools only, outside the ThreeMD library.

## Governance

The workflow-v2 change
`implement-generic-binary-storage-and-document-composition-with-specsync-6-and-trust-1-2-2`
records the actual delegated definition approval before source implementation.
The actor is agent:sculpture_exports, acting under Leif's direct scope approval.
This is not a claim of human implementation review. Root coordinates actual
verification, required lifecycle commits and authorized PR publication.

The ThreeMD 2.1 work is carried by the change
`add-a-structured-binary-document-payload-kind-2-to-threemd-2-1-in-swift-typescript-and-rust-with-fast-checksums-cli`,
which affects the ThreeMD, ThreeMDCLI and ThreeMDElement specs. Its records name
the executing agent and claim no human review that did not happen.

SpecSync is pinned to 6.0.0, Fledge to 1.7.2, and Trust 1.2.2 to immutable commit
bccd89c111d47778c97c5064fb62ab51695e04ea. Existing risk and trusted-signature
policies are preserved. Unavailable signer authority must remain an honest
limitation rather than an invented identity or weakened gate.
