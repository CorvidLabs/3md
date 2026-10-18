# Lesson bundle — adopt-verified-specsync-6-1-1-approval-review-learning-and-archive-lifecycle-for-3md

Material for folding this change's lessons into each affected module's lesson file.
Synthesise from what actually happened below; do not restate the change description.

## What this change was

- **Title**: Adopt verified SpecSync 6.1.1 approval review learning and archive lifecycle for 3md
- **Kind**: Operations
- **Paths**: .github/workflows/trust.yml, .specsync/sdd.json, AGENTS.md, scripts/check-specsync-lifecycle.sh, scripts/test-specsync-lifecycle.sh, .codex/skills/spec-sync/SKILL.md, .cursor/skills/spec-sync/SKILL.md, .gemini/skills/spec-sync/SKILL.md, .claude/skills/spec-sync/SKILL.md
- **Acceptance**: Exact 6.1.1 writer and action inputs; required meaningful source/test/governance coverage; genuine human definition approval before implementation; separate current scoped human review of the implementation; actual product tests distinct from canonical checks and active-workspace audit; same-PR finalize/archive before merge; read prior lessons and record observed findings with evidence and limits. Preserve all stronger existing checks, risk thresholds, signer policies, archives and unrelated work. A non-mutating lifecycle guard fails for a wrong engine, disabled policy, uncovered meaningful path or unfinished active workspace and passes a clean finalized fixture. No fabricated approvals or inherited-history repairs. Human review and finalization remain pending until they actually happen.

## Evidence

- Verification commit: `aa35d5cff5df3eeac55f69dba538026e6c9da2a6`
- Base commit: `c19963be38ec9843b738c1dc335c53809bb99207`
- Verified by: `specsync check (no spec in scope)`

## From the change's context.md

# Context

## Status

Prepared by agent:codex using the authenticated corvid-agent GitHub account. Proposed interview answers are agent drafting from the user request, not a new human decision. Definition approval: pending. Implementation acceptance/review: pending. No approve, review, check, finalize, push or PR publication was performed for this change.

Exact base: `c19963be38ec9843b738c1dc335c53809bb99207` on `main`; isolated branch `codex/specsync-611-definition`.

## Ownership

PR #98 (0xLeif) owns element bundle cleanup/fledge.toml. Preserve element/dist and historical archives. Linux checks do not establish macOS Sculpt UI acceptance.

Host-Mac _notes #69 comment 6245284491 owns Bot policy; Raven #418 is merged and excluded. Site #537 is closed unmerged. The 197-repository audit is not this target list.

## Evidence-backed observations

The isolated official Linux aarch64 6.1.1 archive passed its published SHA-256 check and reports specsync 6.1.1. The global PATH writer is 6.1.0 and must not write these records. Arcsite Trust 1.2.0 action.yml supports specsync-version. Broad rollout permission does not approve these newly written definitions.

## Learning plan

Read the existing instruction/spec context and cited lessons before implementing. Record observed failure, fix, command/evidence, applicability limits and remaining question in this change context. Promote only reusable supported findings; do not claim a new product lesson from an unrun test. Preserve historical lesson bundles.

- .specsync/archive/changes/2026-10-10-record-viewer-navigation-verification-evidence-for-the-approved-archive/lesson-bundle.md
- .specsync/archive/changes/2026-10-10-repair-blurry-cubes-and-slice-canvases-after-view-and-display-size-changes-while-retaining-the-webgl-context-and-camera/lesson-bundle.md

## Resume

Use the isolated 6.1.1 binary with `change status adopt-verified-specsync-6-1-1-approval-review-learning-and-archive-lifecycle-for-3md`. Definition approval and implementation review remain separate human decisions.

## From the change's design.md

# Design

## Operations design

Pin the installed lifecycle writer and Trust selector to 6.1.1, retain Trust 1.2.2 and Fledge pins. Extend root meaningful paths to gdscript/, apps/sculpt/ and .agents/. Root lifecycle owns Sculpt operations; preserve nested specs and the existing Linux Sculpt and macOS app lanes. Do not invent a nested SDD policy or change its hashes.

The guard runs separately from canonical validation and product tasks to avoid recursive verification. It checks exact engine, required flags and native strict active audit, then refuses unfinished active workspaces. It never changes state, signs evidence, or repairs archives. Inherited debt is a blocker rather than a baseline exemption.

Learning stays in native change context/lesson bundles and applicable existing skills. Stronger risk and provenance controls remain unchanged.

## From the change's testing.md

# Testing

## Planned local tests (not run)

- `fledge lanes run verify`
- `swift test --package-path apps/sculpt --no-parallel --skip deterministicPortableInterchangeFixtures`
- `fledge run gdscript`
- `fledge lanes run sculpt (macOS only)`

Run the exact pinned writer: `specsync --version` must report 6.1.1. Run `specsync check --force --strict`, `specsync change audit --strict`, then scoped `specsync change check adopt-verified-specsync-6-1-1-approval-review-learning-and-archive-lifecycle-for-3md --strict` only after definition approval and implementation. The operations no-spec check alone is not product testing. Preserve current coverage thresholds. Run the repository Trust gate where configured and qualified; report missing prerequisites or provenance failures without weakening them.

## Lifecycle regression controls

In disposable fixture repositories, compare an unchanged-policy clean finalized case against uncovered source/test/governance changes, wrong 6.1.0 engine, disabled flags and active/unfinalized workspaces. Each negative control must fail for the intended reason. Verify existing checks still execute and an archive-only follow-up can pass without creating an approval/review record. No human identity is invented for fixtures; controls needing authentic human acceptance remain manual.

## Baseline versus candidate

Baseline command outputs and exit codes live outside this repository in the rollout evidence directory at exact base c19963be38ec9843b738c1dc335c53809bb99207. They are not implementation validation. Re-run baselines after any base update. New failures belong to this candidate; inherited failures remain owner debt. No product tests have run in this preparation.

## Where these lessons go

This change declared no affected specs, so there is no module context to fold into.
