---
change: finish-threemd-2-0-0-with-a-linux-cli-build-fix-pinned-publish-workflows-and-release-documentation
artifact: design
---

# Design

- CLI: add a private `writeStandardError(_:)` helper in Sources/CLI/main.swift and replace each `fputs(<message>, stderr)` with it. Messages, ordering and exit codes are unchanged; only the write path changes.
- publish.yml: both "Upgrade npm for OIDC trusted publishing" steps install `npm@^11.5.1`; the stale element install comment is corrected. Permissions, triggers and publish commands are unchanged.
- cargo-publish.yml: replace the sed rewrite with a step that resolves the tag from the release event (or the dispatched ref), refuses anything that is not a vX.Y.Z tag, and fails unless `cargo metadata --locked` reports the same threemd version. Publish with `cargo publish --locked` using CARGO_REGISTRY_TOKEN from the existing CRATES_IO_TOKEN secret, failing with a clear error when it is empty. Permissions stay `contents: read`. Values from the event flow through `env:`.
- Documentation: status and evidence wording only, plus the LinkedVillage example's bundle command output path (macOS /tmp is a symlink that the host deliberately refuses). docs.3md and web/docs.3md are regenerated with scripts/build-docs-3md.mjs.
- Evidence: Linux container logs and the pinned Trust log for the product tip are committed under docs/evidence/release-2.0.0/ with image tags and tool versions.
