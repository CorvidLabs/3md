# Proposed upstream 3md storage and composition support

Historical assessment of the 1.8.1-era proposal. The checkout now pins ThreeMD 2.0.0, and the first Sculpt release waits for a tagged 2.1.0. See [dependencies](dependencies.md), [portable adoption](3md-2-adoption.md), and [distribution](distribution.md). The earlier observations remain unchanged as historical evidence.

Status: assessment and API proposal only. No upstream source, dependency pin, format, release, or publication was changed. This assessment performed read-only source inspection; it did not run builds, tests, tool gates, fetches, or other Git commands.

## Verified dependency and local evidence

Rook's [Package.swift](/Users/leif/Development/_CorvidLabs/rook/Package.swift:17) selects `https://github.com/CorvidLabs/3md`, exactly `1.8.1`. Its [Package.resolved](/Users/leif/Development/_CorvidLabs/rook/Package.resolved:5) pins revision `45db1352c926ab82d02dbf8583e4d610d34061f8`.

The sibling checkout is `/Users/leif/Development/_CorvidLabs/3md`. Its configured origin is `https://github.com/CorvidLabs/3md.git`. Its local `HEAD` points to `refs/heads/main`, whose file contains `2a145766b9ecb83d96ee15aa453a65cc2125571f`. This is a local ref, not a verified statement about live GitHub main. The checkout's cleanliness was not assessed. Direct byte comparisons found its `Sources/ThreeMD/Parser.swift` and `Document.swift` identical to Rook's pinned copies under `.build/checkouts/3md`.

Relevant upstream contracts:

- [AGENTS.md](/Users/leif/Development/_CorvidLabs/3md/AGENTS.md): Swift conventions and the required trust tools.
- [SPEC.md](/Users/leif/Development/_CorvidLabs/3md/SPEC.md:12): arbitrary nonempty version strings remain accepted by the existing text parser.
- [SPEC.md](/Users/leif/Development/_CorvidLabs/3md/SPEC.md:73): flat string frontmatter, last-wins duplicate keys, and no YAML nesting or aliases.
- [SPEC.md](/Users/leif/Development/_CorvidLabs/3md/SPEC.md:261): the frozen 1.0 text grammar and shared cross-language conformance contract.
- [SPEC.md](/Users/leif/Development/_CorvidLabs/3md/SPEC.md:281): transclusion across documents and binary/compressed containers are already identified as future work.
- [ThreeMD.spec.md](/Users/leif/Development/_CorvidLabs/3md/specs/ThreeMD/ThreeMD.spec.md:35): Swift, TypeScript, and Rust currently share text-parser semantics.

## What belongs in the library

The existing portable library represents general Markdown documents along a free axis. `Document`, `Plane`, `Axis`, `Parser`, and `Serializer` are value types with `Sendable` conformance. Metadata and plane attributes are strings; plane positions are finite numbers when produced by the text parser. The library currently has no package dependencies.

Rook has two useful implementation precedents, both explicitly app-specific:

- [SculptureBinaryCodec.swift](/Users/leif/Development/_CorvidLabs/rook/Sources/RookSculpture/SculptureBinaryCodec.swift:5) stores voxel dimensions, an ASCII title, compressed voxel bytes, and a SHA256 checksum. Its `3MDB` version-1 header and Apple LZFSE stream do not encode an arbitrary `ThreeMD.Document`.
- [SculptureComposition.swift](/Users/leif/Development/_CorvidLabs/rook/Sources/RookSculpture/SculptureComposition.swift:96) validates a self-contained graph, shares named definitions, detects cycles, and bounds depth, placements, and resolved volume. [SculptureCompositionCodec.swift](/Users/leif/Development/_CorvidLabs/rook/Sources/RookSculpture/SculptureCompositionCodec.swift:4) expresses that graph through the `ascii-composition-1` profile over existing 3md text.

Generalize bounded storage and named document references. Keep voxel palettes, 256-cell dimensions, ASCII tile bindings, quarter-turn geometry, child fitting, sparse-world anchors, mesh extraction, and rendering in Rook. A generic document library must also work for time, frame, layer, depth, and custom axes.

## First implementation slice: generic binary document storage

Add a versioned binary envelope for one general 3md document, with additive APIs tentatively named:

```swift
public enum DocumentStorageFormat: Sendable {
    case text
    case binary(compression: DocumentCompression)
}

public enum DocumentCompression: Sendable {
    case none
    case lzfse
}

public struct DocumentDecodeLimits: Sendable { /* Explicit bounded policy. */ }

public enum DocumentStorageCodec {
    public static func decode(
        _ data: Data, limits: DocumentDecodeLimits
    ) throws -> Document

    public static func encode(
        _ document: Document, format: DocumentStorageFormat,
        limits: DocumentDecodeLimits
    ) throws -> Data
}
```

Names and signatures require an upstream API review; they are not available today. Keep `Parser.parse(_:)` and `Serializer.render(_:)` source-compatible. A new bounded parsing overload can enforce allocation limits without changing default version leniency or last-wins duplicate behavior in the existing parser.

