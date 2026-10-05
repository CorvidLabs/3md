# Lesson bundle — limit-github-token-to-contents-read-in-the-ui-trust-and-cargo-publish-workflows

Material for folding this change's lessons into the affected specs' `context.md`.
Synthesise from what actually happened below; do not restate the change description.

## What this change was

- **Title**: Limit GITHUB_TOKEN to contents read in the UI, trust, and cargo-publish workflows
- **Kind**: BugFix
- **Paths**: .github/workflows/ui.yml, .github/workflows/trust.yml, .github/workflows/cargo-publish.yml, .specsync/workflow-v2-baseline.json, .specsync/adoption-report.json
- **Acceptance**: ui.yml, trust.yml, and cargo-publish.yml each set permissions.contents to read. CodeQL actions/missing-workflow-permissions is clean for those workflows. The trust gate and the UI lab still pass with that token. New changes use the SpecSync 6 workflow-v2 baseline. Canonical specs and parser behavior stay unchanged.

## Evidence

- Verification commit: `777427d6c89dd55eead16a3d46e4e97894ef2a6f`
- Base commit: `fb70a0c9c9ab41c93c882514b8af2ca760626fb2`
- Verified by: `specsync check (no spec in scope)`

## From the change's context.md

# Context

CodeQL alerts 7, 8, and 9 on main reported `actions/missing-workflow-permissions` for `cargo-publish.yml`, `trust.yml`, and `ui.yml`. Those three workflows had no `permissions` key, so the job token inherited the repository default.

The other workflows already declare permissions. `pages.yml` and `post-release-formula.yml` do it at workflow scope. `publish.yml` does it per job because npm provenance needs `id-token: write`.

This change limits the three flagged workflows to `contents: read`. It does not change parser behavior or canonical specs. crates.io still uses `CRATES_IO_TOKEN`. SpecSync PR comments stay off. `upload-artifact@v4` uses the Actions runtime token.

The workflow edit is commit `fb70a0c` on PR 57. The repository was still on the SpecSync 5.0.1 change workflow, so this record also adopts the workflow-v2 baseline at cutoff `8712c68`. Existing accepted changes stay workflow v1. This change is workflow v2 and finalizes on the delivery PR.

## From the change's design.md

# Design

Each flagged workflow gets one workflow-level block:

```yaml
permissions:
  contents: read
```

Workflow scope is enough because each file has a single job and no job needs a broader token. A later job that posts comments, writes packages, or publishes Pages must add its own job-level block rather than widening this default.

`contents: read` allows checkout and public release downloads. It does not allow the job token to push, open pull requests, or write checks. Publish secrets stay separate from `GITHUB_TOKEN`.

The workflow-v2 baseline is a cutoff marker. It does not change canonical specs. Changes created after the cutoff use `change review` and `change finalize`. Changes already accepted under workflow v1 stay on that evidence.

## From the change's testing.md

# Testing

- `fledge lanes run verify` passed locally on `fb70a0c` (Swift lint, build, tests, TypeScript, Rust, element bundle, editor grammar).
- `cd js && bun run typecheck` passed.
- Augur on the staged workflow diff returned proceed, risk 29.7.
- PR 57 on `fb70a0c`: CodeQL Analyze (actions), Analyze (javascript-typescript), Analyze (rust), Analyze (swift), CodeQL, Interactive lab, and trust all passed.
- `cargo-publish.yml` does not run on pull requests. Its contract is the declared `contents: read` block plus checkout and `CRATES_IO_TOKEN` at release time.
- Canonical spec behavior is unchanged. `specsync check` remains the contract check because no spec is in scope.
- `specsync change status` must report workflow v2 for this change, and `change finalize` must archive it on PR 57 before merge.

## Where these lessons go

This change declared no affected specs, so there is no module context to fold into.
