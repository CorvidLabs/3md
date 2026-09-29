---
id: CHG-0001-adopt-trust-1-and-specsync-5
state: archived
type: migration
base_commit: 2a145766b9ecb83d96ee15aa453a65cc2125571f
---

# Adopt Trust 1 and SpecSync 5

## Intent

Adopt Trust 1 and SpecSync 5

## Affected Canonical Specs

- None

## Acceptance Criteria

- Trust 1.0.0 runs the existing verify lane
- SpecSync 5.0.1 strict validation passes
- Claude Cursor Codex and Gemini integrations report installed

## No-spec Rationale

Tooling policy migration; no product API or canonical module contract changes.

## Migration Note

Migrated by hand to SpecSync 6 per Leif's decision (2026-09-28); the 6.0.0 tool refused to archive this legacy record (`` exact-only delivery input `.github/workflows/trust.yml` changed after acceptance and requires an audited reopen; run `specsync change reopen CHG-0001-adopt-trust-1-and-specsync-5` to re-verify the accepted change, or supersede it from a later change under a module granted the path by `owns` in `.specsync/config.toml` ``).

- Workflow v1 (SpecSync 5) record, accepted on 2026-07-14 by the closing approval already stored in `approvals.json`. SpecSync 6.0.0 reports its accepted evidence as stale, for the reason quoted above.
- Moved by hand from `.specsync/changes/CHG-0001-adopt-trust-1-and-specsync-5/` into the layout `specsync change archive` writes: `accepted-state.json` is the unchanged accepted `state.json`, `state.json` is marked `archived`, and this file's front matter says `archived`.
- `approvals.json`, `verification.json`, `verification-attempts.json` and every other artifact are the original SpecSync 5 evidence, unchanged. `verification.json` verifies commit `01263f573ae8d89b58f04c2be84b041164c8d789`, not the tree this record was archived from.
- This migration added no verification evidence, test result, attempt history, or approval. It is a manual migration, not a fresh re-verification.
- Closing it through the tool takes `specsync change reopen`, `specsync change verify`, then `specsync change accept`, which writes a new closing approval. Per Leif's decision it was archived by hand instead, so no reopen or new approval is recorded.
