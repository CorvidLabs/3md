---
change: prepare-coherent-threemd-2-0-0-package-metadata-and-honest-capability-and-migration-release-notes
artifact: tasks
---

# Tasks

- [x] Synchronize the four package manifest versions and Rust root lock to 2.0.0 without dependency churn.
- [x] Prepare CHANGELOG, README, current release scope and capability/migration/checklist documentation.
- [x] Confirm focused manifest and locked package metadata checks and unchanged runtime/artifact/policy paths.
- [x] Root runs complete pinned Trust and strict SpecSync validation on the final implementation tip.

Root verified metadata source `87f7d96f9aecdf8932d285515e9786358a60e9e5`:
Trust 1.2.2's eight-step lane passed in 70.080 seconds with 244 Swift tests,
141 TypeScript tests, 31 Rust tests and three doctests, mandatory Node/public
package builds and all 426 interchange cases / 16,983 imports. Forced strict
SpecSync checked three specs with zero warnings, 41/41 source files,
11,900/11,900 lines and 269/269 core exports. The two existing draft specs
retain their validation limits. Raw receipts are `/private/tmp/3md-2-release-trust.log`
and `/private/tmp/3md-2-release-contracts.log`. Trust reports risk43 review and
passes with unchanged progressive provenance degradation; no permitted signature
or human approval is claimed.

Publication, GitHub review/merge gates, tags, package publishing and release are later handoffs, not prerequisites that this implementation task silently claims complete.
