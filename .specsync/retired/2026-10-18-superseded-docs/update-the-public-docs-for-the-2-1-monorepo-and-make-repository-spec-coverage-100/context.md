---
change: update-the-public-docs-for-the-2-1-monorepo-and-make-repository-spec-coverage-100
artifact: context
---

# Context

The public spec coverage badge is Atlas, rendered by the pages workflow from the repository root. After Sculpt.3md landed, that count fell to 32%. Root `specsync check` stayed 55/55 because its source dirs are only the format libraries. Sculpt's own check was 93/94 because `Sources/CLzfse/shim.h` was not listed. Atlas matches spec paths exactly from the repository root, and the Rook specs list paths from `apps/sculpt`.

The denominator also counted the app's tests, docs, package manifest, and two interchange harnesses. `.atlasignore` is root-anchored, so the existing exclusions for `Tests/`, `docs/`, `Package.swift`, `scripts/`, and `Examples/` did not apply inside `apps/sculpt` or to `js/scripts/` and `rust/examples/`.

Hi for this change is `hi/docs.md` and `hi/coverage.md`. App intent stays in `apps/sculpt/hi/`. Do not treat compact `.3mdb` as an upstream ThreeMD standard. Do not rewrite historical adoption receipts. Do not edit the in-progress Godot work on the primary checkout. The corrected definition is approved as `user:0xLeif` on 2026-10-08. The root canonical spec is ThreeMD only. The shim contract stays on the app spec as `REQ-RookSculpture-046` because `REQ-RookSculpture-043` is already the native insertion budget. Closing approval has not been recorded.
