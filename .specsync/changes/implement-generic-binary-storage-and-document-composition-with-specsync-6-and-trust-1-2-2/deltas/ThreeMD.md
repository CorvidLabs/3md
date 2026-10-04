# General storage, composition and governance delta

## ADDED

### REQUIREMENT REQ-ThreeMD-021
The ThreeMD library SHALL round-trip general Document values through a separately versioned binary envelope with portable uncompressed storage and optional conditional Apple LZFSE while retaining existing text grammar and Parser/Serializer behavior.

Acceptance Criteria
- General Unicode, mixed-axis, metadata and finite-coordinate documents round-trip through uncompressed binary and text storage.
- Apple LZFSE round-trips where available and fails explicitly where unsupported.
- The new binary marker is disjoint from Rook's existing voxel-specific 3MDB marker.

### REQUIREMENT REQ-ThreeMD-022
Storage SHALL validate finite unique positions, serializable values, declared allocation limits, exact lengths, CRC32 integrity, full compression stream consumption and cooperative cancellation without partial output.

Acceptance Criteria
- Fixed header and CRC vectors are independently inspected.
- Corrupt, truncated, trailing, concatenated, oversized, unsupported and cancelled inputs fail predictably.
- Existing text-parser conformance vectors remain unchanged.

### REQUIREMENT REQ-ThreeMD-023
Composition SHALL store a root and unique named Document definitions with explicit in-memory references and validate every node, including unused definitions, for safe IDs, target existence, cycles, bounded depth, unique bytes, references and traversal occurrences.

Acceptance Criteria
- Repeated and nested references serialize one definition per ID and preserve generic attributes and mixed axes.
- Missing targets, duplicate IDs, unused-node cycles, depth/byte/reference/occurrence overflow and cancellation fail without partial results.
- Resolution continues after imported original files are removed and never reads filesystem or network paths.

### REQUIREMENT REQ-ThreeMD-024
The composition codec SHALL use existing 3md syntax and a strict versioned JSON manifest without imposing voxel interpretation or automatic flattening, and its profile Document SHALL also be supported by binary storage.

Acceptance Criteria
- Unknown and duplicate JSON fields and invalid outer-profile structure are rejected.
- Canonical profile round-trips preserve root, definitions and reference order.
- A composition profile survives generic binary wrapping with all referenced definitions intact.

### REQUIREMENT REQ-ThreeMD-025
Meaningful changes SHALL remain governed by SpecSync 6.0.0 workflow-v2 definition and actual later verification/review/finalization evidence, with immutable Trust 1.2.2 retaining the existing verification lane and risk/provenance policies.

Acceptance Criteria
- The recorded definition accurately cites Leif's direct scope approval with a delegated agent actor and no claim of human implementation review.
- Strict SpecSync coverage and the existing cross-language native checks are executed by the root verification lane.
- Managed agent rules are updated only with Trust adopt; historical evidence is not fabricated or rewritten, and unavailable signer authority is reported without weakening Attest policy.
