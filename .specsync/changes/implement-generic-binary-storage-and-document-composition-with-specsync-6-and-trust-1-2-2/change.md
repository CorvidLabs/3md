---
id: implement-generic-binary-storage-and-document-composition-with-specsync-6-and-trust-1-2-2
state: implementing
type: feature
base_commit: 8712c686b91a54a972b1ffcb7512055513990d73
---

# Implement generic binary storage and document composition with SpecSync 6 and Trust 1.2.2

## Intent

Implement generic binary storage and document composition with SpecSync 6 and Trust 1.2.2

## Affected Canonical Specs

- `ThreeMD`

## Acceptance Criteria

- General ThreeMD documents round-trip through bounded portable uncompressed binary and optional Apple LZFSE envelopes; named document composition stores shared definitions once and validates references without I/O; malformed, oversized, cyclic, cancelled or corrupt input fails without partial success; existing text conformance and Rook legacy format discrimination remain intact; strict SpecSync 6 workflow-v2 SDD and the immutable Trust 1.2.2 gate pass the existing native cross-language lane without weakening risk or provenance policies.

## No-spec Rationale

Not applicable
