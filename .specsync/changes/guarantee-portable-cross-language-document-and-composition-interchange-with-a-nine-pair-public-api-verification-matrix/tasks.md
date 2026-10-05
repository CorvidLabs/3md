---
change: guarantee-portable-cross-language-document-and-composition-interchange-with-a-nine-pair-public-api-verification-matrix
artifact: tasks
---

# Tasks

- [x] Implement the mandatory interchange catalog, Swift coordinator and three public-API adapters.
- [x] Repair confirmed portable import/export differences with language-local regressions.
- [x] Integrate package build/typecheck/Node runtime and update current contracts and capability documentation.
- [x] Run the complete pinned verification and resolve scoped implementation review findings.
- [x] Prepare accurate PR and verification evidence for Leif.

Complete pinned Trust passed at 55efdaab7efd2a12e78f3602af35c7e7b08322c0:
244 Swift tests, 141 TypeScript tests, 31 Rust tests and three doctests, all
existing gates and 426 matrix cases with 16,983 imports. The final one-line
catalog enforcement repair is committed at 6b6be79eeda12b7ff20b5a06b2c2470a94de0eee
and its full matrix and harness regressions pass. Complementary scoped peer
reviews passed with all reproduced findings resolved; no independent human
review or permitted signature is claimed. The PR body is prepared locally.

The official implementation check repeats required verification after canonical
materialization. Lifecycle review/finalization, publication and CI remain later
milestones until performed; these checkboxes do not claim those events.

Scoped lifecycle review, finalization, feature publication and CI follow the prerequisite implementation check. They are recorded only when actually performed. Leif merges later; this work does not merge, release or push main.
