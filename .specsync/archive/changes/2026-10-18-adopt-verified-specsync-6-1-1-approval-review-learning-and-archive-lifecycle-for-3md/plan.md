---
change: adopt-verified-specsync-6-1-1-approval-review-learning-and-archive-lifecycle-for-3md
artifact: plan
---

# Plan

## Approach

Pin the installed lifecycle writer and Trust selector to 6.1.1, retain Trust 1.2.2 and Fledge pins. Extend root meaningful paths to gdscript/, apps/sculpt/ and .agents/. Root lifecycle owns Sculpt operations; preserve nested specs and the existing Linux Sculpt and macOS app lanes. Do not invent a nested SDD policy or change its hashes.

Exact 6.1.1 writer and action inputs; required meaningful source/test/governance coverage; genuine human definition approval before implementation; separate current scoped human review of the implementation; actual product tests distinct from canonical checks and active-workspace audit; same-PR finalize/archive before merge; read prior lessons and record observed findings with evidence and limits. Preserve all stronger existing checks, risk thresholds, signer policies, archives and unrelated work.

## Out of scope

No product functional behavior, dependency upgrades, credentials, branch protections, main pushes, merges, tags, releases, deployments, VPS access, production services or historical acceptance repairs. No Bot #230 or paused AlgoChat Fledge work. Keep .specsync/version bytes unchanged; it is a lifecycle format stamp.

## Steps

1. Human inspects and approves this exact definition; resolve overlaps before implementation.
2. Pin only declared selectors and regenerate installed agent integrations with verified 6.1.1; inspect generated diff and retain local guidance.
3. Add required meaningful path coverage and a non-mutating lifecycle guard. Preserve existing workflow jobs.
4. Run product gates, canonical check and active audit separately; disclose baseline debt and resolve it only through separately authorized owner work.
5. Publish a tested draft PR only after applicable publication checks pass. Obtain actual current human implementation review.
6. Record only authentic review; finalize/archive on the same PR after evidence and lessons are ready. No merge in this scope.

## Risks

Inherited active records may block a strict global audit/archive guard. Do not accept them retroactively or add exclusions. The rollout stays blocked where stronger enforcement exposes debt. Linux cannot establish macOS or browser visual acceptance.

## Constraints consulted

PR #98 (0xLeif) owns element bundle cleanup/fledge.toml. Preserve element/dist and historical archives. Linux checks do not establish macOS Sculpt UI acceptance.

- .specsync/archive/changes/2026-10-10-record-viewer-navigation-verification-evidence-for-the-approved-archive/lesson-bundle.md
- .specsync/archive/changes/2026-10-10-repair-blurry-cubes-and-slice-canvases-after-view-and-display-size-changes-while-retaining-the-webgl-context-and-camera/lesson-bundle.md
