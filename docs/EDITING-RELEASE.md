# ThreeMD editing release

Status: released in ThreeMD 2.0.0 on 2026-10-06. Release notes, migration guidance and current verification are in [RELEASE-2.0.0.md](RELEASE-2.0.0.md); historical implementation receipts below retain their original commits.

## Release scope

The package release is 2.0.0. The package version, frozen 1.0 text grammar, binary container version 1 and composition profile version `3md-composition-1` are separate contracts. Existing documents and parser/serializer signatures stay supported.

The release combines the binary/composition foundation in PR58 with stable identities, typed document/composition patches and structured diagnostics in PR61, portable TypeScript/Rust implementations in PR62 and public-API interchange in PR63. PR63 landed in PR62, PR62 landed in PR61, and Leif merged PR61 into main at `9dfbdb649891a95f27e7590e9e6ddc72b9e58d08`. The landed tree is byte-identical to feature tip `20d1ed4f04333e18c36a50a44bf10e1b0e9b72e6`. Existing archive records are preserved and do not pretend that feature evidence was originally collected on the squash commit. PR64 prepared the 2.0.0 package metadata at `be41af523aecf041202a06d4c83471b19e09b275`, PR65 added linked file composition at `e424fc5b20b16c657dd00c47415de833e25cf7af`, PR66 landed its review corrections at `9ac2454dfec51a9d575a030236f046462059f847` and PR68 finalized its SpecSync change at `87edafb2f47b4d73e47441ae754ad955b6d49f44`. Release pull request commit `d6eb66f23641e2f7fb7e7dc6ea6dd8e324bd17f6` adds the Linux CLI build fix and the pinned publish workflows; the `v2.0.0` tag is the squash merge of that pull request, with the same source.

## Capability matrix

| Capability | Swift | TypeScript | Rust |
| --- | --- | --- | --- |
| Existing 1.0 text parsing and serialization | Existing shared conformance | Existing shared conformance | Existing shared conformance |
| General uncompressed binary container | Released in 2.0.0 | Released in 2.0.0 | Released in 2.0.0 |
| Apple LZFSE binary compression | Conditional Apple backend | Explicit compressionUnavailable | Explicit compressionUnavailable |
| Self-contained composition graph/codec | Released in 2.0.0 | Released in 2.0.0 | Released in 2.0.0 |
| Linked file ledger, resolution and bundling | Released in 2.0.0 | Released in 2.0.0 | Released in 2.0.0 |
| Identity-aware snapshots, patches and diagnostics | Released in 2.0.0 | Released in 2.0.0 | Released in 2.0.0 |
| Structured document payload, kind 2, from `.binary` | Released in 2.1.0 | Released in 2.1.0 | Released in 2.1.0 |
| `encodeTextContainer` (kind 1) and header-only `containerInfo` | Released in 2.1.0 | Released in 2.1.0 | Released in 2.1.0 |

The 2.1 rows are on main. Pull request 73 removed the fixed storage size stop. CLI binary input, `convert` and `inspect` are follow-ups. See [RELEASE-2.1.0.md](RELEASE-2.1.0.md).

Uncompressed storage is the portable baseline. Unsupported compression is an explicit failure. Shared extension fixtures independently check exact canonical document/profile/envelope bytes, finite-number formatting, Unicode key ordering, identity adoption, revision guards, atomic edits and diagnostic codes/paths in all three libraries. These are separate from the unchanged legacy parser vectors. Leif explicitly authorized TypeScript and Rust implementation in this follow-up; Sculpt remains Swift-only.

TypeScript copies and freezes snapshot values and accepts an optional AbortSignal. Rust snapshots and compositions expose immutable accessors; operations take explicit OperationOptions with an optional cloneable CancellationToken. Swift continues its task cancellation checks where concurrency is available. Cancellation is cooperative during bounded work and never yields a partial published result.

New canonical storage uses Swift-compatible finite-number spelling and NFC scalar key comparison while preserving original key spelling. Text decoding retains the first spelling and last assigned value of canonically equivalent metadata/attribute keys. Strict composition JSON rejects equivalent duplicate keys. Rust direct BTreeMap values containing equivalent distinct spellings are ambiguous without insertion history and are rejected; use the bounded decoder or supply NFC-unique keys. Rust pins unicode-normalization 0.1.25 for this comparison. The portable follow-up originally retained legacy parser bodies. The interchange follow-up repairs Unicode whitespace/source-key interpretation and scalar quoting where round trips revealed data loss. Parser signatures and frozen syntax remain. Legacy numeric spelling may differ, but reimport must preserve semantics. Signed zero normalizes to zero under the existing canonical wire contract.

## Cross-language file interchange

The `verify` lane now requires JavaScript typechecking, distributable JavaScript/declaration builds and a Node public-package runtime check. `swift run threemd-interchange` drives all nine Swift/TypeScript/Rust writer-reader pairs after JavaScript and Rust adapters are built. The mandatory [catalog](../conformance/interchange/README.md) covers fixed wire goldens, legacy vectors, Unicode/quoting and generated finite coordinates, composition graphs, imported identity edits and rejected hostile inputs. The development JSON-lines protocol is not a public snapshot/patch interchange format.

