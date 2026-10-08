---
id: add-gdscript-as-a-fourth-supported-threemd-language-a-godot-4-addon-that-parses-serializes-stores-composes-and-edits
state: draft
type: feature
base_commit: 773d927edb1e80d0561c4d8a1d155127c7e4d156
---

# Add GDScript as a fourth supported ThreeMD language: a Godot 4 addon that parses, serializes, stores, composes and edits 3md documents with the same behavior as Swift, TypeScript and Rust, so games can use the format natively

## Intent

Add GDScript as a fourth supported ThreeMD language: a Godot 4 addon that parses, serializes, stores, composes and edits 3md documents with the same behavior as Swift, TypeScript and Rust, so games can use the format natively

## Affected Canonical Specs

- `ThreeMD`

## Acceptance Criteria

- A Godot 4 addon under gdscript/ parses, serializes, stores, composes, resolves linked files and edits ThreeMD documents with the same results as Swift, TypeScript and Rust. Headless Godot runs the shared conformance vectors. Canonical text, payload kind 2 and payload kind 1 are byte-identical with the other writers. LZFSE is an explicit unsupported backend. The library does no file or network I/O; a separate Godot helper reads project files for games. The interchange gate adds a GDScript adapter and checks every writer/reader pair. The text grammar, binary envelope and composition profile stay unchanged. README and CONTRIBUTING name GDScript and show how to copy the addon into a Godot project. A small example uses planes as game layers. The fledge gdscript task runs the suite. This change does not publish, tag or weaken trust policy.

## No-spec Rationale

Not applicable
