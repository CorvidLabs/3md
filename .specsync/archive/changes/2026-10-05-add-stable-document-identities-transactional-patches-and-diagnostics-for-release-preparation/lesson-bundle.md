# Lesson bundle — add-stable-document-identities-transactional-patches-and-diagnostics-for-release-preparation

Material for folding this change's lessons into the affected specs' `context.md`.
Synthesise from what actually happened below; do not restate the change description.

## What this change was

- **Title**: Add stable document identities transactional patches and diagnostics for release preparation
- **Kind**: Feature
- **Specs**: ThreeMD
- **Paths**: Sources/ThreeMD/, Tests/ThreeMDTests/, specs/ThreeMD/, SPEC.md, README.md, docs/EDITING-RELEASE.md, .specsync/config.toml
- **Acceptance**: Optional stable plane IDs survive text and binary round trips without changing existing parsing or z links; immutable Sendable typed patches apply atomically with bounded operation counts and exact revision preconditions; duplicate IDs invalid coordinates missing targets stale revisions and cancellation return structured diagnostics with no partial document; release docs publish Swift-first capabilities migration examples and a compatibility matrix; the full pinned Trust lane and strict SpecSync pass with actual evidence; feature PRs remain open for Leif to merge and no release is published.

## Evidence

- Verification commit: `a89d0c401f7f6b749e9f2ec4982b7a0dc063776f`
- Base commit: `0d345bb2ef7ec7cede572c24309761bec047301a`
- Verified by: `specsync check --spec ThreeMD --strict`

## From the change's context.md

# Context

Leif approved the proposed release preparation with: Ok do it and prep. I will merge all your PRs later. Root prepares feature branches and actual verification, with no merge or release. This branch is stacked on PR58 head 0d345bb. Existing text grammar, legacy archives and signed provenance policy remain. Binary/composition are Swift-first additions; TypeScript and Rust retain existing text conformance.

## From the change's design.md

# Design

Use additive Swift 6 Sendable value types and stateless services in ThreeMD. Identity interpretation and editing validation are opt-in above Parser/Serializer. The namespaced 3md-id attribute carries optional plane identities and reference identities within each owning composition entry, leaving any existing id attributes uninterpreted. Explicit adoption assigns missing IDs while preserving valid existing IDs. A patch works on an immutable snapshot and publishes only the fully validated result. Revision matching compares canonical expected content exactly rather than relying on a short noncryptographic hash. Document and composition patches share bounded operation/diagnostic policy and validate complete final graphs, allowing atomic coordinate swaps. No global mutable state, external resolver, process, filesystem or network operation is added. Preserve existing z links and HTML anchors without silent link rewrites. If link diagnostics are collected, first replace the remaining backtracking decimal predicate with the shared linear scanner and keep diagnostic work bounded and cancellable.

## From the change's testing.md

# Testing

Test identity retention across text and binary; coordinate changes retain IDs; legacy no-ID documents remain valid; duplicate/invalid IDs and missing targets report paths. Test exact stale revision rejection, all-or-nothing multi-operation failure, operation limits, cancellation and Codable round trips. Preserve old text conformance. Execute pinned Trust 1.2.2 with Fledge 1.7.2 and SpecSync 6.0.0, including Swift/TypeScript/Rust existing checks and generated bundle drift. Tests and signer policy evidence are distinct.

## Execution receipt

## Requirement evidence

| Requirement | Actual evidence |
| --- | --- |
| REQ-ThreeMD-026 | DocumentIdentityTests verifies namespace preservation, text/binary round trips, owner-scoped reference identities, deterministic adoption, invalid IDs, budgets and cancellation. Included in the passing 222-case Swift lane. |
| REQ-ThreeMD-027 | DocumentEditingTests and CompositionEditingTests verify exact UTF-8 stale revisions, coordinated final-coordinate swaps, graph updates, Codable revision agreement, invalid later operations, limits and cancellation without partial publication. Included in the passing complete lane. |
| REQ-ThreeMD-028 | DocumentDiagnosticTests verifies actual parser line evidence, value-only structural paths, deterministic truncation, preflight source budgets before graph validation, count policy and cancellation. No legacy link extraction is claimed. |
| REQ-ThreeMD-029 | docs/EDITING-RELEASE.md and SPEC.md specify version separation, Swift-first capability matrix, source compatibility and explicit Sculpt migration boundary. Pinned Trust and strict contracts pass. Actual scoped agent review passed; unsigned provenance limitation remains under unchanged soft policy. PR61 stays open for Leif. |

## Run details

Root verified 0018a3c96d849ffb5966a9dd270b43b7d63541a6 with Trust1.2.2, Fledge1.7.2 and SpecSync6.0.0. The seven-step lane passed 222 Swift XCTest cases, 79 JavaScript tests, Rust conformance and three doc tests, formatting/build, element bundle drift and editor grammar. Forced strict contracts cover 28/28 files and 4491/4491 lines, 200/200 ThreeMD exports, three specs and zero warnings. Root's local raw log is /private/tmp/threemd-editing-final-trust.log; the targeted lifecycle check additionally retains command output in its verification record.

The initial implementation passed 219 Swift tests. Scoped review found expensive graph revalidation preceded the diagnostic source-work preflight. The correction charges bounded source work first and adds three regressions for budget ordering, graph count enforcement and cancellation. Scoped review then passed. Existing legacy link extraction is outside bounded diagnostics; Codable hosts must bound incoming transport bytes before Foundation decoding.

Trust reports progressive provenance passed with policy unsatisfied. No trusted-key signature or human GitHub review is claimed. Historical archives, text conformance fixtures, JavaScript/Rust source and generated element bundle remain unchanged.

## Where these lessons go

- `specs/ThreeMD/context.md`
