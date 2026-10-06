# File composition

## ADDED

### REQUIREMENT REQ-ThreeMD-035

The library SHALL provide glyph-ledger composition of supplied files and portable self-contained bundling in Swift, TypeScript and Rust under docs/FILE-COMPOSITION.md. Resolution SHALL preserve document semantics, identities, nested references and shared children, and refuse invalid paths, missing files, cycles, resource overflow and cancellation atomically. Core SHALL perform no file or network I/O. Existing grammar, container and composition profile versions SHALL remain.

Acceptance Criteria:
- Resolve repeated/nested text and binary child files once per normalized path.
- Preserve document/plane identities and opaque reference attributes.
- Portable text/binary bundles reopen without source folders.
- Shared fixtures and all nine writer/reader pairs pass.

