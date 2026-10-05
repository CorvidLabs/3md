---
id: limit-github-token-to-contents-read-in-the-ui-trust-and-cargo-publish-workflows
state: implementing
type: bug_fix
base_commit: fb70a0c9c9ab41c93c882514b8af2ca760626fb2
---

# Limit GITHUB_TOKEN to contents read in the UI, trust, and cargo-publish workflows

## Intent

Limit GITHUB_TOKEN to contents read in the UI, trust, and cargo-publish workflows

## Affected Canonical Specs

- None

## Acceptance Criteria

- ui.yml, trust.yml, and cargo-publish.yml each set permissions.contents to read. CodeQL actions/missing-workflow-permissions is clean for those workflows. The trust gate and the UI lab still pass with that token. New changes use the SpecSync 6 workflow-v2 baseline. Canonical specs and parser behavior stay unchanged.

## No-spec Rationale

Workflow token permissions and the SpecSync 6 workflow-v2 baseline only. Parser behavior and the ThreeMD, ThreeMDCLI, and ThreeMDElement contracts stay the same.