The envelope should contain an independently versioned container marker, payload kind, compression identifier, encoded and decoded byte lengths, reserved fields, and a specified corruption check. The first payload kind is valid UTF-8 3md source. Its document semantics therefore remain those of the existing parser. Encoding a `Document` uses canonical serialized text; this does not promise preservation of comments, line endings, or original whitespace. If exact original source bytes become necessary, expose that as a separately documented API.

Specify the byte layout and checked arithmetic before coding. Use a new discriminant that cannot be confused with Rook's existing voxel-specific version-1 header. The `.3mdb` suffix alone must never determine the payload schema. Unsupported magic, versions, payload kinds, compression identifiers, or reserved fields must fail explicitly.

Compression `.none` is the mandatory portable baseline. Apple LZFSE may be an optional backend under `#if canImport(Compression)`; other platforms must report unsupported compression rather than misread the bytes. An uncompressed container must remain available on those platforms. `Compression` and `CryptoKit` imports cannot be added unconditionally to the cross-platform core. Choose and document a portable corruption-check algorithm, or isolate an optional backend, before promising equivalent support across implementations. A checksum detects corruption; it is not author authentication.

Bound encoded bytes, declared decoded bytes, actual decoded output, line count, plane count, and per-record sizes before large allocations. Require one fully consumed compression stream, exact output length, and no trailing data. Existing public `Document` initializers and synthesized Codable decoding can construct values outside parser invariants; new storage encoding must validate finite coordinates, unique plane positions, and a serializable document instead of assuming that every value came from `Parser`.

## Second slice: self-contained named document composition

Add a general composition profile containing a root document ID, a deterministic named library of document definitions, and explicit references between those definitions. Proposed value types are `DocumentComposition`, `DocumentEntry`, and `DocumentReference`, with a dedicated `DocumentCompositionCodec`. Each definition is stored once; references identify that definition rather than embedding repeated copies.

Use an explicit, versioned profile on existing 3md text, initially with a well-defined fenced JSON manifest and embedded 3md sources. Preserve the normal text grammar. The graph representation should preserve document metadata and application-specific reference attributes; it must not prescribe voxel geometry. Reference IDs are identifiers, never paths or URLs. Resolution reads only the supplied in-memory library. Decoding performs no filesystem access, network access, process execution, or implicit import search.

Validate root existence, unique safe IDs, reference targets, reference-record keys, cycles, maximum graph depth, definition count, total unique source bytes, and bounded traversal occurrences. Validate unused definitions as well as the root so invalid hidden nodes cannot survive an apparently valid load. Bounds are a declared generic policy, not Rook's voxel limits. Use overflow-safe accumulation and check cancellation during graph traversal and embedded-document decoding. Cache each parsed/resolved definition once per operation.

For the first graph slice, provide reference lookup and graph inspection. Automatic Markdown flattening needs separately specified plane-position conflicts, link remapping, labels, ordering, and axis compatibility. Automatic voxel expansion remains Rook's responsibility. A generic binary envelope can store a composition-profile document once that profile exists; there is no need to invent a second unrelated compressed format.

## Swift 6 and cancellation

Keep public data immutable and `Sendable`; keep parsing and encoding stateless. CPU-bound throwing APIs can remain synchronous so callers choose their executor. Do not put compression or graph traversal on `MainActor`. Add cooperative cancellation checks at bounded intervals and propagate `CancellationError` unchanged. Do not return partial documents or partially validated graphs.

Native compression streams and unsafe buffer pointers remain confined to one operation and their buffer lifetimes. Do not use unchecked Sendable wrappers to pass mutable codec state between tasks. An eventual async convenience API must define task ownership and cancellation propagation; cancellation of a caller does not automatically cancel an unrelated detached task. No callback-thread or timer abstraction is required for this core work.

## Backward-compatible migration into Rook

1. Keep Rook's `1.8.1` dependency pin and current readers/writers unchanged during upstream development.
2. Preserve existing `ascii-sculpture-1`, `ascii-composition-1`, and `ascii-world-1` files and their app-specific validation and expansion rules.
3. Preserve the existing voxel `.3mdb` reader permanently for already saved files. Do not relabel those files as conforming to the proposed general envelope.
4. After an independently verified upstream version is available, add a clearly discriminated read path for the general envelope. Never reinterpret a failed legacy decode as a different schema merely because both files use `.3mdb`.
5. Convert on explicit save/export or an explicit migration command. Preserve the source on failure and retain Rook's new-file publication protections. Do not silently rewrite user files, generated examples, or existing media.
6. Adapt Rook composition to the named-document library only after round-trip and semantic equivalence tests prove all shared references, rotations, padding, and sparse placements are preserved. The core graph stores references; Rook still supplies voxel semantics.

## Verification required before an upstream change is done

Meaningful new tests should include:

