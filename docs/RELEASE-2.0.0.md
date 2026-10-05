# ThreeMD 2.0.0 release preparation

Status: prepared and unreleased. This document describes the source and package
metadata intended for 2.0.0. It does not announce a tag, published package, VSIX,
deployment or completed Sculpt dependency adoption.

## What is included

The Swift, TypeScript and Rust libraries provide readable text and general
uncompressed binary storage, self-contained reusable-document composition,
optional stable identities, immutable revision-checked snapshots, typed atomic
patches and structured diagnostics. Hosts own file selection, storage,
permissions and other side effects. These library APIs do not perform file,
process or network I/O.

The existing raw parser, serializer and positional links remain. Compatibility
repairs preserve literal quotes, Unicode scalars and whitespace where shared
round trips exposed data loss. Canonical finite-number spelling, Unicode key
equivalence and key ordering now have shared byte fixtures.

## Versions and capabilities

| Surface | Prepared package version | Capability |
| --- | --- | --- |
| Swift `ThreeMD` and `threemd` | Future Git tag `v2.0.0` | Native library APIs; existing text CLI |
| `@corvidlabs/threemd` | `2.0.0` | TypeScript library, distributable ESM and declarations |
| Rust `threemd` | `2.0.0` | Native library APIs |
| `@corvidlabs/three-md-element` | `2.0.0` | Existing rendered text planes |
| VSCode `corvidlabs.threemd` | `2.0.0` | Existing text syntax highlighting |

The element and VSCode versions align with the release train. Their UI does not
gain binary files, composed-document expansion, stable-identity editing or a
language server. The ordinary CLI's existing commands operate on text.
`threemd-interchange` is development verification tooling, not a public
snapshot/patch server or an agent authorization service.

| Library capability | Swift | TypeScript | Rust |
| --- | --- | --- | --- |
| Existing text parser/serializer and positional links | Yes | Yes | Yes |
| General canonical text and uncompressed binary | Yes | Yes | Yes |
| Self-contained composition graph and codec | Yes | Yes | Yes |
| Identity adoption, snapshots, typed atomic patches, diagnostics | Yes | Yes | Yes |
| Optional LZFSE storage | Apple Compression backend when available | Explicit unsupported-backend error | Explicit unsupported-backend error |
| Cooperative cancellation | Task checks when concurrency is available | Synchronous AbortSignal checks | Explicit OperationOptions cancellation token |

TypeScript operations are synchronous. An AbortSignal already aborted, or an
abort visible at a cooperative check, is honored. A callback on the same event
loop cannot interrupt a synchronous call. No port promises partial results on
cancellation or unlimited work.

Package versions do not change the persisted format identifiers:

| Contract | Retained value |
| --- | --- |
| Text grammar | Frozen `1.0`; older `3md: 0.1` documents remain valid |
| General binary envelope | Version `1`, detected by `3mdbin\r\n` magic |
| General composition profile | `3md-composition-1` |
| Optional identity attribute | `3md-id`, with ordinary `id` retained as opaque metadata |

Do not replace document frontmatter with `3md: 2.0.0` to label this package
release. The parser remains lenient about the document version string; the
package number has a separate purpose.

Swift and TypeScript add no runtime package dependency. Rust pins
`unicode-normalization =0.1.25`; its serde and serde_json entries are development
dependencies. The release workflow already derives npm/crate versions from the
release tag. Swift's manifest has no library release version to change.

## Migrating an existing host

1. Keep existing raw Parser/Serializer calls when their text contract is enough.
   Their signatures and frozen grammar are retained. New bounded storage APIs
   are a separate boundary for hostile or large data.
2. Choose storage explicitly. Detect a general binary envelope by content, not
   by filename alone. Use uncompressed encoding for files that all three
   libraries must read. Handle the unsupported-backend error for LZFSE on
   platforms without the Apple backend.
3. Adopt optional `3md-id` values explicitly before using identity-based edits.
   Existing valid IDs survive adoption; invalid or duplicate namespaced IDs are
   rejected. A plane ID belongs to its document. A repeated reference ID belongs
   to its owning composition entry. Existing `id` values and positional links
   are not reinterpreted.
4. Create an immutable snapshot, then submit typed patches with that snapshot's
   exact canonical revision. Reopening equivalent canonical content yields the
   same revision. Changed content rejects a stale precondition. A revision is
   neither authentication nor permission for an agent to act.
5. Treat each patch as a transaction. Validation checks the final candidate, so
   coordinated coordinate swaps and reference changes can succeed. Missing
   targets, cycles, invalid unused graph nodes, limits, cancellation or a later
   invalid operation publish no partial snapshot.
6. Keep input-byte and work limits. A generic JSONDecoder, JSON.parse or serde
   call for snapshot/patch transport needs a caller-owned byte limit before
   allocation. Language-specific Codable/fromJSON/from_parts helpers validate
   values and revisions but do not define a shared untrusted JSON transport.
7. Review serialization assumptions. Faithful legacy quoting can change emitted
   text bytes for previously lossy string values. Canonical storage has a shared
   byte contract; ordinary legacy writer numeric spelling may differ. Compare
   imported semantics for legacy interchange, and exact bytes for canonical
   revisions and canonical outputs.

