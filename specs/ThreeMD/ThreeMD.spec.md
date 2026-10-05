---
module: ThreeMD
version: 3
status: active
files:
  - Sources/ThreeMD/Axis.swift
  - Sources/ThreeMD/Plane.swift
  - Sources/ThreeMD/Document.swift
  - Sources/ThreeMD/ParseError.swift
  - Sources/ThreeMD/Parser.swift
  - Sources/ThreeMD/Serializer.swift
  - Sources/ThreeMD/HTMLRenderer.swift
  - Sources/ThreeMD/MarkdownRenderer.swift
  - Sources/ThreeMD/CrossPlaneLink.swift
  - Sources/ThreeMD/Document+Links.swift
  - Sources/ThreeMD/CrossPlaneLinkEdge.swift
  - Sources/ThreeMD/Double+ThreeMD.swift
  - Sources/ThreeMD/ThreeMDAnchor.swift
  - Sources/ThreeMD/DocumentStorage.swift
  - Sources/ThreeMD/DocumentStorageCodec.swift
  - Sources/ThreeMD/DocumentStorageValidation.swift
  - Sources/ThreeMD/DocumentStorageCompression.swift
  - Sources/ThreeMD/DocumentComposition.swift
  - Sources/ThreeMD/DocumentCompositionLimits.swift
  - Sources/ThreeMD/DocumentCompositionCodec.swift
  - Sources/ThreeMD/DocumentCompositionJSON.swift
  - Sources/ThreeMD/DocumentEditingTypes.swift
  - Sources/ThreeMD/DocumentIdentity.swift
  - Sources/ThreeMD/DocumentEditing.swift
  - Sources/ThreeMD/DocumentCompositionEditing.swift
  - Sources/ThreeMD/DocumentDiagnostics.swift
  - Sources/ThreeMD/FiniteDecimal.swift
  - js/src/index.ts
  - rust/src/lib.rs
db_tables: []
depends_on: []
---

# ThreeMD

## Purpose

Additive editing APIs interpret optional namespaced identities, apply bounded exact-revision document/composition patches and report structured diagnostics. They are Swift-first and perform no external I/O. Existing raw parsing, z links and HTML anchors retain their semantics.

ThreeMD parses and serializes Markdown extended along one free Z axis. Its
immutable documents preserve source order, free axis labels, metadata and opaque
Markdown bodies. SPEC.md owns the frozen text grammar and additive storage and
composition formats.

Swift, TypeScript and Rust retain their shared text-parser conformance contract.
Swift additionally provides HTML/Markdown renderers, bounded general-document
storage, and a validated self-contained library of named documents. The new
storage and composition APIs are Swift-first; this does not claim implementation
in the ports or hosted viewer. The interactive component is the separate
ThreeMDElement module.

## Public API

Each symbol appears once. Descriptions identify its owning type and overloads.
Initializers are grouped under `init`. New storage and composition operations
are pure synchronous APIs; they never open paths or resolve URLs.

