---
id: prepare-coherent-threemd-2-0-0-package-metadata-and-honest-capability-and-migration-release-notes
state: approved
type: documentation
base_commit: 9dfbdb649891a95f27e7590e9e6ddc72b9e58d08
---

# Prepare coherent ThreeMD 2.0.0 package metadata and honest capability and migration release notes

## Intent

Prepare coherent ThreeMD 2.0.0 package metadata and honest capability and migration release notes

## Affected Canonical Specs

- `ThreeMD`
- `ThreeMDElement`

## Acceptance Criteria

- All JS library, element, VSCode and Rust package manifests plus Rust root lock declare 2.0.0; Swift remains tag-versioned. Prepared release notes accurately distinguish package version from unchanged text1.0, binary1 and composition3md-composition-1 contracts. Migration documents legacy compatibility, optional Apple LZFSE, platform and signed-provenance gaps, app-specific Sculpt formats and a separately verified dependency adoption. Source, fixture, element/dist, archived lifecycle and workflow/policy bytes stay unchanged. Focused manifest/lock/package inspections pass and root runs the exact-tip pinned Trust lane before closure. No tag, publication, deploy or policy changes occur.

## No-spec Rationale

Only package version declarations and current release documentation change. The existing ThreeMD, CLI and element behavior, public API, text grammar, binary/profile versions, runtime policies, conformance fixtures and canonical requirements are unchanged.