Canonical writers compare keys by NFC scalar order while keeping the original
first spelling and last assigned value from decoded text. Strict composition
JSON rejects canonically equivalent duplicate keys. Rust maps manually built
with equivalent distinct keys lack source insertion history and are rejected;
use the bounded decoder or provide NFC-unique keys.

See [editing APIs and examples](EDITING-RELEASE.md) and the
[shared interchange protocol](../conformance/interchange/PROTOCOL.md) for the
typed library workflow and verification contract.

## Sculpt adoption

Leif separately authorized using the landed work in Sculpt.3md. That app stream
must name and verify the actual dependency revision or a later published tag;
this release metadata does not establish that the app already uses 2.0.0.

Sculpt's compact voxel `.3mdb`, `ascii-composition-1` and `ascii-world-1`
schemas remain distinct from the general library container and composition
profile. A shared suffix does not make the formats interchangeable. Existing
files need legacy-reader regressions and semantic round trips before an explicit
migration is offered. They are not silently rewritten.

## Landed source and verification

The implementation chain is PR58/PR60 for the original foundation, PR61 for
Swift editing, PR62 for portable libraries and PR63 for public-API interchange.
PR63 was merged into PR62, PR62 into PR61, and Leif merged PR61 into main at
`9dfbdb649891a95f27e7590e9e6ddc72b9e58d08`. That main tree is byte-identical
to feature tip `20d1ed4f04333e18c36a50a44bf10e1b0e9b72e6`. Archived approvals
and exact implementation pins retain their real history; squash merging does
not rewrite where the evidence was collected.

Historical complete Trust and agent-review receipts are retained in
[EDITING-RELEASE.md](EDITING-RELEASE.md). The current finite interchange catalog
contains 426 requests: 82 mandatory catalog cases, 43 legacy vectors, 45 numeric
goldens and 256 seeded finite-number cases. It checks 16,983 imported outputs,
1,887 for each of the nine writer-reader pairs. It compares canonical bytes,
uncompressed envelopes, preserved semantics, identities and atomic imported
edits. Failed adapters, timeouts, oversized responses and unclassified failures
fail the development gate.

Those are meaningful finite behavioral checks, not exhaustive proof of every
IEEE754 value, arbitrary graph or language runtime. Current runtime receipts
come from macOS. Linux and Windows execution remain unverified by that receipt;
the configured complete Trust job runs on macos-15. A local Node build/runtime
check is not a permanent multi-platform CI matrix.

The repository still uses soft provenance. Existing Trust passes can report
degradation when no permitted signed attestation exists. Agent scope approval
and technical review are neither an authenticated human review nor a permitted
signature. The configured policy is unchanged, and this release preparation
does not close the signed-provenance gap.

## Before a later release

The metadata implementation at `87f7d96f9aecdf8932d285515e9786358a60e9e5`
passed the complete pinned Trust lane in 70.080 seconds: 244 Swift tests,
141 TypeScript tests, 31 Rust tests and three doctests, package typechecking/builds,
all 426 interchange cases and 16,983 imported outputs, bundle drift and editor
grammar. Forced strict SpecSync passed with zero warnings and 41/41 source
files, 11,900/11,900 lines and 269/269 core exports. Existing draft CLI/element
spec limits remain explicit. Root's scoped metadata review confirms matching
versions, preserved file-format contracts and unchanged source/workflow/policy
bytes. This is technical agent review, not independent human approval or a
permitted signature. Final closure and publication retain their own commit pins.

Focused preparation checks confirmed valid JSON manifests with matching 2.0.0
versions, Swift Package Manager manifest loading, locked offline Cargo metadata
and the crate's package file list. Scripts-disabled npm dry runs confirmed both
package versions but found no `dist/` outputs in the fresh checkout. Those dry
runs are package-content inspections, not evidence of installable built
packages. The mandatory Trust lane builds the JS library; the element build and
distribution checks remain an explicit later packaging step.

- Run the complete pinned Trust lane and strict SpecSync validation on the
  exact final preparation commit, and retain the real verification pin.
- Obtain scoped technical review with authorship stated. Preserve configured
  GitHub gates and required human review; do not invent an approval or signature.
- Establish Linux execution for the portable libraries/interchange and document
  Windows coverage or an explicit limitation. Do not relabel macOS tests as
  platform execution.
- Resolve permitted signed attestation according to the current policy, or
  record the remaining gap explicitly before any release decision.
- Build and inspect the JS ESM/declaration package, element bundle/types, Rust
  crate and VSIX. Include current metadata and intended source/artifact files.
  This slice does not rebuild or commit `element/dist/`; a later element
  packaging step must create and verify its distribution outputs.
- Confirm availability and configuration for public npm trusted publishing,
  the crates.io token, VSIX distribution and any formula-update credentials.
  No secret is inspected or copied into this preparation.
- Under a separate release instruction, create the actual `v2.0.0` tag and
  release. The existing release event can publish npm/crate packages and trigger
  an external formula update. Do not dispatch those workflows as a check.
- After publication, verify registry versions and install exact released
  packages. Swift may then use `from: "2.0.0"`, JS
  `@corvidlabs/threemd@2.0.0` and Rust `threemd@2.0.0`. Perform the separate
  Sculpt adoption checks against the chosen actual revision or tag.

Indexed partial reads, chunked storage, portable materials/timing profiles and a
full animation timeline remain future work. They are not added by this release.
