---
change: update-the-public-docs-for-the-2-1-monorepo-and-make-repository-spec-coverage-100
artifact: testing
---

# Testing

## Requirement evidence

| ID | Canonical | Evidence |
| --- | --- | --- |
| REQ-ThreeMD-044 | REQ-ThreeMD-044 | README.md leads with ThreeMD 2.1.0, the text file, binary, and Kind 1 as deprecated. js/README.md, element/README.md, CHANGELOG.md, and docs/RELEASE-2.1.0.md say the registries serve 2.1.0. On 2026-10-08, `npm view @corvidlabs/threemd version` and `npm view @corvidlabs/three-md-element version` returned 2.1.0, and crates.io `threemd` max_version was 2.1.0. |
| REQ-ThreeMD-045 | REQ-ThreeMD-045 | README.md, CONTRIBUTING.md, AGENTS.md, and ROADMAP.md name Sculpt.3md at apps/sculpt, package name Rook, building against this checkout. They keep Swift, TypeScript, and Rust as the three parsers. They do not call the app a fourth parser, and they do not call compact `.3mdb` the upstream binary standard. |

- `hi check` at the repository root reports no problems.
- `specsync check` at the repository root stays 55/55 and 21172/21172.
- `specsync check` in `apps/sculpt` reports 94/94 and 25536/25536.
- `fledge atlas . --json` reports `coverage_pct` 100 and zero orphan files.
- `bun scripts/build-docs-3md.mjs` regenerates both docs bundles from the edited Markdown.
- No parser, fixture, or package-dependency change. The 2.0 portable interchange goldens are not regenerated.
