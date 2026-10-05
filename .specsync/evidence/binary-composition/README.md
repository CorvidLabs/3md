# Binary and composition implementation evidence

The implemented Swift tree is commit `0e9f81ab6c8c104f3f2856f8b9760fd520a05f5b`. Frozen source and fixture hashes accompany actual command logs. Subsequent lifecycle metadata does not change these product sources.

## Actual verification

- 47 focused XCTest regressions pass, including four checks of the six generated example files and their manifest.
- Complete Swift suite: 176 XCTest tests, zero failures. The trailing Swift Testing zero-test summary belongs to the separate runner and is not the XCTest count.
- Existing JavaScript conformance: 79 tests pass. Rust conformance and three documentation tests pass; strict format/clippy pass.
- Generated element bundle drift and four editor grammar fixtures pass.
- The full seven-step lane passes in 21.140 seconds.
- Forced strict SpecSync 6 validation passes for all three specs with no warnings, 22/22 files and 3379/3379 source lines covered.
- Augur staged risk verdict is proceed at 33.67; Trust's committed-range risk verdict is proceed at 32.
- Direct Trust 1.2.2 passes its existing progressive provenance gate. Attest policy verification fails because the available actual agent record is unsigned and outside the unchanged permitted reviewer identities. No signer key or policy was changed.

The initial compile exposed deployment availability of Task APIs. Guarded cancellation now preserves the original deployment baseline and cooperates on supported concurrency runtimes. The initial full lane passed Swift but lacked Bun on a coordinator-supplied PATH; the corrected Trust lane includes the existing Bun installation. Both earlier logs are preserved.

## Scoped agent peer review

`agent:sculpture_editor` gave a scoped PASS for storage on the exact implementation commit. Review covered size-before-allocation, CRC/header coverage, exact compressed-stream termination, fidelity, availability and real fixture contracts. This agent authored composition, so the storage review is peer review across ownership boundaries.

`agent:sculpture_examples` gave a scoped PASS for composition and format concordance on that same commit. Its earlier finding about outer-profile byte-limit errors was repaired and regression tested. Review covered all-entry validation, cycle/missing-reference detection, shared occurrence bounds, strict JSON keys, source fidelity and resource isolation. This agent authored storage, so the composition review is peer review across ownership boundaries.

Codex root ran the actual verification lane and recorded an unsigned Attest claim under `agent:codex-root`, with tests passed and the real risk receipt. None of these records claims an independent human implementation review or the permitted pinned signature. Cancellation regressions establish pre-canceled operations; they do not establish interruption inside the unchanged synchronous Parser.

## SDD status and remaining gates

The new workflow-v2 scope has Leif's direct approval recorded by actual delegated agent actors. Its approved delta was materialized and scoped structural verification passed. Three historical accepted records were audited and reopened with their original approvals and prior evidence preserved. CHG-0001 and CHG-0003 passed fresh checks and received truthful delegated acceptance refreshes.

CHG-0002 remains verifying: its original committed state contains verification.json but no verification-attempts.json. After the audited reopen, SpecSync 6 refuses a new attempt with `verification attempt history is missing`. The supported `migrate 5.0 --dry-run` reports all records unchanged and supplies no recovery. No history, state or approval was manually fabricated to bypass this guard.

The pull request is a draft while closing SDD and permitted signed provenance remain open. A green implementation lane or progressive Trust gate does not imply those gates are complete. No merge, release or deployment is claimed.
