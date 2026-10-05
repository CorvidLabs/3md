# 3md

## Current merge request

Leif directly instructed "merge al the prs" on 2026-10-04 after reviewing the binary/composition implementation. This authorizes repairing the reviewed decimal-decoding resource issue, verifying the resulting feature head, completing truthful delegated lifecycle records, and merging the related open PRs through the configured GitHub rules. The actor remains the actual executing agent; no record claims an independent human review, a different agent identity, or an unavailable signature. Existing Trust risk and provenance policy stays unchanged. Main pushes, releases, deployments and changes to branch protections are outside this request.

Markdown with a Z axis. See [README.md](README.md) for the pitch and
[SPEC.md](SPEC.md) for the format definition. The implementation is the
`ThreeMD` Swift package.

## Project map

- `Sources/ThreeMD/` - the parser and serializer library.
- `Tests/ThreeMDTests/` - XCTest suite.
- `Examples/` - sample `.3md` documents.
- `specs/ThreeMD/` - the spec-sync contract for the library.
- `SPEC.md` - the authoritative format specification.

## Conventions

CorvidLabs Swift conventions apply: explicit access control, K&R braces, no
force unwrap, async/await only, Sendable across concurrency boundaries,
descriptive generic names, 4-space indentation, 120-column lines. The formatter
config in `.swift-format` enforces the mechanical parts.

## Binary and composition scope

Use SpecSync 6.0.0 for all lifecycle writers. The local binary is
`/Users/leif/.cargo/bin/specsync`; the development Fledge pin is 1.7.2 at
`/opt/homebrew/bin/fledge`. CI verifies the release checksums and pins Trust
1.2.2 to `bccd89c111d47778c97c5064fb62ab51695e04ea`.

Check the plugin's actual version. Fledge's installed plugin registry can take
priority over PATH; when it resolves an older Trust, invoke the isolated
`fledge-trust` 1.2.2 binary directly with the pinned Fledge on PATH. Do not
change the global plugin installation merely to run this checkout's gate.

The current scope adds general binary Document storage and self-contained
named Document references. Preserve the existing 1.0 text grammar, version
leniency, parser/serializer APIs, and cross-language text conformance. New
feature code in the original foundation scope was Swift-only. The portable
follow-up below supersedes that implementation-language limit. Portable
uncompressed storage is required and Apple LZFSE is an optional conditional
backend. Named references never perform
implicit filesystem or network reads. Voxel expansion and rendering are
application semantics, not ThreeMD behavior.

Leif directly approved this defined scope and full SpecSync 6 SDD. The actor
recording that definition is `agent:sculpture_exports`, acting under Leif's
direct authorization. The record does not claim Leif reviewed an implementation
diff and is not independent human review. Actual tests, implementation review,
signature/provenance and lifecycle completion remain separately evidenced.
Preserve the existing Attest trusted keys and reviewer identity restrictions;
do not identify another agent as `agent:claude` or invent signer evidence.

Root coordinates exact implementation commits, verification and authorized
feature-branch pull requests. A scope approval does not authorize an unreviewed
merge, tag, release, deployment or repository visibility change. Do not run the
shared verification lane concurrently with the coordinator.

## Portable editing release preparation

On 2026-10-05 Leif explicitly requested updating every language supported by
ThreeMD, not only Swift. The approved follow-up brings the uncompressed binary
container, self-contained composition, stable identities, exact revisions,
atomic edits and structured diagnostics to TypeScript and Rust. Shared
extension fixtures verify all three libraries alongside unchanged legacy
text conformance. TypeScript and Rust report unsupported LZFSE explicitly.
Rust pins unicode-normalization 0.1.25 for canonical key equivalence.

Use SpecSync 6 for the new scope only and preserve historical archives.
Source coverage includes Sources, js/src and rust/src. The derived web bundle
must pass the existing drift gate; do not build or commit element/dist.
Actual agent review is not independent human approval or a permitted signature.
Retain the existing provenance policy and report unsigned degradation honestly.

Leif will merge the prepared PRs. This work does not merge them, push main,
publish a version, tag a release or deploy. Sculpt remains Swift-only with
ThreeMD 1.8.1 until separately verified dependency adoption is authorized.

## Mandatory file interchange

Leif directly requested that all supported languages import/export each other's
files. The new SpecSync 6 scope requires a Swift development coordinator driving
the public Swift, built TypeScript package in Node, and Rust adapters. Every
catalog case and all nine writer/reader pairs are mandatory for canonical text,
portable uncompressed binary and self-contained composition. Identity adoption,
imported edits and exact revisions are tested on those same files. Existing
signed-zero normalization remains explicit. LZFSE is still optional Apple-only.

Repair confirmed Unicode trimming, source-key reconstruction and scalar quoting
defects without changing the frozen grammar or parser signatures. Orchestration
is Swift; test adapters use the library language. The coordinator may start
development processes; the ThreeMD library remains pure without file/network
I/O or process execution. Run the complete lane once through root, including
JavaScript typechecking/declaration build and Node runtime interchange. Preserve
archives, old conformance fixtures, signer policies and element/dist. This scope
does not authorize merging, releasing, pushing main or a Sculpt dependency bump.

## Current 2.0.0 release preparation authority

On 2026-10-05 Leif directly requested: "Ok can we merge all the PRs and prep 2.0.0? Also can we use all this in sculpt.3md and continue working on sculpt". Root coordinates GitHub merges and the separately verified Sculpt adoption. Earlier notes that Leif would merge later or Sculpt must remain on 1.8.1 describe the earlier scope and do not block this new request.

Root reports the combined feature tree landed through PR61 at main commit `9dfbdb649891a95f27e7590e9e6ddc72b9e58d08`, byte-identical to feature tip `20d1ed4f04333e18c36a50a44bf10e1b0e9b72e6`. Historical approvals and verification pins stay unchanged.

The release-preparation agent owns synchronized 2.0.0 manifests, the Rust root lock version and honest release/capability/migration prose under a new SpecSync 6 definition. Its actor is `agent:codex-threemd-editing`, acting under Leif's direct preparation authority. Agent definition approval is not a claim that Leif reviewed the diff, an independent human review or a permitted signature. Canonical behavior, public APIs, source, fixtures, dependency versions, release workflows, policies, old archives, the managed block and `element/dist/` stay unchanged in this metadata slice. Root owns the complete pinned Trust lane and lifecycle closing.

This request authorizes preparation and configured-gate merges, not a tag, package publication, release, deployment, changed protections, policy weakening or invented signed provenance. Linux/Windows runtime parity and permitted signed attestation remain explicit release gaps. Uncompressed interchange is portable; optional LZFSE stays Swift/Apple only. Sculpt keeps its app-specific legacy schemas unless a separately verified explicit migration is implemented.

<!-- CorvidLabs trust toolchain: BEGIN (managed, do not edit inside) -->
## CorvidLabs trust toolchain

This repository uses one trust gate. Every session must use it and must not bypass or weaken it.

- Run `fledge trust verify` before calling a change complete.
- Keep module specs synchronized with implementation changes.
- Treat an Augur block verdict as a hard stop that must be surfaced and de-risked.
- Record and verify provenance with Attest after the repository's verification lane passes.
- Keep generated trust configuration and this managed block in place.

<!-- CorvidLabs trust toolchain: END -->
