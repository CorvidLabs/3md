---
change: add-gdscript-as-a-fourth-supported-threemd-language-a-godot-4-addon-that-parses-serializes-stores-composes-and-edits
artifact: docs
---

# Docs

README and CONTRIBUTING gain a GDScript section when the suite is green.

The section tells a game author to copy `gdscript/addons/threemd` into their project's `addons/threemd`, enable the plugin, and call `ThreeMDParser.parse` or `ThreeMDFiles` on a file inside the project. It states that LZFSE files are refused, and that the addon does not watch the filesystem or fetch remote documents.

The example is a few planes used as layers. It is not an HTML renderer port.

SPEC.md does not gain a new payload kind or grammar version. The supported-languages sentence in the spec and README names GDScript next to Swift, TypeScript, and Rust after the conformance suite passes.

No changelog version bump and no package publish are part of this change.
