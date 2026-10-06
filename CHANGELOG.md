# Changelog

## [Unreleased]

### Changed

- Linked file composition resolves each ledger reference without work or memory that grows with the containing path, in Swift, TypeScript and Rust. A repeated raw source within one file reuses its first resolution.
- A ledger edge whose `source-file` attribute cannot fit `maximumReferenceAttributeBytes` is now refused with `referenceAttributesExceeded` while it is resolved, before a later missing file or cycle. It was previously refused only after discovery.
- Rust `file_composition::resolve` reports every cancellation, including one observed while decoding an embedded bundle, validating the final graph or encoding it, as `DocumentFileCompositionError::Storage(DocumentStorageError::Cancelled)`, as for other cancellations. `code()` stays `cancelled`; code that matched `Composition(Storage(Cancelled))` should match the storage variant.
- TypeScript `DocumentFileComposition.resolve` works when called detached from the class; it no longer relies on `this`.

### Added

- Rust `editing::adopt_composition_entries`, an additive function that returns adopted entries so callers can build the graph and receive the specific composition error.
- The development interchange `files` request accepts strict optional `limits` and `documentLimits` objects, and the shared cases cover lowered limits, refusal order, path grammar, ledger escapes, cycle spellings, the cached-subtree discovery ceiling and the attribute bound in all nine writer/reader pairs.
- A Linux CI job runs the Swift, TypeScript and Rust suites and the nine-pair interchange in a `swift:6.3.3-noble` container. Windows remains unverified.

### Fixed

- The development `threemd-interchange --bundle` host adds Musl import guards (not yet compiled) and an explicit unsupported-platform error for other platforms, keeps its existing Darwin and Glibc builds, and names the path in open and publish errors.
- The Rust interchange adapter checks limit literals with correctly rounded numbers, matching Swift and TypeScript.

## [v2.0.0] - 2026-10-06

ThreeMD 2.0.0 gives the Swift, TypeScript and Rust libraries the same feature set: portable storage, self-contained composition, linked files and transactional editing. The package version is separate from the persisted formats. Text grammar 1.0, binary envelope version 1 and composition profile `3md-composition-1` are unchanged. See the [release notes and migration guide](docs/RELEASE-2.0.0.md).

Verification: the pinned Trust 1.2.2 gate passed on macOS at commit `d6eb66f`, the last source change on the release pull request, in 48 seconds. The `v2.0.0` tag is the squash merge of that pull request, with the same source; later release-branch commits change only documentation, evidence and SpecSync records. It ran 268 Swift tests, 157 TypeScript tests with typecheck and package build, 49 Rust tests plus 3 doctests, and the nine-pair interchange: 479 cases and 17,451 imports, 1,939 for each writer/reader pair. Augur returned proceed (risk 27); provenance is reported degraded (soft policy, unsigned). The log is [docs/evidence/release-2.0.0/trust-d6eb66f.log](docs/evidence/release-2.0.0/trust-d6eb66f.log).

### Added

- General readable and uncompressed binary document storage (`.3mdb`, magic `3mdbin\r\n`) in Swift, TypeScript and Rust, with bounded decoding, a corruption checksum and deterministic canonical output.
- Self-contained reusable-document composition (`3md-composition-1`) with validated references, shared definitions and bounded acyclic graphs, stored as readable text or uncompressed binary.
- Linked file composition: an ordinary document's `3md-files` metadata maps single printable ASCII glyphs to relative filenames. Each library resolves host-supplied file bytes recursively, deduplicates normalized paths, preserves identities and nested graphs, and bundles the result into the existing profile, which reopens without the source folder. See [linked file composition](docs/FILE-COMPOSITION.md) and the [LinkedVillage example](Examples/LinkedVillage/README.md).
- Optional namespaced `3md-id` plane and reference identities, explicit identity adoption, immutable snapshots, exact canonical revisions, transactional typed patches and structured diagnostics.
- Cooperative cancellation and explicit work limits in every port. Library APIs leave file and network access to their host.
- The `threemd-interchange` development gate, which drives all nine Swift/TypeScript/Rust writer/reader pairs through the public APIs, and its explicit offline `--bundle` mode for creating portable bundles from a chosen folder.

### Changed

- The JS library, web element, VS Code extension and Rust crate versions align at 2.0.0. Swift remains versioned by Git tag.
- Rust adds the pinned `unicode-normalization =0.1.25` runtime dependency for canonical key equivalence and ordering. Swift and TypeScript add no runtime package dependency.
- Faithful legacy quoting can change emitted text bytes for string values that earlier writers serialized lossily. Imported semantics are preserved.
- The npm publish jobs install `npm@^11.5.1` instead of `npm@latest`. npm 12 does not support the Node 20 those jobs use.