| Export | Contract |
|--------|----------|
| `Axis` | RawRepresentable, Sendable, Hashable, Codable normalized axis label. |
| `rawValue` | Trimmed and lowercased axis string. |
| `time` | Named time axis. |
| `depth` | Named depth axis. |
| `layer` | Named layer axis. |
| `frame` | Named frame axis. |
| `space` | Named space axis. |
| `Plane` | Sendable, Hashable, Codable Markdown slice. |
| `z` | Finite plane position; Rust duplicate-position error payload. |
| `x` | Optional finite horizontal offset. |
| `y` | Optional finite vertical offset. |
| `label` | Optional plane name. |
| `attributes` | Plane strings or opaque composition-reference strings. |
| `body` | Opaque Markdown content. |
| `anchorID` | Plane stable HTML ID; Document.anchorID(forZ:) lookup helper. |
| `Document` | Sendable, Hashable, Codable document. |
| `version` | Free declared format-version string. |
| `axis` | Document axis; Rust axis(raw: &str) normalizes its label. |
| `title` | Optional document title. |
| `metadata` | Non-reserved frontmatter fields. |
| `preamble` | Optional content before the first plane. |
| `planes` | Planes in source order. |
| `planesByZ` | Ascending-Z read-only view. |
| `plane` | Document.plane(atZ:) returns a plane or nil. |
| `Parser` | Sendable existing text parser. |
| `parse` | Swift Parser.parse(_:) and TypeScript/Rust parse(source) retain typed text failures. |
| `Serializer` | Sendable existing text writer. |
| `render` | Serializer document-to-text, HTMLRenderer document-to-HTML, MarkdownRenderer Markdown-to-HTML. |
| `serialize` | TypeScript/Rust document-to-text function, including Rust Document helper. |
| `HTMLRenderer` | Accessible standalone HTML5 renderer. |
| `MarkdownRenderer` | CommonMark subset renderer. |
| `ThreeMDAnchor` | Sendable stable cross-plane anchor namespace. |
| `id` | ThreeMDAnchor.id(forZ:); composition entry's case-sensitive identity. |
| `href` | ThreeMDAnchor.href(forZ:) fragment target. |
| `CrossPlaneLink` | Sendable, Hashable, Codable extracted link. |
| `sourceZ` | Swift/TypeScript link or edge source. |
| `targetZ` | Swift/TypeScript link or edge target. |
| `text` | Optional link label; DocumentStorageFormat.text emits canonical UTF-8. |
| `targetExists` | Swift/TypeScript target-presence flag. |
| `CrossPlaneLinkEdge` | Swift/TypeScript summarized link edge. |
| `count` | Links collapsed into an edge. |
| `links` | Extract links in source order in all text implementations. |
| `danglingLinks` | Swift/TypeScript unresolved-link filter. |
| `linkGraph` | Swift/TypeScript summarized edge list. |
| `ParseError` | Existing parser error; Swift Sendable, Equatable, LocalizedError. |
| `ParseErrorCode` | TypeScript union of six canonical parser failure names. |
| `code` | Stable parser failure name or DocumentDiagnostic.Code. |
| `line` | Optional one-based parser source line. |
| `detail` | Optional parser failure detail. |
| `errorDescription` | Swift localized parser/storage/composition/edit explanation. |
| `missingFrontmatter` | Swift missing opening fence. |
| `invalidFrontmatter` | Swift malformed/unclosed frontmatter. |
| `missingVersion` | Swift missing/empty version. |
| `missingPlanePosition` | Swift directive without Z. |
| `invalidPlaneDirective` | Swift malformed directive, numeric value or quote. |
| `duplicatePlane` | Swift repeated Z. |
| `DocumentCompression` | UInt8, Sendable compression identifier. |
| `none` | Portable uncompressed payload, identifier 0. |
| `lzfse` | Conditional Apple LZFSE, identifier 1. |
| `DocumentStorageFormat` | Equatable, Sendable explicit storage selection. |
| `binary` | .binary(compression: DocumentCompression). |
| `DocumentDecodeLimits` | Equatable, Sendable bounded resource policy. |
| `maximumEncodedBytes` | Container/text ceiling, standard and absolute maximum 64 MiB. |
| `maximumDecodedBytes` | Decoded UTF-8 ceiling checked before allocation, standard/maximum 64 MiB. |
| `maximumLines` | Physical lines, standard/maximum 100,000. |
| `maximumPlanes` | Planes, standard/maximum 65,536. |
| `maximumRecordBytes` | Per-line/scalar/preamble/body bytes, standard 8 MiB, explicit ceiling 64 MiB. |
| `standard` | Storage/composition/edit policy with documented bounded defaults. |
| `DocumentStorageCodec` | Pure content-detecting general storage. |
| `containerVersion` | UInt16 binary envelope version 1. |
| `headerByteCount` | Header length 40 bytes. |
| `isBinary` | isBinary(_ data: Data) -> Bool recognizes complete magic only. |
| `validate` | validate(_ document: Document, limits: DocumentDecodeLimits = .standard) throws. |
| `encode` | Storage encode(_:format:limits:) throws -> Data defaults to text; composition encode(_:limits:documentLimits:) emits readable profile. |
| `decode` | Storage Data -> Document; composition Data/Document -> DocumentComposition, all throwing with explicit policies. |
| `DocumentStorageError` | Equatable, Sendable, LocalizedError storage failures. |
| `invalidLimits` | Storage or named composition limit is invalid. |
| `oversizedInput` | Encoded input/writer output exceeds input policy. |
| `oversizedOutput` | Decoded/canonical output exceeds output policy. |
| `tooManyLines` | Excessive physical lines. |
| `tooManyPlanes` | Excessive planes. |
| `oversizedRecord` | Excessive line/scalar/preamble/body. |
| `invalidUTF8` | Invalid payload encoding. |
| `invalidText` | Wrapped existing ParseError. |
| `invalidDocument` | Direct value cannot serialize faithfully, including nonfinite/repeated Z or invalid scalar structure. |
| `invalidContainer` | Invalid/truncated header. |
| `unsupportedVersion` | Binary version other than 1. |
| `unsupportedPayloadKind` | Payload kind other than canonical UTF-8 text. |
| `unsupportedCompression` | Unknown algorithm identifier. |
| `unsupportedFlags` | Nonzero flags. |
| `nonzeroReserved` | Nonzero reserved header field. |
| `lengthMismatch` | Truncated/trailing/concatenated stream or inconsistent lengths. |
| `checksumMismatch` | Header/payload corruption checksum differs. |
| `compressionUnavailable` | Requested compression absent on platform. |
| `compressionFailed` | System compression fails. |
| `DocumentReference` | Hashable, Sendable target and opaque attributes. |
| `targetID` | ID in the supplied library, never a path or URL. |
| `DocumentEntry` | Hashable, Sendable named Document and ordered references. |
| `document` | Entry Document; codec document(for:limits:documentLimits:) throws -> Document creates the profile. |
| `references` | Ordered references without automatic flattening. |
| `DocumentComposition` | Hashable, Sendable validated rooted library. |
| `rootID` | Existing root ID. |
| `entries` | Unique definitions sorted by ASCII ID. |
| `rootEntry` | Validated root definition. |
| `entry` | entry(id: String) -> DocumentEntry? looks up supplied definitions. |
| `DocumentCompositionLimits` | Equatable, Sendable lowering-only graph/profile policy. |
| `maximumDefinitions` | 1,024 unique definitions. |
| `maximumReferences` | 16,384 reference records total. |
| `maximumDepth` | 64 nodes along every dependency path. |
| `maximumDefinitionBytes` | 16 MiB summed unique canonical definition source. |
| `maximumTraversalOccurrences` | 1,000,000 reachable occurrences per definition, counting shared targets each time. |
| `maximumProfileBytes` | 20 MiB complete readable profile. |
| `maximumReferenceAttributes` | 64 attributes per reference. |
| `maximumReferenceAttributeBytes` | 16 KiB summed UTF-8 keys/values per reference. |
| `DocumentCompositionCodec` | Strict readable 3md-composition-1 profile, binary-wrappable as Document. |
| `isComposition` | Profile-header recognition only; decode validates. |
| `DocumentCompositionError` | Equatable, Sendable, LocalizedError graph/profile failures. |
| `invalidID` | ID not matching 1–64 ASCII letters/digits/underscore/hyphen, starting with letter/digit. |
| `duplicateID` | Repeated identity. |
| `missingRoot` | Missing root definition. |
| `missingTarget` | Missing reference target, including unused definitions. |
| `cycle` | Repeated ID on a dependency path, including unused subgraphs. |
| `tooManyDefinitions` | Definition policy exceeded. |
| `tooManyReferences` | Reference-record policy exceeded. |
| `depthExceeded` | Dependency path too deep. |
| `definitionBytesExceeded` | Unique source-byte policy exceeded. |
| `traversalOccurrencesExceeded` | Reachable occurrence policy exceeded. |
| `referenceAttributesExceeded` | Attribute count/UTF-8 policy exceeded. |
| `profileBytesExceeded` | Profile-byte policy exceeded. |
| `invalidProfile` | Malformed/unknown/duplicate JSON or invalid outer profile. |
| `unsupportedProfile` | Unknown composition schema. |
| `DocumentIdentity` | Optional editing convention; raw parsing keeps attributes opaque. |
| `attributeKey` | The namespaced attribute key 3md-id. |
| `isValid` | Safe 1...64-byte case-sensitive ASCII identity predicate. |
| `adopt` | Document/composition overloads preserve supplied valid IDs and assign only missing plane/reference IDs. |
| `stableID` | Plane/DocumentReference optional namespaced attribute accessor, independent of position/target. |
| `DocumentRevision` | Equatable, Hashable, Codable, Sendable exact canonical UTF-8 precondition, not authenticity. |
| `canonicalContent` | Complete canonical document/profile text; equality and hashing use exact UTF-8 bytes. |
| `==` | DocumentRevision exact UTF-8 equality, including Unicode normalization distinctions. |
| `hash` | DocumentRevision.hash(into:) agrees with exact-byte equality; hashes are never revision preconditions. |
| `DocumentHeader` | Hashable, Codable, Sendable non-plane fields replaced together. |
| `DocumentEdit` | Equatable, Codable, Sendable ordered plane/header operation. |
| `insert` | Insert a plane at a source-order index. |
| `remove` | Remove a plane by stable identity. |
| `replace` | Replace a plane while retaining its identity. |
| `move` | Move an identified plane to a final source-order index. |
| `replaceHeader` | Replace non-plane fields with DocumentHeader. |
| `DocumentPatch` | Equatable, Codable, Sendable atomic expected-revision document transaction. |
| `expectedRevision` | Complete canonical source that must equal the current snapshot revision. |
| `operations` | Ordered document/composition edits, bounded before staging. |
| `DocumentSnapshot` | Immutable Codable, Sendable validated document/revision pair; decode rejects disagreement. |
| `revision` | Snapshot's exact canonical expected content. |
| `DocumentEditor` | Pure bounded document transaction service. |
| `apply` | DocumentEditor/CompositionEditor apply(_:to:limits:...) validate a private final candidate or throw without partial publication. |
| `CompositionEdit` | Equatable, Codable, Sendable definition/reference/root operation. |
| `insertEntry` | Add a definition to the candidate graph. |
| `removeEntry` | Remove a definition by ID; final graph must retain every target. |
| `replaceEntry` | Replace a definition without changing its ID. |
| `selectRoot` | Select an existing final root definition. |
| `insertReference` | Insert an identified reference in a named owner's source order. |
| `removeReference` | Remove a reference by owner and stable identity. |
| `replaceReference` | Replace a reference while retaining its scoped identity. |
| `moveReference` | Move a reference within its owning entry. |
| `CompositionPatch` | Equatable, Codable, Sendable atomic exact-profile revision transaction. |
| `DocumentCompositionSnapshot` | Immutable Codable, Sendable validated graph/revision pair; decode rejects disagreement. |
| `composition` | Complete self-contained snapshot graph. |
| `CompositionEditor` | Pure graph staging and complete final validation without resource resolution. |
| `DocumentEditLimits` | Equatable, Sendable explicit operation/payload/diagnostic ceilings. |
| `maximumOperations` | Default 1,024 operations, maximum 4,096; zero allows only empty patches. |
| `maximumPayloadBytes` | Charged operand UTF-8 bytes, default 16 MiB, maximum 64 MiB. |
| `maximumDiagnostics` | Collected issue ceiling, default 256, maximum 1,024. |
| `maximumDiagnosticBytes` | Diagnostic source-work ceiling, default and maximum 64 MiB. |
| `DocumentDiagnostic` | Equatable, Codable, Sendable code/severity/message with available line/path evidence. |
| `Code` | Stable editing/validation diagnostic categories. |
| `Severity` | Diagnostic error or warning classification. |
| `message` | Presentable explanation; consumers use code for programmatic handling. |
| `severity` | Whether the reported issue prevents the operation. |
| `sourceLine` | Actual parser line evidence, nil for value-only inspection. |
| `path` | Optional structural document/graph/operation path. |
| `error` | Diagnostic preventing an operation. |
| `warning` | Diagnostic advisory severity. |
| `invalidIdentity` | Supplied namespaced identity violates the safe ASCII convention. |
| `duplicateIdentity` | Namespaced identity repeated within its scope. |
| `missingIdentity` | An operation requires an adopted identity. |
| `identityChanged` | Replacement attempted to change the stable identity. |
| `staleRevision` | Expected complete canonical content differs. |
| `invalidIndex` | Source-order insertion/move index outside the operation's bounds. |
| `duplicatePosition` | Final plane positions conflict. |
| `invalidComposition` | Final graph failed validation. |
| `operationLimit` | Patch exceeds operation count policy. |
| `payloadLimit` | Expected revision, operand or diagnostic work exceeds policy. |
| `parseFailure` | DocumentDiagnostics.parseFailure(_:) preserves existing ParseError code/line/detail in structured form. |
| `DocumentEditError` | Equatable, Sendable, LocalizedError failed transaction carrying one structured diagnostic. |
| `diagnostic` | Structured failed-operation evidence. |
| `DocumentDiagnosticReport` | Equatable, Codable, Sendable deterministic issues with truncation evidence. |
| `diagnostics` | Collected issues in document or graph order. |
| `isTruncated` | Remaining content was not completely inspected after reaching a ceiling. |
| `DocumentDiagnostics` | Additive bounded source/document/composition inspection. |
| `inspect` | Throwing source/document/composition overloads inspect storage, identity, positions and validated graph values; no legacy link extraction. |
| `init` | Public Swift model/service constructors; policies and composition validation throw. |

