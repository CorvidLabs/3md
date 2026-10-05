---
change: bring-bounded-binary-composition-and-transactional-editing-to-typescript-and-rust-with-shared-conformance
artifact: testing
---

# Testing

Both ports consume shared portable fixtures and verify fixed header/CRC vectors, UTF-8 and canonical metadata, exact streams/limits, hostile declarations, duplicate escaped JSON keys, invalid unused graph nodes, occurrence/depth budgets, stable identity preservation, stale UTF-8 revisions, final-only atomic swaps and rollback, cancellation and diagnostic preflight/truncation. Root adds matching Swift tests for shared vectors. Existing Swift/JS/Rust text conformance, generated element bundle drift and editor grammar must remain green. Source feature support does not claim LZFSE where no backend exists.

## Requirement evidence

| Requirement | Evidence | Result |
| --- | --- | --- |
| REQ-ThreeMD-030 | TypeScript storage/composition tests, Rust extension tests, Swift ExtensionConformanceTests, shared exact document/profile/container fixtures | Pass: bounded portable storage, explicit unsupported compression, strict JSON and graph validation |
| REQ-ThreeMD-031 | TypeScript and Rust editing suites, shared identity/transaction/diagnostic vectors, Swift reader tests | Pass: exact revisions, immutable snapshots, atomic final validation, limits, cancellation and structured diagnostics |
| REQ-ThreeMD-032 | Complete pinned Trust lane, unchanged legacy conformance, 45 shared numeric vectors, 100,000-value probes, scoped agent review and forced strict specs | Pass with the existing unsigned provenance limitation; no release or dependency migration |

## Verified source and commands

On 2026-10-05 root verified source commit `1770d075b2a3ec0491d6a1d4776b4ba908cf1480`, based on PR61 tip `2dc2bd4cfb387bd3365b65b259c912b79bb0f962`:

```text
PATH=/opt/homebrew/bin:/Users/leif/.cargo/bin:$PATH /private/tmp/3md-trust-v1.2.2/bin/fledge-trust verify --range 2dc2bd4cfb387bd3365b65b259c912b79bb0f962..HEAD
/Users/leif/.cargo/bin/specsync check --strict --force
```

The complete seven-step lane passed in 6.079 seconds: 232 Swift tests; 133 TypeScript tests with 656 expectations and type checking; Rust's 13 extension tests, eight editing tests, legacy conformance test and three doctests, with formatting and strict Clippy; the deterministic element bundle check; and existing editor grammar tests. Trust's Augur verdict was review at risk 36, followed by the actual delegated scoped source review. Trust passed under unchanged progressive provenance and explicitly reported degradation without a permitted signature. This is not authenticated human approval.

Forced strict SpecSync passed three specs with zero warnings and documented 267/267 ThreeMD exports. The initial Trust run retained the historical `Sources`-only coverage counter. Root subsequently expanded source coverage to `Sources`, `js/src` and `rust/src`, then reran forced strict validation: 38/38 files and 10763/10763 lines. This includes both portable implementation inventories. Two existing draft CLI/element specs still skip section/export validation.

The complete raw receipt is retained locally at `/private/tmp/threemd-portable-verified-head-trust.log`. Both deterministic actual-writer probes tested 100,000 finite IEEE754 values against Swift and found zero mismatches. The checked-in 45 numeric vectors include the reproduced integral/scientific threshold and decimal-tie failures. These sampled checks are not exhaustive floating-point proof.

The scoped review agent reproduced and verified repairs for canonical Unicode key equivalence/order, NaN diagnostic classification, forged structural TypeScript policies and revision methods, Rust decimal spelling, and quadratic whitespace trimming. TypeScript decoding medians across nine samples were 0.076 ms at 4000 spaces, 0.142 ms at 16000 and 6.510 ms at 1000000. Separate semantic tests cover interior whitespace and text/binary round trips; the local timing is not a runtime latency guarantee.

The derived `web/assets/three-md.js` was rebuilt using the existing exact bundle command and passed the unmodified drift gate. Element source and element/dist remain unchanged. No hosted binary/composition editing UI is claimed.
