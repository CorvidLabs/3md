# ThreeMD editing release preparation

Status: unreleased feature preparation. Leif will merge the prepared PRs. No tag, package publication or deployment is part of this work.

## Release scope

The proposed next compatible library release is 1.9.0, subject to the final API compatibility audit. The package version, frozen 1.0 text grammar, binary container version and composition profile version are separate contracts. Existing documents and source APIs stay supported.

The release combines the binary/composition foundation in PR58 with additive stable identities, typed document/composition patches and structured diagnostics. The editing PR is stacked on PR58 and should follow it in the merge order. PR60's historical evidence repair is an independent documentation/lifecycle change. Existing archive records are preserved.

## Capability matrix

| Capability | Swift | TypeScript | Rust |
| --- | --- | --- | --- |
| Existing 1.0 text parsing and serialization | Existing shared conformance | Existing shared conformance | Existing shared conformance |
| General uncompressed binary container | PR58, unreleased | Not implemented | Not implemented |
| Apple LZFSE binary compression | PR58, conditional Apple backend | Not implemented | Not implemented |
| Self-contained composition graph/codec | PR58, unreleased | Not implemented | Not implemented |
| Identity-aware snapshots, patches and diagnostics | This preparation, unreleased | Not implemented | Not implemented |

Uncompressed storage is the portable baseline. Unsupported compression is an explicit failure. Text compatibility tests for the other readers do not establish binary, composition or editing feature parity. The existing JavaScript/Rust checks remain in the complete verification lane; authored implementation for this slice is Swift only.

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

## Sculpt integration boundary

Sculpt's shared-model editing uses its existing validated sculpture/reference values and ThreeMD 1.8.1 until a separately verified upstream version is published. Its current voxel `.3mdb`, `ascii-composition-1` and `ascii-world-1` schemas remain app-specific. The general binary container is a different discriminated format; identical filename suffixes do not make these payloads interchangeable.

After publication, dependency adoption and explicit file migration require semantic equivalence and legacy-reader regression checks. Existing files are not rewritten automatically. Current Sculpt PRs do not use an untagged dependency or claim support for the new generic container.

## Release checklist

- Complete the new feature's Swift semantic tests and existing text conformance unchanged.
- Run the pinned complete Trust lane and forced strict SpecSync validation on the actual product tip.
- Verify cross-platform unsupported-compression behavior and publish the capability matrix.
- Record scoped agent review accurately and preserve the unsigned provenance limitation under the existing policy.
- Finalize only the new feature scope and retain its implementation evidence through publication.
- Merge PR58 before the stacked editing PR, reconcile the resulting tree, and repeat required exact-tip release checks.
- Publish a version/tag only under a later direct release instruction from Leif.

Indexed partial reads, portable material/timing profiles and a full animation timeline are later milestones. They are not promised by this release preparation.
