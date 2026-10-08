---
id: update-the-public-docs-for-the-2-1-monorepo-and-make-repository-spec-coverage-100
state: implementing
type: feature
base_commit: e2eada6648eb8d66899274641574c6e6ec42c49a
---

# Update the public docs for the 2.1 monorepo and make repository spec coverage 100%.

## Intent

Update the public docs for the 2.1 monorepo and make repository spec coverage 100%.

## Affected Canonical Specs

- `ThreeMD`

## Acceptance Criteria

- The README leads with ThreeMD 2.1.0, the text file, and binary, and it names Kind 1 as deprecated. It shows Sculpt.3md nested at apps/sculpt with package name Rook, building against this checkout. Install docs say npm @corvidlabs/threemd 2.1.0 and crates.io threemd 2.1.0 are published. Contributor docs still require format changes in Swift, TypeScript, and Rust, and they do not call the app a fourth parser. fledge atlas at the repo root reports 100% implementation coverage. specsync check at the repo root stays 55/55. specsync check in apps/sculpt reports 94/94. Historical release receipts are not rewritten into a claim that Sculpt compact .3mdb is the upstream standard. The root canonical spec for this change is ThreeMD only. The Linux shim stays on the app spec as REQ-RookSculpture-046 and is not a root format spec.

## No-spec Rationale

Not applicable
