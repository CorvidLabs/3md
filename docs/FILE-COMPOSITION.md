# Linked file composition

Status: ThreeMD 2.0 preparation, not a released feature.

## Public contract
An ordinary Document MAY have a metadata string named `3md-files`. Its value is a strict JSON object mapping single printable ASCII glyphs U+0021 through U+007E to relative filenames: `{"1":"models/tree.3md","2":"castle.3md"}`. Glyph placement belongs to the host. Generic Markdown, version, axes and existing document/plane identities remain valid.

Core performs no filesystem or network I/O. A host supplies DocumentFileSource(path, data) values. Resolving after child bytes change refreshes the linked snapshot. Sharing writes the resolved graph through existing `3md-composition-1` readable or general uncompressed binary codecs. No parser grammar, container or profile version changes.

Swift exposes DocumentFileSource(path: String, data: Data), DocumentFileReference(glyph: String, source: String), DocumentFileCompositionResult(rootPath: String, composition: DocumentComposition, fileRootIDs: [String: String], resolvedPaths: [String]), and DocumentFileComposition.ledger(in:), resolvePath(_:relativeTo:), resolve(rootPath:sources:limits:documentLimits:). Existing standard policies are defaults. TS and Rust expose equivalent idiomatic APIs.

## Paths and ledger
Paths normalize to NFC, are case sensitive, and use POSIX slashes. Reject absolute paths, backslashes, colons, ASCII controls, empty segments and trailing slash. Dot/parent segments resolve relative to containing file and cannot escape the project root. No percent decoding or extension restriction occurs. Normalize supplied paths from the project root; duplicate normalized paths fail.
Ledger values must be strings. Reject duplicate JSON keys including escaped spellings, malformed JSON and glyphs outside single printable ASCII. Order ledger references by glyph. Filename ordering is Unicode scalar order, never locale or UTF-16 order.

## Discovery and bundling
Before NFC normalization or indexing, the sum of original supplied-path UTF-8 bytes plus rootPath MUST fit maximumProfileBytes. Standalone resolvePath checks combined source and owner UTF-8 bytes against the standard document maximumRecordBytes (8 MiB). ledger JSON uses that same standalone record bound. These failures are inputLimit. Path scanning checks cancellation cooperatively.
Only reachable files decode. Supplied source count is bounded by maximumDefinitions before indexing, and aggregate reachable encoded bytes by maximumProfileBytes. Ordinary documents contribute local entry root; an existing composition contributes ALL its entries, including unused entries. Scan every embedded document ledger relative to its containing file.
Canonical paths deduplicate sources. Bound depth, definitions, references and traversal work, check cancellation, refuse file/graph cycles and return no partial results.
After discovery sort by normalized path scalar order, then local ID ASCII order; assign file-000000, file-000001 etc. Remap existing references and retain their order, attributes and optional stable identities. Append ledger edges in glyph order with attributes glyph and source-file (normalized project-relative path). Do not invent a stable reference ID.
Remove only 3md-files metadata from bundled documents. Preserve all other metadata, Markdown, axes and identities. Imported nested bundles retain their graph, including unused entries. Validate the final complete graph with existing limits, including conceptual traversal. Document identity adoption remains a separate editing operation. A moved bundle never needs or follows its source folder.

## Errors and interchange
DocumentFileCompositionError distinguishes invalid/duplicate paths, invalid ledger/glyph, missing files and input limits. Existing storage/composition/cancellation errors retain types.
Development interchange kind files has bytesHex containing UTF-8 JSON `{"rootPath":"root.3md","files":[{"path":"root.3md","bytesHex":"..."}]}`. Unknown/malformed protocol fields map to adapterFailure. New errors map to filePath, fileLedger, missingFile, fileLimit. Success uses the existing composition response/writers; produced bundles import through composition kind across all nine language pairs.

## Verification
Test simple, nested, repeated and refreshed children; text/binary children; nested bundles; identities/opaque attributes; duplicate basenames in different folders; Unicode and valid parent-relative paths; missing files; invalid paths/aliases; duplicate JSON keys; malformed ledger; cycles; lowered policies; cancellation. Shared Swift/TS/Rust inputs and all nine writer/reader pairs must pass. Complete Trust is required. Portable output must reopen without source files.