### Public initializer contracts

DocumentDecodeLimits accepts maximumEncodedBytes, maximumDecodedBytes,
maximumLines, maximumPlanes and maximumRecordBytes with the defaults above.
All are positive and within absolute ceilings. DocumentCompositionLimits takes
all eight maximum-properties above with their defaults; references and attribute
limits can be zero, while other limits are positive. DocumentReference defaults
attributes to [:]; DocumentEntry defaults references to [].
DocumentComposition(rootID:entries:limits:documentLimits:) throws defaults both
policies to .standard and validates every definition before returning.

Editing snapshot constructors validate source values and canonicalize revision text. DocumentPatch and CompositionPatch
constructors take expectedRevision and ordered operations without executing them. DocumentEditLimits takes the four
maximum-properties above; payload/diagnostic limits are positive. DocumentHeader captures a Document or explicitly takes
version, axis and optional title/metadata/preamble. Diagnostic/report constructors retain the evidence supplied by callers.
Codable editing transport is not a bounded streaming JSON reader: callers must cap untrusted wire bytes before decoding.

## Invariants

Editing invariants: `3md-id` is an opt-in plane/reference attribute, unique among planes of one document or references of one owning entry. Explicit adoption preserves valid IDs and ordinary `id` metadata. Exact canonical-content revisions reject stale patches without author-authentication claims. Ordered operations work on a private candidate and validate the final document/full graph before publishing; intermediate coordinate swaps are allowed. Invalid/stale/canceled edits leave the input unchanged. Operation, payload and diagnostic work are bounded. Diagnostics use actual available source lines or structural paths and never invent value-only line numbers. Identity-aware editing does not silently rewrite z-based links.

