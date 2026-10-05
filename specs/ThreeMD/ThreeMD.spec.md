---
module: ThreeMD
version: 5
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
  - js/src/portable.ts
  - js/src/storage.ts
  - js/src/composition.ts
  - js/src/editing.ts
  - rust/src/lib.rs
  - rust/src/storage.rs
  - rust/src/composition.rs
  - rust/src/editing.rs
  - rust/src/diagnostics.rs
  - Sources/ThreeMDInterop/Protocol.swift
  - Sources/ThreeMDInterop/SwiftAdapter.swift
  - Sources/ThreeMDInterop/main.swift
db_tables: []
depends_on: []
---

# ThreeMD

## Purpose

Additive Swift, TypeScript and Rust APIs interpret optional namespaced identities, apply bounded exact-revision document/composition patches and report structured diagnostics. They perform no external I/O. Existing raw parsing, z links and HTML anchors retain their semantics.

ThreeMD parses and serializes Markdown extended along one free Z axis. Its
immutable documents preserve source order, free axis labels, metadata and opaque
Markdown bodies. SPEC.md owns the frozen text grammar and additive storage and
composition formats.

Swift, TypeScript and Rust retain their shared text-parser conformance contract.
Swift additionally provides HTML/Markdown renderers. All three libraries provide
bounded general-document storage and a validated self-contained library of named
documents. The ports support the uncompressed envelope and explicitly reject
LZFSE backend requests. The interactive component remains the separate
ThreeMDElement module; its hosted UI is not changed by this slice.

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
| `parseFailure` | DocumentDiagnostics.parseFailure(_:) maps existing parser failure to generic code, actual sourceLine and localized message. |
| `DocumentEditError` | Equatable, Sendable, LocalizedError failed transaction carrying one structured diagnostic. |
| `diagnostic` | Structured failed-operation evidence. |
| `DocumentDiagnosticReport` | Equatable, Codable, Sendable deterministic issues with truncation evidence. |
| `diagnostics` | Collected issues in document or graph order. |
| `isTruncated` | Remaining content was not completely inspected after reaching a ceiling. |
| `DocumentDiagnostics` | Additive bounded source/document/composition inspection. |
| `inspect` | Throwing source/document/composition overloads inspect storage, identity, positions and validated graph values; no legacy link extraction. |
| `init` | Public Swift model/service constructors; policies and composition validation throw. |
| `DocumentStorageErrorCode` | TypeScript typed stable storage failure names. |
| `DocumentCompositionErrorCode` | TypeScript typed stable composition failure names. |
| `DocumentDiagnosticCode` | TypeScript typed diagnostic names. |
| `CancellationToken` | Rust cloneable shared atomic cancellation state with new, cancel and is_cancelled. |
| `OperationOptions` | Rust explicit operation policy carrying optional cancellation; default leaves it absent. |
| `with_cancellation` | Construct Rust operation options from a token. |
| `is_cancelled` | Observe Rust cancellation flag. |
| `cancel` | Mark a Rust token canceled; bounded operations report typed cancellation. |
| `storage` | Rust pure general text/container codec module. |
| `editing` | Rust immutable snapshots, identity adoption and atomic patches module. |
| `CONTAINER_VERSION` | Rust general envelope version, 1. |
| `HEADER_BYTE_COUNT` | Rust complete envelope header length, 40. |
| `IDENTITY_ATTRIBUTE_KEY` | Rust namespaced identity key, 3md-id. |
| `is_binary` | Rust complete binary magic predicate. |
| `is_composition` | Rust composition profile discriminator. |
| `is_valid_id` | Rust bounded composition definition ID predicate. |
| `is_valid_identity` | Rust bounded editing identity predicate. |
| `stable_id` | Rust Plane/DocumentReference namespaced identity accessor. |
| `root_id` | Rust immutable graph root ID accessor. |
| `root_entry` | Rust validated root definition accessor. |
| `from_parts` | Rust snapshot reconstruction rejects forged document/revision pairs. |
| `adopt_document` | Rust explicit deterministic missing plane identity adoption. |
| `adopt_composition` | Rust explicit document/reference identity adoption with owner scopes. |
| `apply_document_patch` | Rust staged ordered operations validate final value before publication. |
| `apply_composition_patch` | Rust staged operations validate the entire resulting graph before publication. |
| `inspect_source` | Rust bounded storage decode and structured diagnostic report. |
| `inspect_document` | Rust bounded value-only identity/position diagnostics without invented lines. |
| `inspect_composition` | Rust bounded graph identity diagnostics; no link extractor or resolver. |
| `parse_failure` | Rust existing parser failure to source-line diagnostic adapter. |
| `decode_document` | Rust strict composition profile Document decoder. |
| `as_str` | Rust stable camel-case diagnostic code spelling. |
| `DiagnosticCode` | Rust diagnostic code enum with stable shared names. |
| `DiagnosticSeverity` | Rust error/warning enum. |
| `new` | Rust model/policy/token constructors; graph/snapshot constructors validate before returning. |
| `check` | Crate-internal Rust cancellation poll, not a root public API. |
| `checkCancellation` | Internal TypeScript AbortSignal poll, not reexported by the package root. |
| `InvalidUnicodeError` | Internal TypeScript invalid surrogate failure mapped to typed storage/edit errors. |
| `utf8Length` | Internal checked UTF-8 work count with cancellation. |
| `stringsEqual` | Internal exact dictionary comparison. |
| `canonicalStrings` | Internal NFC-equivalent dictionary reconstruction retaining spelling. |
| `canonicalKeys` | Internal TypeScript NFC scalar key ordering. |
| `canonicalDocument` | Internal TypeScript canonical dictionary normalization. |
| `documentsEqual` | Internal semantic document equality. |
| `frozenStrings` | Internal TypeScript copied immutable string map. |
| `frozenPlane` | Internal TypeScript copied immutable plane. |
| `frozenDocument` | Internal TypeScript copied immutable document. |
| `validID` | Internal TypeScript safe ASCII identifier check. |
| `boundedInteger` | Internal TypeScript integer policy check. |
| `canonicalNumber` | Internal TypeScript Swift-compatible finite decimal spelling. |
| `BoundedTextWriter` | Internal TypeScript byte-budgeted canonical text accumulator. |
| `frozenReference` | Internal TypeScript copied immutable reference. |
| `frozenEntry` | Internal TypeScript copied immutable definition. |
| `crc32` | Crate-internal Rust envelope checksum, not authenticity. |
| `parse_data` | Crate-internal Rust bounded UTF-8/text decode and Unicode key reconstruction. |
| `position_key` | Crate-internal Rust exact finite coordinate set key. |
| `normalized_key` | Crate-internal Rust bounded NFC key normalization. |
| `canonical_keys` | Crate-internal Rust normalized scalar key ordering. |
| `canonical_number` | Crate-internal Rust Swift-compatible finite decimal spelling. |
| `swift_double` | Crate-internal Rust shortest decimal formatter with Swift notation threshold and ties-to-even spelling. |
| `trimFoundationWhitespace` | Internal TypeScript linear scan using the shared Foundation horizontal whitespace table. |
| `isFoundationWhitespace` | Internal TypeScript shared horizontal whitespace predicate; no newline/BOM trimming. |
| `parse_with_options` | Crate-internal Rust parser path with cooperative cancellation and normalized position-set checks. |
| `canonical_data` | Crate-internal Rust budgeted canonical text encoding. |
| `validate_graph` | Crate-internal Rust whole-library resource and target validation. |
| `PayloadBudget` | Crate-internal Rust cumulative edit work counter. |
| `charge` | Crate-internal checked payload byte accounting. |
| `header` | Crate-internal header payload accounting. |
| `make` | Crate-internal Rust report accumulation helper. |
| `composition_error` | Crate-internal Rust graph error to diagnostic mapping. |

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

