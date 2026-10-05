---
change: prepare-coherent-threemd-2-0-0-package-metadata-and-honest-capability-and-migration-release-notes
artifact: design
---

# Design

Set the version field to 2.0.0 in js/package.json, element/package.json, editor/vscode/package.json and rust/Cargo.toml. Update only the Rust root package version in Cargo.lock. Package.swift remains unchanged because Swift Package Manager resolves release tags. Bun workspace locks do not contain version fields, so their bytes remain unchanged.

Existing release workflows already derive npm and crate versions from the release tag; inspect and document them without running or changing them. The element package version is aligned while its rendered text feature set remains unchanged. The VSCode extension retains syntax highlighting only and has no automatic Marketplace publication workflow.

Do not change ThreeMD parser/editor/codec implementations, public interfaces, frozen 1.0 grammar, container version 1, profile 3md-composition-1 or existing canonical requirements. no_spec_change is therefore true. The stored approval and real main base are recorded before changing release metadata.

Focused checks inspect valid JSON manifests, exact version agreement, Cargo metadata against the locked root package and unchanged runtime/artifact/policy trees. Root runs the exact-tip complete pinned Trust lane and strict SpecSync check, then arranges complementary review and closes this new scope. No reviewer claim invents a permitted signature or human diff review.
