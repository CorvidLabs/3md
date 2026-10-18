---
change: retire-the-superseded-threemd-2-1-documentation-workspace-as-an-unchanged-historical-snapshot
artifact: context
---

# Context

The public-docs/coverage record remains verifying with a 2.1.0 ADDED delta. Canonical REQ-ThreeMD-044 now states published 2.2.1 facts from commit 4e718b4 (PR84), following fe20a18 (PR80). Replaying the old delta would revert living release facts. Native check rejects it. Retirement preserves original evidence without claiming successful acceptance. The user requested manual archival; this concrete retirement definition remains unapproved.

## Observed retirement results

All 12 source files and the original verifying state are preserved exactly under .specsync/retired/2026-10-18-superseded-docs/. The SHA-256 manifest identifies source commit 48ff62f8e44f4b6cced9e35c984085764659c282. All 2256 tracked non-lifecycle files are unchanged. Filesystem negative fixtures reject missing, altered and extra files and an invented archived state. Canonical strict validation and lifecycle regression controls pass. The strict active audit still reports the policy coverage issue; no diagnostic is suppressed. All five other inherited records remain active. Human implementation review and finalization of this retirement operation are pending.

The first post-move audit also marked the two viewer verification records stale because retired files enter the project-input digest. Both viewer records were refreshed successfully with native strict check/commit. This refresh records automated evidence only; human review remains pending.
