# Lesson bundle — prepare-coherent-threemd-2-0-0-package-metadata-and-honest-capability-and-migration-release-notes

Material for folding this change's lessons into the affected specs' `context.md`.
Synthesise from what actually happened below; do not restate the change description.

## What this change was

- **Title**: Prepare coherent ThreeMD 2.0.0 package metadata and honest capability and migration release notes
- **Kind**: Documentation
- **Specs**: ThreeMD, ThreeMDElement
- **Paths**: AGENTS.md, CHANGELOG.md, README.md, docs/EDITING-RELEASE.md, docs/RELEASE-2.0.0.md, js/package.json, js/README.md, element/package.json, element/README.md, editor/vscode/package.json, editor/vscode/README.md, rust/Cargo.toml, rust/Cargo.lock
- **Acceptance**: All JS library, element, VSCode and Rust package manifests plus Rust root lock declare 2.0.0; Swift remains tag-versioned. Prepared release notes accurately distinguish package version from unchanged text1.0, binary1 and composition3md-composition-1 contracts. Migration documents legacy compatibility, optional Apple LZFSE, platform and signed-provenance gaps, app-specific Sculpt formats and a separately verified dependency adoption. Source, fixture, element/dist, archived lifecycle and workflow/policy bytes stay unchanged. Focused manifest/lock/package inspections pass and root runs the exact-tip pinned Trust lane before closure. No tag, publication, deploy or policy changes occur.

## Evidence

- Verification commit: `1eb8ed2a3dd1b5db3c4b9cb64e38c451f7b8c44b`
- Base commit: `9dfbdb649891a95f27e7590e9e6ddc72b9e58d08`
- Verified by: `specsync check --spec ThreeMD --spec ThreeMDElement --strict`

## From the change's context.md

# Context

Leif directly requested: "Ok can we merge all the PRs and prep 2.0.0? Also can we use all this in sculpt.3md and continue working on sculpt". Root coordinates merges and Sculpt adoption. This change prepares library release metadata and documentation, with no tag or publication authority.

Root reports PR63 was merged by 0xLeif into PR62, then PR62 was merged into PR61 through normal GitHub gates. Leif merged PR61 into main at 9dfbdb649891a95f27e7590e9e6ddc72b9e58d08. Its tree is byte-identical to the prepared feature tip 20d1ed4f04333e18c36a50a44bf10e1b0e9b72e6. This new definition pins the landed main commit; archived implementation evidence keeps its real feature commits.

The package manifests currently disagree: JS library 1.0.0, Rust 1.0.0, element 1.7.17 and VSCode 0.1.0. Swift has no manifest release version. Version 2.0.0 is a coherent package release label, not a text grammar or storage schema migration.

The executing approval actor is agent:codex-threemd-editing, acting under the direct preparation instruction. This is agent scope approval, not a claim that Leif reviewed a diff, an independent human review or an authenticated signature. The existing soft Trust provenance policy and permitted-signature gap remain. Linux and Windows interchange execution is not established by the macOS receipt.

No source, fixtures, old archives, managed AGENTS block, dependency versions, workflows, policy or element/dist output changes are authorized in this bounded scope.

## From the change's design.md

# Design

Set the version field to 2.0.0 in js/package.json, element/package.json, editor/vscode/package.json and rust/Cargo.toml. Update only the Rust root package version in Cargo.lock. Package.swift remains unchanged because Swift Package Manager resolves release tags. Bun workspace locks do not contain version fields, so their bytes remain unchanged.

Existing release workflows already derive npm and crate versions from the release tag; inspect and document them without running or changing them. The element package version is aligned while its rendered text feature set remains unchanged. The VSCode extension retains syntax highlighting only and has no automatic Marketplace publication workflow.

Do not change ThreeMD parser/editor/codec implementations, public interfaces, frozen 1.0 grammar, container version 1, profile 3md-composition-1 or existing canonical requirements. no_spec_change is therefore true. The stored approval and real main base are recorded before changing release metadata.

Focused checks inspect valid JSON manifests, exact version agreement, Cargo metadata against the locked root package and unchanged runtime/artifact/policy trees. Root runs the exact-tip complete pinned Trust lane and strict SpecSync check, then arranges complementary review and closes this new scope. No reviewer claim invents a permitted signature or human diff review.

## Where these lessons go

- `specs/ThreeMD/context.md`
- `specs/ThreeMDElement/context.md`
