---
spec: ThreeMD.spec.md
---

## Context

ThreeMD is Markdown extended along one free Z axis. Documents carry an axis
label and ordered Markdown planes without assigning application semantics to
their content. The original text grammar remains frozen and shared between
Swift, TypeScript and Rust through the existing conformance fixtures.

The Swift target also contains the existing HTML and Markdown renderers. This
change adds bounded general Document storage and named-document composition.
They do not introduce voxel grids, assets, placement transforms, file resolvers,
network access or automatic flattening. The web component and command-line
tool remain separate consumers; this feature does not add binary/composition
commands or claim implementation in the language ports or viewer.

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
  round trips. Parser and Serializer are left unchanged.
- Composition stores each named Document once, preserving each axis and opaque
  reference attributes. IDs resolve solely within the supplied library.
- Validation covers unused definitions as well as the root, preventing hidden
  missing targets, cycles and excessive traversal work.
- The readable profile uses one fenced JSON manifest inside existing 3md syntax.
  A bounded scanner rejects duplicate keys and excessive records before JSON
  object decoding. The profile can itself pass through generic binary storage.
- APIs remain synchronous and pure, with cooperative task cancellation. Callers
  choose their executor and filesystem boundary.

## Source Responsibilities

The existing Axis, Plane, Document, Parser, Serializer, link and renderer files
retain the text contract. DocumentStorage.swift defines storage policy/errors;
DocumentStorageCodec.swift owns the envelope; DocumentStorageValidation.swift
owns bounded text validation and canonical writing; DocumentStorageCompression.swift
owns the optional system compression boundary.

DocumentComposition.swift owns the graph/value model and graph validation.
DocumentCompositionLimits.swift owns policies and typed failures.
DocumentCompositionCodec.swift owns the profile boundary.
DocumentCompositionJSON.swift owns bounded strict manifest scanning/writing.
All new feature implementation is Swift.

## Governance

The workflow-v2 change
`implement-generic-binary-storage-and-document-composition-with-specsync-6-and-trust-1-2-2`
records the actual delegated definition approval before source implementation.
The actor is agent:sculpture_exports, acting under Leif's direct scope approval.
This is not a claim of human implementation review. Root coordinates actual
verification, required lifecycle commits and authorized PR publication.

SpecSync is pinned to 6.0.0, Fledge to 1.7.2, and Trust 1.2.2 to immutable commit
bccd89c111d47778c97c5064fb62ab51695e04ea. Existing risk and trusted-signature
policies are preserved. Unavailable signer authority must remain an honest
limitation rather than an invented identity or weakened gate.
