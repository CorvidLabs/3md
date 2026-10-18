---
id: retire-the-superseded-threemd-2-1-documentation-workspace-as-an-unchanged-historical-snapshot
state: implementing
type: operations
base_commit: 48ff62f8e44f4b6cced9e35c984085764659c282
---

# Retire the superseded ThreeMD 2.1 documentation workspace as an unchanged historical snapshot

## Intent

Retire the superseded ThreeMD 2.1 documentation workspace as an unchanged historical snapshot

## Affected Canonical Specs

- None

## Acceptance Criteria

- Preserve every file and original verifying state of the superseded 2.1 documentation workspace byte-for-byte under a dated .specsync/retired snapshot with SHA-256 manifest and explicit non-finalized label. Preserve canonical/source tree, prior approvals and archives. Do not reapply obsolete 2.1 requirements. Keep all other unresolved active work and strict policy audit failures visible. Verify manifest, unchanged trees and scope; current retirement operation requires actual definition approval and current human review before native finalization. No merge, release, deployment or engine change.

## No-spec Rationale

The 2.1 documentation delta was superseded by canonical 2.2.0 and 2.2.1 release documentation. Preserve its current workspace bytes and verifying state as non-finalized history; do not replay its stale delta or change living specs.