Rust exposes the same link facts using source_z, target_z and target_exists,
and uses PascalCase parser error variants. Its code() helper supplies the shared
camel-case failure names. These idiomatic names do not change the conformance
contract.

1. Existing text grammar, source order, version/axis labels and conformance
   vectors remain unchanged. Parser and link numeric validation share a linear finite-decimal predicate preserving grammar.
2. Direct storage values require finite coordinates, unique Z and a faithful
   canonical text parse round trip. The new writer quotes every scalar.
3. Binary magic is `3mdbin\r\n`, separate from Rook's older voxel format.
   Header/version/kind/lengths/CRC follow SPEC.md section 11. Uncompressed storage
   is portable; system LZFSE is optional. CRC is not authenticity.
4. Declared decoded size is checked before allocation. Exact stream termination,
   output size and full input consumption are required. Errors yield no partial data.
5. Definitions are stored once, keep their own axes and reference only supplied
   IDs. All nodes, including unused ones, must be valid, acyclic and within every
   graph budget. Reference order survives round trips.
6. Composition is one strict fenced JSON profile plane. Unknown/duplicate keys
   fail. A bounded scanner precedes Foundation object decoding. The outer record
   policy is explicitly 20 MiB; children use their own document policy.
7. Long operations check task cancellation where concurrency is available:
   macOS 10.15, iOS 13, tvOS 13, watchOS 6 or later and supported non-Apple
   platforms. Earlier Apple runtimes use a no-op cancellation check, preserving
   the original deployment baseline. Available cancellation propagates as
   CancellationError; callers may run pure synchronous APIs in a detached task.
