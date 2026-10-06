# ThreeMD 2.0.0

Status: released on 2026-10-06 as tag `v2.0.0`. This guide holds the release
notes and migration steps. Publishing the GitHub release runs the existing
release workflows: they publish the npm packages, publish the `threemd` crate
when the `CRATES_IO_TOKEN` repository secret is configured, and update the
Homebrew formula. The VS Code extension is built locally as a VSIX and is not
published to a marketplace. Sculpt's adoption of 2.0.0 is a separate
workstream.

## What is included

The Swift, TypeScript and Rust libraries provide readable text and general
uncompressed binary storage, self-contained reusable-document composition,
linked file composition through a `3md-files` glyph ledger, optional stable
identities, immutable revision-checked snapshots, typed atomic patches and
structured diagnostics. Hosts own file selection, storage, permissions and other
side effects. These library APIs do not perform file, process or network I/O.

The existing raw parser, serializer and positional links remain. Compatibility
repairs preserve literal quotes, Unicode scalars and whitespace where shared
round trips exposed data loss. Canonical finite-number spelling, Unicode key
equivalence and key ordering now have shared byte fixtures.

### Linked file composition

An ordinary document can carry a `3md-files` metadata string: a strict JSON
object that maps single printable ASCII glyphs (U+0021 through U+007E) to
relative filenames, such as `{"1":"models/tree.3md","2":"castle.3md"}`. The
host chooses and reads files and supplies their bytes. Each library resolves
reachable references recursively, deduplicates normalized paths, and preserves
document content, identities and nested composition graphs. Invalid paths,
malformed ledgers, missing files, cycles, resource limits and cancellation are
refused without a partial result. Resolving again after a child changes
refreshes the linked graph.