### Portable surfaces

Portable API contracts: TypeScript exports the analogous storage/composition/editing types through `js/src/index.ts`, with Uint8Array storage, named policy options and optional AbortSignal as the last argument. Its snapshots and graphs copy/freeze values, and fromJSON reconstructs and validates exact revision pairs. `stableID(value)` reads the namespaced attribute without altering existing Plane/Document interfaces. Rust exposes storage, composition, editing and diagnostics modules plus model/policy/error reexports. Operations accept policies and `OperationOptions`; private snapshot/graph fields use immutable accessors. New Rust canonical storage uses pinned unicode-normalization for NFC scalar ordering, rejects ambiguous canonically equivalent keys in direct BTreeMap values and reconstructs first-spelling/last-value behavior while decoding source. The interchange follow-up aligns existing Unicode whitespace and source-key grammar interpretation, and repairs lossless legacy scalar quoting. Public signatures and frozen syntax remain. Legacy spelling may vary while canonical bytes and reimported semantics agree. The development coordinator uses processes only in its separate executable target; the library remains pure.



Cancellation is cooperative. JavaScript work is synchronous, so an AbortSignal dispatched on the same event loop cannot preempt it mid-call; callers can pre-cancel or schedule work and cancellation in their own execution context. No library worker or external service is created. Rust's shared atomic flag can be canceled from another thread. Both ports check bounded work and return no partial result.

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
- TypeScript adds no production dependency. Rust adds exact unicode-normalization 0.1.25 for new canonical key comparison, locked with its small dependencies. Existing text parsing/serialization behavior is unchanged.

## Change Log

| Version | Date | Changes |
|---------|------|---------|
| Editing preparation | 2026-10-05 | Additive stable identities, exact-revision typed patches and structured diagnostics; Swift-first release preparation with unchanged text compatibility and historical archives. |
| 1 | 2026-06-23 | Initial text parser/serializer and HTML rendering spec. |
| 1 | 2026-06-24 | Shared text contract across Swift, TypeScript and Rust. |
| 2 | 2026-10-04 | Active exact export validation; additive bounded storage/composition with unchanged text conformance. Actual verification/publication belongs to the workflow-v2 change. |
| 3 | 2026-10-05 | implement-generic-binary-storage-and-document-composition-with-specsync-6-and-trust-1-2-2: Implement generic binary storage and document composition with SpecSync 6 and Trust 1.2.2 |
| 4 | 2026-10-05 | add-stable-document-identities-transactional-patches-and-diagnostics-for-release-preparation: Add stable document identities transactional patches and diagnostics for release preparation |
| 5 | 2026-10-05 | bring-bounded-binary-composition-and-transactional-editing-to-typescript-and-rust-with-shared-conformance: Bring bounded binary composition and transactional editing to TypeScript and Rust with shared conformance |
