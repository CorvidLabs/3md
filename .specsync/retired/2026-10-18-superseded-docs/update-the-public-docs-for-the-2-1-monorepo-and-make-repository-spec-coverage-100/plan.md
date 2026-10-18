---
change: update-the-public-docs-for-the-2-1-monorepo-and-make-repository-spec-coverage-100
artifact: plan
---

# Plan

1. Capture hi for the docs and for 100% implementation coverage before adding specs.
2. Keep root SpecSync on the format libraries. Add the Linux shim to RookSculpture.
3. Teach `.atlasignore` the same exclusions for the nested app, docs, tests, manifests, and interchange harnesses.
4. Add `apps/sculpt/pathmap/SculptSources.spec.md` so Atlas at the repository root can see `apps/sculpt/Sources`. The Rook specs stay the behavioral contract and keep paths relative to `apps/sculpt`.
5. Update the public docs and regenerate `docs.3md` and `web/docs.3md`. Widen the pages workflow so a coverage-input change republishes the badge.
6. The corrected definition is recorded as `user:0xLeif` on 2026-10-08. The root canonical spec is ThreeMD only. The Linux shim stays on the app spec as `REQ-RookSculpture-046`. Closing approval is still open. Do not self-approve it.

## Approach

Keep root SpecSync on the format libraries and retain Sculpt's Rook behavioral contracts; correct Atlas root-relative coverage and public documentation according to the existing numbered plan.

## Out of scope

Do not treat compact .3mdb as an upstream ThreeMD standard, rewrite historical adoption receipts, or edit the separate in-progress Godot work, as context.md requires.

## Steps

Follow the six existing steps above, preserving the ThreeMD-only root canonical scope and the app shim's REQ-RookSculpture-046 contract. Closing approval remains open.

## Risks

Atlas matches paths from the repository root while Rook specs use apps/sculpt-relative paths. Root-anchored exclusions can accidentally count nested tests, docs, manifests and interchange harnesses; context.md records that mismatch.

## Constraints consulted

This normalization uses the existing plan.md and context.md, including the recorded hi/docs.md and hi/coverage.md intent references and the separate apps/sculpt/hi/ scope. It adds no approval or completion claim.
