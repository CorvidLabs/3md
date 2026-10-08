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
