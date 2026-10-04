---
change: implement-generic-binary-storage-and-document-composition-with-specsync-6-and-trust-1-2-2
artifact: testing
---

# Testing

Storagetests: existingtextvectors unchanged; Unicode/customaxes/negativefractional positions/preambles/links/metadata/attributes round-trip; independent fixedheader/CRC vectors; optionalLZFSE and unsupportedplatform/version/algorithm; malformedreservedflags, truncation/trailing/concatenation/checksum/expansion/limitboundaries; invalidconstructedDocuments; cooperativecancel withoutpartialresult.

Compositiontests: shared/nesteddefinitions, deterministiclibrary/referenceorder, mixedaxes/rootlookup andbinarywrapping. Reject duplicate/unknownJSONfields, duplicate/missingIDs, unused-nodecycles, depth/bytes/reference/occurrencebudgets, escapedrecordlimits and cancellation. Imported originals removed proves no hiddenfilesystemresolver. Noflatteningclaim.

Rootexecutes existingFledgeverify (Swift,TypeScript,Rust,bundle/editor checks), strictSpecSync6coverage100, workflow-v2check/audit and pinnedTrustverify. Sourcebuilds/producttests have not run for thisscope yet. Tooldiagnostics are notproducttests. ExistingAttestsigner/reviewer policy stays intact; unavailableauthority is reported rather than bypassed.
