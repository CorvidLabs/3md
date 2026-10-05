---
change: implement-generic-binary-storage-and-document-composition-with-specsync-6-and-trust-1-2-2
artifact: testing
---

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