### Fixed

- Unicode scalar, whitespace, quoted-metadata and canonical numeric-spelling defects found by cross-language round trips.
- The `threemd` CLI writes standard error through `FileHandle.standardError`'s descriptor instead of the C `stderr` global, which Swift 6 strict concurrency rejects with Glibc on Linux. Like `fputs`, it ignores a failed write, so messages and exit codes are unchanged, including when standard error is closed (checked by comparing 39 CLI cases against main).
- `cargo-publish.yml` checks that the committed crate version matches the release tag instead of rewriting `rust/Cargo.toml`. Releases between 1.0.0 and 2.0.0 never reached crates.io, which stayed at `threemd` 1.0.0: the old workflow rewrote the version, left the tree dirty, and `cargo publish` refused. The `CRATES_IO_TOKEN` repository secret is also not configured yet. The workflow now also fails clearly when the token secret is missing and refuses to run from anything other than a release tag.

### Known limitations

- Linux execution is verified on aarch64 only, in Docker at commit `d6eb66f`: with official `swift:6.0-noble` (6.0.3) and `swift:6.3-noble` (6.3.3) images the whole Swift package builds and 262 tests pass (the Apple Compression tests compile only on Apple platforms), `rust:1.95-bookworm` passes 49 tests plus 3 doctests, `oven/bun:1.4` passes typecheck, build and 157 tests, and the nine-pair interchange passes all 479 cases. No CI job runs the library suites on Linux yet. See [docs/evidence/release-2.0.0](docs/evidence/release-2.0.0/README.md).
- x86_64 Linux is not verified: it was tried only under emulation during readiness checks, and no log is retained for this release. Windows execution is not verified.
- Provenance is soft and unsigned: Trust passes while reporting degradation because no permitted signed attestation exists. No independent human review or signature is claimed.
- The npm packages `@corvidlabs/threemd` and `@corvidlabs/three-md-element` are published by the release workflows. The release workflow publishes the `threemd` crate when the `CRATES_IO_TOKEN` repository secret is configured. The VS Code extension is not published to a marketplace; build the VSIX locally with `bun run package` in `editor/vscode`.
- Optional LZFSE compression is Swift-only through Apple Compression. TypeScript and Rust return an explicit unsupported-backend error; uncompressed storage is the portable contract.
- The `<three-md>` element remains a text renderer and the VS Code extension remains syntax highlighting only. Neither exposes binary, composition, linked-file or editing UI.
- Sculpt's adoption of 2.0.0 is a separate workstream. Its app-specific `.3mdb`, `ascii-composition-1` and `ascii-world-1` schemas are not the general container or profile.
- Cross-language agreement rests on a finite conformance catalog, not exhaustive proof for every input or runtime.
- Known follow-up, not part of 2.0.0: a separate post-release parity-hardening PR will bound per-reference path work in the resolvers, add shared interchange cases for lowered limits and cancellation, and make the development bundle host's errors name the failing path.

## [v1.0.0] - 2026-06-23

### Other

- Freeze the format at 1.0 (ff8e202)
- Fix doc drift from the verification sweep; add flagship polish (9863b7f)

## [v0.6.0] - 2026-06-23

### Other

- Add VS Code syntax-highlighting extension (editor/vscode) (9d03371)
- Add a Rust implementation; run all three impls in the verify lane (8eb9a73)
- Serve the interactive demo on GitHub Pages (3aed0b3)

## [v0.5.0] - 2026-06-23

### Other

- Add cross-plane links ([[z=N]]) in both parsers, rendered as anchors (e40038e)

## [v0.4.0] - 2026-06-23

### Other

- Render Markdown in HTML output; wire npm publish to GitHub Packages (4d4e81b)
- Add self-documenting example: 3md explained in 3md (d72dd0c)

## [v0.3.0] - 2026-06-23

### Other

- Harden parser, docs, and tooling from the multi-agent review (133d14d)
- Make web demo mobile friendly (responsive planes + touch orbit) (e17652f)
- Harden attest: signed attestations and an enforcing policy (f2ff2d7)

## [v0.2.0] - 2026-06-23

### Other

- Add HTML renderer, threemd CLI, TS package, and cross-language conformance (b9bd327)
- Fix web demo source-panel highlighting (broken @plane markup) (7937526)

## [v0.1.0] - 2026-06-23

### Other

- Fix web demo: scene z=0 fallback, scope arrow keys, honor fps (ebe937b)
- Add interactive web demo and fill in spec companions and docs (9e1ce42)
- Add 3md: Markdown with a Z axis, plus the CorvidLabs trust toolchain (46e4b57)
