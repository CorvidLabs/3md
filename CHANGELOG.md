# Changelog

## [v2.0.0] - Unreleased

Prepared package metadata only. No 2.0.0 tag or published package is claimed.

### Library capabilities

- General readable and uncompressed binary document storage across Swift, TypeScript and Rust, with bounded decoding and deterministic canonical output.
- Self-contained reusable-document composition with validated references, shared definitions and bounded acyclic graphs.
- Optional namespaced plane and reference identities, immutable snapshots, exact canonical revisions, transactional typed patches and structured diagnostics.
- Cooperative cancellation and explicit work limits. Library APIs leave file and network access to their host.
- Public-API interchange checks across all nine writer-reader pairs, including legacy text, canonical text, uncompressed containers, composition and imported identity edits.
- Compatibility repairs for Unicode scalars, whitespace, quoted metadata and canonical numeric spelling found by cross-language round trips.

### Compatibility and release boundaries

- Package 2.0.0 retains frozen text grammar 1.0, binary container version 1 and composition profile `3md-composition-1`. Existing parser/serializer signatures and ordinary `id` attributes remain supported.
- Swift's optional LZFSE backend requires Apple Compression. TypeScript and Rust return an explicit unsupported-backend error; uncompressed storage is the portable contract.
- Rust adds the pinned `unicode-normalization =0.1.25` runtime dependency for canonical key equivalence and ordering. Swift and TypeScript introduce no runtime package dependency.
- Element and VSCode package versions align to 2.0.0. The element remains a text renderer; VSCode remains syntax highlighting only. They do not expose the new binary/composition editing APIs as UI.
- Runtime evidence currently comes from macOS. Linux/Windows execution and a permitted signed attestation remain release gaps. Finite conformance tests do not prove exhaustive parity.

See [release preparation and migration](docs/RELEASE-2.0.0.md) for capability, adoption and publication checks.

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
