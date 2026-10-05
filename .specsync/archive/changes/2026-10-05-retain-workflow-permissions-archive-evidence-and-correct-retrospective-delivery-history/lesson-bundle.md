# Lesson bundle: retain-workflow-permissions-archive-evidence-and-correct-retrospective-delivery-history

Material for folding this change's lessons into the affected specs' `context.md`.
Synthesise from what actually happened below; do not restate the change description.

## What this change was

- **Title**: Retain workflow permissions archive evidence and correct retrospective delivery history
- **Kind**: Documentation
- **Paths**: docs/evidence/workflow-permissions-archive/
- **Acceptance**: The original implementation commit 777427d6c89dd55eead16a3d46e4e97894ef2a6f is retained under a dedicated named evidence branch, retrievable from GitHub and fetchable into a fresh repository; its tree equals the archived implementation_tree. An additive correction note records both squash mappings, the post-PR57 definition/finalization chronology, preserved legacy delivery hashes, agent review and degraded unsigned provenance. Original archive files, workflows, parser, format, language ports, canonical specs, generated product bundles and existing local untracked Atlas files are unchanged. Actual verification and delegated lifecycle records remain distinct from human review or trusted signatures.

## Evidence

- Verification commit: `50d6a54ee5873c5659edb052b431bf300011597e`
- Base commit: `8b09724fc390236f52c873761247166048aef67e`
- Verified by: `specsync check (no spec in scope)`

## From the change's context.md

# Context

Leif said "do it" after the read-only review of landed 8b09724 identified unavailable implementation evidence and inaccurate delivery chronology. The actual executing agent records delegated authorization for this bounded repair, without claiming human diff review or signer authority.

The archive pins local commit 777427d6c89dd55eead16a3d46e4e97894ef2a6f, tree 8858ce95114438865fbb981fcfb83c283f6302e9. GitHub returned HTTP422 for that commit. Retain that existing object without rewriting it. Its historical tree includes previously committed Atlas blobs; they are historical evidence only. Current untracked Atlas files are not staged, rebuilt or copied into this repair.

PR57 merged before the definition was created; PR59 archived the later records. Original records remain immutable. PR58 is outside scope.

## From the change's design.md

# Design

Retain refs/heads/leif/evidence-workflow-permissions-777427d at the original commit. This historical evidence branch must remain while the archive relies on it. It is not a feature to merge or a release tag; forced updates are not authorized.

The repair feature branch starts at landed 8b09724 and adds documentation plus its own workflow-v2 lifecycle record. Add a correction rather than altering old cryptographic preimages. The historical evidence tree has generated/lifecycle differences from main; compare its workflow and product files separately.

## From the change's testing.md

# Testing

Query GitHub for the retained commit, then fetch only the dedicated ref into a fresh bare repository. Verify exactly 777427d6c89dd55eead16a3d46e4e97894ef2a6f and tree 8858ce95114438865fbb981fcfb83c283f6302e9. Recompute archived review/finalization digests and legacy delivery hashes. Confirm original archives and product/workflow/spec/bundle paths equal 8b09724.

Run required pinned Trust and forced strict SpecSync 6 validation. Record actual outputs and an unsigned executing-agent Attest claim without a human or signer flag. Existing progressive policy remains unchanged. No new product test implementation is needed for this documentation and retention repair.

## Actual implementation checkpoint

At 814efb9ec60f3f1c5198c5c4b3bc7f939746c506, the pinned Trust 1.2.2 gate passed all seven native steps in 28.168 seconds: 129 Swift tests, 79 JavaScript tests, Rust conformance and three documentation tests, formatter/clippy, generated-bundle drift and editor grammar. Forced strict SpecSync 6 validation passed three specs with no warnings, 14/14 files and 2002/2002 source lines covered; existing draft specs retain their documented section/export skips. Risk was proceed at 33. Progressive provenance remained degraded. The actual executing-agent Attest claim is unsigned; strict policy verification reports missing signature and a reviewer outside the unchanged allow-list.

GitHub resolves the retained original SHA/tree, and a fresh bare repository fetched the named evidence ref and main baseline. Its product/workflow/spec/provenance-policy diff against 8b09724 is empty. The correction branch's original archive and implementation diff against that baseline is empty. Current local Atlas files remain untracked and unchanged. The original review/finalization digests and all 37 delivery payload entries were verified in the preceding read-only audit. Current verification is distinct from those historical checks.

## Where these lessons go

This change declared no affected specs, so there is no module context to fold into.
