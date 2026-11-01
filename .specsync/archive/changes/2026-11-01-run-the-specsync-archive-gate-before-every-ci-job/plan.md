---
change: run-the-specsync-archive-gate-before-every-ci-job
artifact: plan
---

# Plan

## Approach

Insert the same Archive job at the top of `jobs:` in each pull request or push
workflow and make every other job in those workflows need it.

## Out of scope

- The release and dispatch only workflows: cargo-publish, post-release-formula
  and publish.
- The six changes already open under `.specsync/changes/`.
- The org ruleset that requires the Archive check.
- Moving the action pin to a published release.

## Steps

1. Add the `archive-gate` job named `Archive` to linux.yml, pages.yml,
   sculpt.yml, trust.yml and ui.yml, pinned to
   106aaa43d0bcf049f19b173ddb63815a25c3f931.
2. Add `needs: archive-gate` to the linux, deploy, sculpt, trust and lab jobs.
3. Parse every edited file and print each job's `needs` to confirm the graph.
4. Run the archive readiness script, `specsync change audit --strict` and
   `specsync check --strict`.

## Risks

- While any change is open, no other CI job runs on that pull request. This is
  intended, but it means the six open changes at the base commit keep the
  Archive check red until their owners archive them.
- The action is pinned to a main branch commit rather than a release until a
  release ships the gate.

## Constraints consulted

- AGENTS.md: use SpecSync 6.0.0 for lifecycle writers; do not weaken a trust
  gate (Trust and its strict SpecSync contract are unchanged and only gain a
  dependency); no merge, main push, tag or release.
- Pull request template: no em-dash characters in committed text.
