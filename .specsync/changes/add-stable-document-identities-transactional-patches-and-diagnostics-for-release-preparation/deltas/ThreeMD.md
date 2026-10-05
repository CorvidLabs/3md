# Stable identities, editing and diagnostics

## ADDED

### REQUIREMENT REQ-ThreeMD-026
The library SHALL expose optional stable plane identities and per-owning-entry reference identities through the preserved namespaced 3md-id attribute without changing frozen text parsing, legacy z links or composition definition IDs.

Acceptance Criteria
- Identity-aware validation reports empty, unsafe or duplicate IDs with an exact plane path.
- Text and supported binary round trips preserve IDs and arbitrary existing metadata.
- Explicit adoption preserves valid existing IDs and assigns missing identities without interpreting ordinary id attributes.
- Identity-aware edits can change a plane coordinate, source order or reference target without changing its ID.

### REQUIREMENT REQ-ThreeMD-027
Typed document and composition patches SHALL be immutable Sendable values applied transactionally with exact canonical-content revision comparison and bounded operation counts.

Acceptance Criteria
- Insert, remove, replace and reorder operations target stable IDs and preserve unrelated content.
- Invalid operations, final duplicate positions or reference graphs, stale expected content and cancellation return no partial document or composition.
- Existing no-ID documents remain parseable and identities can be explicitly assigned before ID-targeted edits.

### REQUIREMENT REQ-ThreeMD-028
Additive diagnostics SHALL expose stable codes, explanatory text and available source line or plane/reference paths without changing existing ParseError cases.

Acceptance Criteria
- Parse failures reuse actual line evidence and never invent a line for value-only diagnostics.
- Identity and patch failures identify the offending plane or operation.
- Diagnostics preserve legacy parser and serializer behavior and do not perform external I/O.

### REQUIREMENT REQ-ThreeMD-029
Release preparation SHALL publish accurate capability, compatibility and migration documentation while preserving current text conformance and historical lifecycle evidence.

Acceptance Criteria
- New editing and binary/composition APIs are declared Swift-first until other implementations support them.
- No library release/tag, protection change or signer claim is invented.
- Existing format/source APIs remain compatible and later indexed storage, materials and timing remain labeled planned.
