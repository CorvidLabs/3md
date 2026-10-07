---
spec: ThreeMD.spec.md
---

## Tasks

Existing text parsing/serialization, cross-plane links, renderers, stable
anchors and diagnostics remain implemented. Shared conformance fixtures and
TypeScript/Rust ports are existing repository features, not future work.

### Current approved slice

- [x] Adopt SpecSync 6 workflow-v2 with the existing baseline history preserved.
- [x] Write adaptive definition artifacts and record Leif's direct scope
      authorization under the actual agent identity.
- [x] Commit the definition checkpoint through root after staged risk analysis.
- [x] Pin SpecSync 6.0.0, Fledge 1.7.2 and immutable Trust 1.2.2.
- [x] Run isolated Trust 1.2.2 adoption and configuration doctor without changing
      risk policies, trusted keys or reviewer identities.
- [x] Author bounded general Document binary/text storage and semantic tests;
      implementation agents reported formatted, frozen sources.
- [x] Author self-contained named-document graph/profile and semantic tests;
      implementation agents reported formatted, frozen sources.
- [x] Validate exact source inventory and public exports under the active spec;
      strict SpecSync 6 check passed with no errors or warnings.
- [ ] Complete the retained cross-language native verification lane.
- [ ] Record actual exact-revision lifecycle verification and closing review.
- [ ] Publish the authorized feature PR with truthful receipts and limitations.

### ThreeMD 2.1 structured payload (kind 2)

- [x] Apply the SPEC.md 1.2 text: header, sections 11, 11.1 and 11.2, the new
      sections 11.3 to 11.5, and the section 12 and 13 edits.
- [x] Document the 2.1 public API, the `.binary` behavior change, the error
      mapping, the Rust number fix and the frozen whitespace set W in this spec.
- [ ] Add the `files:` entries and Public API rows of the new source in the
      commits that create it: `js/src/number.ts`, `js/src/checksum.ts` and
      `rust/src/checksum.rs` with the prerequisite fixes, and the structured
      reader files with their twenty Public API rows in the integration merge of
      the three ports.
- [ ] Land the shared fixtures: `conformance/structured/`, the
      `*.structured.3mdb` files, `numeric-powers.json` and
      `scripts/structured/` (generator and Unicode 13.0 set).
- [ ] Land the prerequisite fixes: the slicing CRC in all three ports, the Rust
      `canonical_number` fix, the Swift frozen whitespace set W and the
      side-effect-free TypeScript storage modules.
- [ ] Implement payload kind 2, `containerInfo`, `supportedPayloadKinds`,
      `DocumentPayloadKind`, `DocumentContainerInfo` and `encodeTextContainer` in
      TypeScript, Rust and Swift, with the tests of
      `docs/design/threemd-2.1/test-plan.md`.
- [ ] Move the interchange gate to protocol `3md-interchange-2` with the
      catalog, vector and files-case changes, in one integration merge with the
      three ports.
- [ ] Add the ThreeMD 2.0.0 compatibility job and the performance gate.
- [ ] Run the verify lane, the Linux, compatibility and perf workflows and the
      release-candidate fuzz volumes on the exact tip; record the evidence.

### Later, outside this slice

- External document transclusion with an explicit resolver policy.
- Payload kind 3 (structured composition), a key-table layout, an indexed
  archive for partial loading and a portable LZFSE backend (SPEC.md 11.5).
- Storage/composition implementations for TypeScript, Rust and the hosted viewer.
- Application-specific flattening, voxel semantics, rendering transforms or
  library selection UI.
- Package release, tag, merge or deployment; PR authorization alone does not
  authorize these actions.