Bundling writes the existing `3md-composition-1` profile as readable text or
uncompressed binary. It removes the external ledger, adds `glyph` and
`source-file` reference attributes, and reopens without the source folder.
Glyph placement and rendering belong to the host. See
[FILE-COMPOSITION.md](FILE-COMPOSITION.md),
[SPEC.md section 12.3](../SPEC.md#123-linked-file-authoring) and the
[LinkedVillage example](../Examples/LinkedVillage/README.md).

| Port | Entry point |
| --- | --- |
| Swift | `DocumentFileComposition.resolve(rootPath:sources:limits:documentLimits:)` with `DocumentFileSource(path:data:)` |
| TypeScript | `DocumentFileComposition.resolve(rootPath, sources, limits?, documentLimits?, signal?)` with `Uint8Array` data |
| Rust | `file_composition::resolve(root_path, sources, limits, document_limits, options)` |

## Versions and capabilities

| Surface | Version | Capability |
| --- | --- | --- |
| Swift `ThreeMD`, `threemd` and `threemd-interchange` | Git tag `v2.0.0` | Native library APIs; existing text CLI; development interchange and bundle tooling |
| `@corvidlabs/threemd` | `2.0.0` | TypeScript library, distributable ESM and declarations |
| Rust `threemd` | `2.0.0` | Native library APIs |
| `@corvidlabs/three-md-element` | `2.0.0` | Existing rendered text planes |
| VSCode `corvidlabs.threemd` | `2.0.0` | Existing text syntax highlighting, locally built VSIX |

The element and VSCode versions align with the release train. Their UI does not
gain binary files, composed or linked-document expansion, stable-identity
editing or a language server. The ordinary CLI's existing commands operate on
text. `threemd-interchange` is development verification tooling. Its explicit
`--bundle` mode reads a chosen folder offline and never overwrites an existing
output. It is not a public snapshot/patch server, a file watcher or an agent
authorization service.

| Library capability | Swift | TypeScript | Rust |
| --- | --- | --- | --- |
| Existing text parser/serializer and positional links | Yes | Yes | Yes |
| General canonical text and uncompressed binary | Yes | Yes | Yes |
| Self-contained composition graph and codec | Yes | Yes | Yes |
| Linked file ledger, supplied-file resolution and portable bundling | Yes | Yes | Yes |
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
| Optional linked file ledger | `3md-files` metadata string; no grammar, envelope or profile change |

Do not replace document frontmatter with `3md: 2.0.0` to label this package
release. The parser remains lenient about the document version string; the
package number has a separate purpose.

Swift and TypeScript add no runtime package dependency. Rust pins
`unicode-normalization =0.1.25`; its serde and serde_json entries are development
dependencies. The npm publish jobs set each package version from the release
tag. The crate workflow refuses to publish unless the committed crate version
equals the tag. Swift's manifest has no library release version.

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
8. Opt in to linked files explicitly. Add a `3md-files` ledger only where linked
   authoring is wanted. The host selects and reads files, passes their bytes as
   supplied sources and handles refusals. Share a bundle, not a folder: the
   bundled profile imports in every port without the source files. Documents
   without a ledger are unaffected, and no existing file is rewritten.

Canonical writers compare keys by NFC scalar order while keeping the original
first spelling and last assigned value from decoded text. Strict composition
JSON rejects canonically equivalent duplicate keys. Rust maps manually built
with equivalent distinct keys lack source insertion history and are rejected;
use the bounded decoder or provide NFC-unique keys.

See [editing APIs and examples](EDITING-RELEASE.md) and the
[shared interchange protocol](../conformance/interchange/PROTOCOL.md) for the
typed library workflow and verification contract.

## Sculpt adoption

Sculpt's adoption of the released library is a separate app workstream. It must
name and verify the actual dependency revision or tag it uses; this release does
not establish that the app already uses 2.0.0.

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
to feature tip `20d1ed4f04333e18c36a50a44bf10e1b0e9b72e6`. PR64 prepared the
2.0.0 package metadata and this guide at
`be41af523aecf041202a06d4c83471b19e09b275`. PR65 added linked file composition
at `e424fc5b20b16c657dd00c47415de833e25cf7af`, PR66 landed its review
corrections at `9ac2454dfec51a9d575a030236f046462059f847`, and PR68 finalized
its SpecSync change at `87edafb2f47b4d73e47441ae754ad955b6d49f44`. Archived
approvals and exact implementation pins retain their real history; squash
merging does not rewrite where the evidence was collected.

Commit `d6eb66f23641e2f7fb7e7dc6ea6dd8e324bd17f6` on the release pull request carries the last product
changes after `87edafb`. The `threemd` CLI writes standard error through
`FileHandle.standardError`'s descriptor instead of the C `stderr` global, which
Swift 6 strict concurrency rejects with Glibc on Linux. Like `fputs`, it ignores
a failed write, so messages and exit codes are unchanged; 39 CLI cases,
including closed standard error and a broken pipe, match main exactly. The npm
publish jobs pin their npm upgrade to `npm@^11.5.1`, and the crate workflow
checks the committed version against a tag ref instead of rewriting it. Later
release-branch commits change only documentation, evidence and SpecSync
records. The repository merges by squash, so the `v2.0.0` tag is the squash
merge of that pull request: a different commit with the same source.

The pinned Trust 1.2.2 gate passed on `d6eb66f` on macOS in 48 seconds,
with Fledge 1.7.2: 268 Swift tests, 157 TypeScript tests with typecheck and
package build, 49 Rust tests plus 3 doctests, strict Clippy, editor grammar and
element bundle drift. The public-API interchange gate ran 479 cases: 82 catalog
sources, 43 legacy JSON sources, 45 fixed numbers, 256 seeded finite-number
samples and 53 linked-file requests. It checked 17,451 imported outputs, 1,939
for each of the nine writer/reader pairs, comparing canonical bytes,
uncompressed envelopes, preserved semantics, identities, atomic imported edits
and source-free bundle imports. Augur returned proceed (risk 27). Provenance is
reported degraded under the soft policy because no permitted signature exists.
The log is [evidence/release-2.0.0/trust-d6eb66f.log](evidence/release-2.0.0/trust-d6eb66f.log).
Linked-file implementation receipts are in
[evidence/file-composition](evidence/file-composition/README.md); earlier
receipts remain in [EDITING-RELEASE.md](EDITING-RELEASE.md).

Agent source reviews found and repaired defects before PR66 landed. Claude's
final scoped source review of the corrections passed; its unmodified receipt is
`evidence/file-composition/claude-protocol-final-review-receipt.json`. Agent
reviews are technical records, not human implementation approval, a GitHub
approval or a signature.

## Known limits

- These are finite behavioral checks, not exhaustive proof of every IEEE754
  value, arbitrary graph or language runtime.
- The release Trust receipt comes from macOS, and the configured complete Trust
  job in CI runs on macos-15.
- Linux execution is verified on aarch64 only, in Docker at commit `d6eb66f`. With official `swift:6.0-noble` (6.0.3) and `swift:6.3-noble`
  (6.3.3) images the whole Swift package builds and 262 tests pass; the Apple
  Compression tests compile only on Apple platforms. `rust:1.95-bookworm` passes
  49 tests plus 3 doctests, `oven/bun:1.4` passes typecheck, build and 157
  tests, and the nine-pair interchange passes all 479 cases and 17,451 imports.
  No CI job runs the library suites on Linux yet. Logs and scripts are in
  [evidence/release-2.0.0](evidence/release-2.0.0/README.md).
- x86_64 Linux is not verified: it was tried only under emulation during
  readiness checks, and no log is retained for this release.
- Windows execution is not verified.
- The repository uses soft provenance. Trust passes while reporting degradation
  because no permitted signed attestation exists. Agent scope approval and
  technical review are neither an authenticated human review nor a permitted
  signature. The configured policy is unchanged, and this release does not close
  the signed-provenance gap.
- Optional LZFSE storage is Swift-only through Apple Compression. TypeScript and
  Rust report an explicit unsupported-backend error; mandatory cross-language
  interchange uses uncompressed storage.
- The `<three-md>` element remains a text renderer and the VSCode extension
  remains syntax highlighting only.
- The development bundle host refuses symlinks, FIFOs and existing outputs, but
  does not promise protection against malicious concurrent same-user renames on
  Darwin.
- Sculpt adoption is separate, and existing Sculpt files are not rewritten.

## Known follow-up

A separate post-release parity-hardening PR will bound per-reference path work
in the resolvers, add shared interchange cases for lowered limits and
cancellation, and make the development bundle host's errors name the failing
path. None of this is part of 2.0.0.

## Publication

The `v2.0.0` GitHub release starts the existing workflows:

- `publish.yml` publishes `@corvidlabs/threemd` and
  `@corvidlabs/three-md-element` to npm through trusted publishing.
- `cargo-publish.yml` publishes the `threemd` crate when the `CRATES_IO_TOKEN`
  repository secret is configured, and fails with a clear error when it is not.
  Releases between 1.0.0 and 2.0.0 never reached crates.io, which stayed at
  `threemd` 1.0.0: the old workflow rewrote the crate version, left the tree
  dirty, and `cargo publish` refused. This release checks the committed version
  instead. The `CRATES_IO_TOKEN` secret is not configured yet; once it is,
  re-running the failed `cargo-publish` job for `v2.0.0` publishes the crate.
- `post-release-formula.yml` updates the Homebrew formula.

The VS Code extension is not published to a marketplace. Build the VSIX locally
with `bun run package` in `editor/vscode`.

Pin the release with the lines below. Confirm that npm and crates.io list
2.0.0 before pinning those packages.

- Swift: `.package(url: "https://github.com/CorvidLabs/3md", from: "2.0.0")`
- TypeScript: `bun add @corvidlabs/threemd@2.0.0`
- Rust: `cargo add threemd@2.0.0`

Indexed partial reads, chunked storage, remote or watched linked files, portable
materials/timing profiles and a full animation timeline remain future work. They
are not part of this release.
