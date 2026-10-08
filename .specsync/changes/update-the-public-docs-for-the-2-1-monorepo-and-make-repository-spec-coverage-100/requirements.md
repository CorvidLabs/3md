---
change: update-the-public-docs-for-the-2-1-monorepo-and-make-repository-spec-coverage-100
artifact: requirements
---

# Requirements

- **REQ-ThreeMD-044** The public docs SHALL describe ThreeMD 2.1.0 as the current library, with the text file and binary named as the two saves, and SHALL name Kind 1 as deprecated. They SHALL say npm and crates.io serve 2.1.0.
- **REQ-ThreeMD-045** The public docs SHALL identify Sculpt.3md as the nested Mac app at `apps/sculpt`, package name Rook, building against this checkout. They SHALL keep Swift, TypeScript, and Rust as the three format parsers. They SHALL NOT call the app a fourth parser or call its compact `.3mdb` the upstream binary standard.
- The Linux shim stays on the app spec as living **REQ-RookSculpture-046**. `Sources/CLzfse/shim.h` is listed there, and `specsync check` from `apps/sculpt` reports 94/94. That requirement is not a root canonical delta. Living **REQ-RookSculpture-043** stays the native insertion budget.