This gate establishes passing declared cases at the tested commit. It does not prove every possible input, all operating systems or optional Apple LZFSE support in the other ports. Swift rendering helpers, idiomatic coding surfaces and browser viewer features remain separate capabilities. Direct Rust maps with ambiguous Unicode-equivalent keys remain an explicit validation error; source decoding has portable reconstruction semantics.

## Stable identities

Use the optional `3md-id` plane attribute to identify a plane independently of its position. Ordinary `id` attributes remain application metadata. Parsing never invents IDs. Explicit adoption preserves valid existing identities and assigns only missing identities. Repeated composition references carry their own `3md-id` within the owning entry, while definition IDs keep their existing meaning.

```3md
---
3md: 1.0
axis: layer
title: Design notebook
---
@plane z=0 label="Inbox" 3md-id="inbox"
# Inbox

@plane z=1 label="Ideas" 3md-id="ideas"
# Ideas
```

Moving Ideas to another position keeps its identity. Existing `[[z=N]]` links and HTML anchors retain their current semantics; editing does not silently rewrite Markdown links. Identity interpretation is an optional editing-layer convention above the unchanged parser.

## Transactional editing

Document and composition snapshots are immutable Sendable values. A typed patch includes its expected revision and ordered operations. Revision comparison uses exact canonical content, not a short hash or a process-local counter, and is a concurrency precondition rather than author authentication.

The editor applies operations to a private candidate and validates the final value before publishing a new snapshot. This permits coordinated position swaps or reference updates while refusing duplicate final positions, invalid IDs, missing targets and invalid final graphs. Operation counts, payload work and diagnostic collection are bounded. Cancellation, stale revisions or a later failing operation return no partial result.

Diagnostics carry stable codes, severity, explanatory text and available line/path evidence. Value-only diagnostics do not invent source line numbers. IDs remain stable when bodies, labels, positions, order or reference targets change.

Inspection covers source/storage validity, identities, positions and graph values. It does not invoke the existing Markdown link extractor or automatically report dangling links. Existing `links()` behavior remains available separately. Codable snapshots and patches are typed transport values, not a bounded streaming JSON decoder; a host accepting untrusted wire input must limit its bytes before Foundation decoding.

```swift
let identified = try DocumentIdentity.adopt(document)
let snapshot = try DocumentSnapshot(identified)
let patch = DocumentPatch(
    expectedRevision: snapshot.revision,
    operations: [.move(id: "ideas", to: 0)]
)
let updated = try DocumentEditor.apply(patch, to: snapshot)
```

The example assumes the Ideas plane already carries `3md-id="ideas"`. Adoption of an unnamed plane assigns a deterministic `plane-N` ID instead of deriving identity from its label.

The TypeScript root exports the analogous classes, using `Uint8Array` for storage and `kind` for typed operations:

```typescript
const bytes = DocumentStorageCodec.encode(document,
  DocumentStorageFormat.binary(DocumentCompression.None));
const snapshot = new DocumentSnapshot(DocumentIdentity.adopt(document));
const updated = DocumentEditor.apply({
  expectedRevision: snapshot.revision,
  operations: [{ kind: "move", id: "ideas", to: 0 }],
}, snapshot);
```

Rust exposes `storage`, `composition`, `editing` and `diagnostics` modules. `storage::encode/decode` take explicit policies and `OperationOptions`; `editing::adopt_document`, `DocumentSnapshot::new` and `editing::apply_document_patch` provide the same staged workflow. Snapshots expose `document()/composition()/revision()` accessors. Rust `from_parts` and TypeScript `fromJSON` reject altered source/revision pairs. Typed transport helpers do not replace a bounded untrusted-wire reader: hosts limit input bytes before generic JSON decoding.

## Sculpt integration boundary

Before 2.0.0, Sculpt's shared-model editing used its existing validated sculpture/reference values and ThreeMD 1.8.1. Adoption of the released library is a separately implemented and verified app stream; this library release does not establish its completion. Sculpt's voxel `.3mdb`, `ascii-composition-1` and `ascii-world-1` schemas remain app-specific. The general binary container is a different discriminated format; identical filename suffixes do not make these payloads interchangeable.

Dependency adoption and explicit file migration require semantic equivalence and legacy-reader regression checks. Existing files are not rewritten automatically. Any temporary source pin must name an actual verified upstream commit; a release pin requires the corresponding tag to exist. App-specific storage is not silently relabeled as the generic container.

## Release checklist