- Existing text conformance vectors unchanged, including older version markers, duplicate-key behavior, fences, quoted values, unknown metadata, and custom axes.
- General documents with Unicode, negative/fractional plane coordinates, preambles, arbitrary attributes, links, and more than one axis interpretation round-trip through text and the uncompressed envelope.
- Fixed binary vectors and independently checked headers; unknown versions/algorithms, bad checksums, truncated streams, trailing bytes, oversized declarations, decompression expansion, and exact boundary limits fail predictably.
- Optional LZFSE round trips and explicit unsupported-backend behavior on platforms without Apple's Compression framework. Do not claim cross-language binary support until those implementations have it.
- Named shared references and nested graphs survive serialization with one definition per ID. Missing targets, duplicate IDs, cycles, excessive depth/bytes/occurrences, invalid unused nodes, and cancellation return no partial result.
- In-memory composition decoding works after any original imported source files have been removed, proving there is no hidden path resolver.
- Rook's published compact files continue to decode, and explicit conversion preserves sculpture cells and composition expansion exactly.

The upstream [AGENTS.md](/Users/leif/Development/_CorvidLabs/3md/AGENTS.md) requires `fledge lanes run verify` before calling a source change done, module-spec updates followed by `fledge spec check`, `augur check --staged` before commit, and `augur check --range origin/main..HEAD` before merge. A block verdict is a hard stop. After a green lane it requires `attest sign --commit HEAD --reviewer agent:<id> --from-augur augur.json --tests-passed`, using the actual actor and evidence. None of those commands was run for this assessment, and no approval, review, attestation, or lifecycle completion is claimed.

The current upstream [fledge.toml](/Users/leif/Development/_CorvidLabs/3md/fledge.toml:40) verify lane includes Swift lint/build/tests, JavaScript and Rust checks, generated element-bundle drift, editor grammar, and spec validation. Authored feature code can remain Swift-only while those existing checks verify text compatibility. The new binary/composition capability must be explicitly marked Swift-first until other implementations support it; their current text-parser equivalence must remain intact.

A later implementation should use a fresh isolated checkout, proposed under `/private/tmp/3md-binary-composition-assessment` with a unique suffix if needed, from the verified official origin. No clone or worktree was created here. Publication, merge, release, or changes to another repository's visibility require their own authority; Rook's feature-branch authority does not supply it.

## Implementation follow-up under subsequent authorization

Leif subsequently requested a core ThreeMD subagent, SpecSync 6 full SDD, latest Trust, and published pull requests. A fresh official checkout at `/private/tmp/3md-binary-composition-20261004` now carries the Swift implementation on `leif/binary-composition-sdd`, published as [ThreeMD PR58](https://github.com/CorvidLabs/3md/pull/58). The earlier assessment above remains historical.

The generic binary envelope and named-document composition are additive Swift APIs. Six real examples have readable, portable binary and optional LZFSE forms, with equality and manifest tests. All 176 Swift tests, 79 existing JavaScript tests, Rust conformance/docs, element drift and editor grammar pass. Forced strict SpecSync 6 validates all three specs without warnings. Direct Trust 1.2.2 passes in the existing progressive provenance mode; signed provenance remains unsatisfied by the actual unsigned agent claim.

The draft preserves an SDD closing blocker: historical CHG-0002 lacks its original attempt ledger, and pinned SpecSync 6 refuses a fresh attempt after an audited reopen. Its supported migration dry run offers no recovery. Actual prior evidence, reopening, failure, review scope and source hashes are retained in that PR. No history, signer identity or gate was fabricated. The other two stale historical records received append-only verification and delegated acceptance refreshes.

Rook still pins ThreeMD 1.8.1 and uses its existing private sculpture containers and voxel semantics. The library change is unreleased; Rook integration and explicit migration remain separately bounded work after a verified upstream version is available.

## Editing release preparation follow-up, 2026-10-05

The preceding draft/blocker status is historical. PR58 now includes the decimal-decoding resource repair and completed SpecSync closing recovery, with 180 Swift tests, 79 JavaScript tests and the full Trust lane passing on `0d345bb2ef7ec7cede572c24309761bec047301a`. It remains unreleased. The unchanged soft provenance policy accepts an accurately recorded unsigned agent claim; this is not a permitted signature or human approval.

[ThreeMD PR58](https://github.com/CorvidLabs/3md/pull/58) and the workflow-evidence follow-up PR60 have landed. [ThreeMD PR61](https://github.com/CorvidLabs/3md/pull/61) is reconciled against main for stable namespaced identities, exact-revision typed patches, bounded diagnostics and a release capability matrix. Its full Trust lane and GitHub checks pass. Leif additionally authorized native TypeScript and Rust implementations with shared binary, composition and editing fixtures in a separate follow-up. Indexed loading and material/timing profiles remain later work. Sculpt PR33's definition has landed; [Sculpt PR34](https://github.com/CorvidLabs/rook/pull/34) contains the actual shared voxel-model implementation using the existing pinned library and app schemas. Leif will merge the prepared implementation PRs later; no tag, release or automatic dependency adoption is part of this slice.