8. The module has no file/network/process resolver, voxel placement, rendering
   transform or automatic flattening behavior.

## Behavioral Examples

Given identified planes at positions 0 and 1, one transactional patch can swap their positions while retaining both IDs and all unaffected content. If a later operation produces a duplicate final position or missing target, the complete patch fails and the original snapshot remains unchanged. Two references to one definition have different identities and can be retargeted independently. A reopened equivalent canonical document has an equal revision; altered canonical content rejects a patch prepared against the prior revision.

```text
Given a Unicode Document with metadata, finite offsets and literal quotes
When encoded as uncompressed general binary and decoded
Then all fields are equal and the magic/header/CRC follow SPEC.md.

Given two root references to one named child with different attributes
When the library is encoded as a profile and reloaded
Then the child source occurs once, reference order and attributes survive,
and lookup works after the original imported files have been removed.

Given an unused definition with a cycle or missing target
When constructing a DocumentComposition
Then validation fails without returning a library.

Given an existing text conformance fixture
When parsed by any existing language implementation
Then the prior expected result and error semantics remain unchanged.
```

## Error Cases

The export table records each typed failure. Storage rejects excess resources,
invalid UTF-8/text/direct values, malformed or unsupported headers, corruption,
unavailable compression and inexact/trailing streams. Composition rejects
unsafe/duplicate IDs, absent roots/targets, cycles, every budget excess and
malformed/unsupported profiles. Cancellation is distinct. Existing parser
errors retain their stable cases and metadata.

## Dependencies

- Swift Foundation for text, Data, JSON and localized errors.
- Conditional Apple system Compression for optional LZFSE; no third-party Swift
  dependency or CryptoKit requirement. The original text surface stays portable.
- Existing TypeScript/Rust text ports retain their original dependencies.

## Change Log

| Version | Date | Changes |
|---------|------|---------|
| Editing preparation | 2026-10-05 | Additive stable identities, exact-revision typed patches and structured diagnostics; Swift-first release preparation with unchanged text compatibility and historical archives. |
| 1 | 2026-06-23 | Initial text parser/serializer and HTML rendering spec. |
| 1 | 2026-06-24 | Shared text contract across Swift, TypeScript and Rust. |
| 2 | 2026-10-04 | Active exact export validation; additive bounded storage/composition with unchanged text conformance. Actual verification/publication belongs to the workflow-v2 change. |
| 3 | 2026-10-05 | implement-generic-binary-storage-and-document-composition-with-specsync-6-and-trust-1-2-2: Implement generic binary storage and document composition with SpecSync 6 and Trust 1.2.2 |