- Done: all three libraries' semantic tests and shared extension fixtures pass with the existing text conformance unchanged.
- Done: the pinned Trust 1.2.2 gate passed on macOS at commit `d6eb66f`. Counts are in [RELEASE-2.0.0.md](RELEASE-2.0.0.md#landed-source-and-verification).
- Done: cross-platform unsupported-compression behavior is explicit and the capability matrix is published.
- Done: scoped agent reviews are recorded under their actual reviewer identities, and the unsigned provenance limitation is preserved under the existing policy.
- Done: the storage/composition, editing, portable-library, interchange, metadata and linked-file scopes are finalized through SpecSync with their implementation evidence archived.
- Open: Windows and x86_64 Linux execution and a permitted signed attestation. Linux status is recorded under the known limits in [RELEASE-2.0.0.md](RELEASE-2.0.0.md#known-limits).
- Release: the `v2.0.0` tag and GitHub release follow Leif's direct "Finish 2.0.0" instruction of 2026-10-06. The release workflows publish the npm packages, and publish the Rust crate when the `CRATES_IO_TOKEN` repository secret is configured. The VSIX is built locally and is not published to a marketplace.

Indexed partial reads, portable material/timing profiles and a full animation timeline are later milestones. They are not part of 2.0.0.

## Prepared implementation evidence

Product tip `0018a3c96d849ffb5966a9dd270b43b7d63541a6` passed the pinned complete Trust lane: 222 Swift tests, 79 JavaScript tests, Rust conformance/doc tests, element drift and editor grammar. Forced strict SpecSync covers all 28 files and 200 ThreeMD exports with zero warnings. Scoped agent review passed after a diagnostic-budget ordering correction. The existing soft provenance policy reports degradation without a permitted signature; neither a human implementation approval nor a release is claimed.

That receipt is PR61's historical Swift-first implementation. Portable follow-up source tip `1770d075b2a3ec0491d6a1d4776b4ba908cf1480` passed the complete pinned Trust lane: 232 Swift tests, 133 TypeScript tests and type checking, Rust's 13 extension tests, eight editing tests, legacy conformance test and three doctests, strict Clippy, element drift and editor grammar. Subsequent forced strict SpecSync validation includes the new TypeScript/Rust coverage roots: all three specs passed with zero warnings, 267 documented ThreeMD exports, 38/38 files and 10763/10763 lines. The CLI and element specs retain their existing draft validation limits.

Actual scoped agent review passed after reproducing Unicode key equivalence/order, NaN diagnostic classification, forged TypeScript policy objects, large-number canonical formatting and quadratic whitespace trimming; the ports carry focused regressions. Trust passed with the unchanged soft provenance degradation, not a permitted signature or independent human approval. Only the derived web bundle is refreshed with unchanged element source and the existing drift gate. Its parser helper retains behavior with bounded linear trimming, and new root exports change deterministic minifier allocation. Element/dist is untouched. This does not add a hosted binary/composition editor.

A separate deterministic probe compares 100,000 finite IEEE754 samples from Swift with each port's actual storage output; both repaired writers have zero mismatches. This is additional sampled evidence, not exhaustive proof over all floating-point values. The TypeScript whitespace probe uses nine-sample medians: bounded decoding is 0.076 ms at 4,000 spaces, 0.142 ms at 16,000 and 6.510 ms at 1,000,000. Those local measurements qualify the regression repair, not a runtime latency guarantee. Semantic tests separately preserve interior spaces/tabs and verify text/binary round trips.

The interchange follow-up's complete pinned Trust lane passed at source
`55efdaab7efd2a12e78f3602af35c7e7b08322c0`: 244 Swift tests, 141 TypeScript
tests, 31 Rust tests and three doctests, required package typechecking/build,
bundle drift and editor grammar. Its 426-case public-API matrix passes all nine
producer/consumer pairs with 16,983 imported outputs. The final catalog guard at
`6b6be79eeda12b7ff20b5a06b2c2470a94de0eee` also passes that matrix and the
bounded protocol/watchdog regressions. Three actual agent reviews found and
closed scalar Unicode, exact-key comparison and supervision defects. Reviewers
state their implementation/fixture authorship and complementary peer coverage;
these are technical agent records, not human approval or permitted signatures.
The new scope's official verification, finalization and publication retain their
own exact commit records. Historical receipts remain unchanged.

## Linked authoring and portable bundling

2.0.0 includes a host-supplied file ledger in all three ports, defined by [FILE-COMPOSITION.md](FILE-COMPOSITION.md). The libraries resolve explicit bytes, not disk paths. An ordinary document can map `1` and `2` to child filenames without a separate module registry. Re-resolving after child edits refreshes the linked graph; bundling embeds shared definitions once in the existing composition profile and removes the external ledger. The bundle then needs no source folder.

```swift
let linked = try DocumentFileComposition.resolve(
    rootPath: "scene.3md",
    sources: [DocumentFileSource(path: "scene.3md", data: parentBytes),
              DocumentFileSource(path: "models/tree.3md", data: treeBytes)]
)
let portable = try DocumentCompositionCodec.encode(linked.composition)
```

TypeScript uses `DocumentFileComposition.resolve(rootPath, sources)` with Uint8Array bytes and optional policies/AbortSignal. Rust uses `file_composition::resolve(root_path, sources, composition_limits, document_limits, options)`. All preserve generic Markdown and axes; placement/rendering remains the host's responsibility. See [LinkedVillage](../Examples/LinkedVillage/README.md) for nested and repeated file examples and the explicit development bundle command. Apple LZFSE remains optional; mandatory cross-language binary is uncompressed.

This additive authoring contract does not implement remote fetching, filesystem watchers, automatic user-file migration or arbitrary spatial rendering in Sculpt. Native app insertion is a separate bounded feature.
