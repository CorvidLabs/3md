---
change: add-stable-document-identities-transactional-patches-and-diagnostics-for-release-preparation
artifact: testing
---

# Testing

Test identity retention across text and binary; coordinate changes retain IDs; legacy no-ID documents remain valid; duplicate/invalid IDs and missing targets report paths. Test exact stale revision rejection, all-or-nothing multi-operation failure, operation limits, cancellation and Codable round trips. Preserve old text conformance. Execute pinned Trust 1.2.2 with Fledge 1.7.2 and SpecSync 6.0.0, including Swift/TypeScript/Rust existing checks and generated bundle drift. Tests and signer policy evidence are distinct.

## Execution receipt

Root verified 0018a3c96d849ffb5966a9dd270b43b7d63541a6 with Trust1.2.2, Fledge1.7.2 and SpecSync6.0.0. The seven-step lane passed 222 Swift XCTest cases, 79 JavaScript tests, Rust conformance and three doc tests, formatting/build, element bundle drift and editor grammar. Forced strict contracts cover 28/28 files and 4491/4491 lines, 200/200 ThreeMD exports, three specs and zero warnings. Root's local raw log is /private/tmp/threemd-editing-final-trust.log; the targeted lifecycle check additionally retains command output in its verification record.

The initial implementation passed 219 Swift tests. Scoped review found expensive graph revalidation preceded the diagnostic source-work preflight. The correction charges bounded source work first and adds three regressions for budget ordering, graph count enforcement and cancellation. Scoped review then passed. Existing legacy link extraction is outside bounded diagnostics; Codable hosts must bound incoming transport bytes before Foundation decoding.

Trust reports progressive provenance passed with policy unsatisfied. No trusted-key signature or human GitHub review is claimed. Historical archives, text conformance fixtures, JavaScript/Rust source and generated element bundle remain unchanged.
