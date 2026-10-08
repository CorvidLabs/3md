---
module: ThreeMD
version: 9
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
  - Sources/ThreeMD/DocumentStorageStructured.swift
  - Sources/ThreeMD/ThreeMDWhitespace.swift
  - Sources/ThreeMD/DocumentComposition.swift
  - Sources/ThreeMD/DocumentCompositionLimits.swift
  - Sources/ThreeMD/DocumentCompositionCodec.swift
  - Sources/ThreeMD/DocumentCompositionJSON.swift
  - Sources/ThreeMD/DocumentFileComposition.swift
  - Sources/ThreeMD/DocumentFileCompositionLedger.swift
  - Sources/ThreeMD/DocumentEditingTypes.swift
  - Sources/ThreeMD/DocumentIdentity.swift
  - Sources/ThreeMD/DocumentEditing.swift
  - Sources/ThreeMD/DocumentCompositionEditing.swift
  - Sources/ThreeMD/DocumentDiagnostics.swift
  - Sources/ThreeMD/FiniteDecimal.swift
  - js/src/index.ts
  - js/src/portable.ts
  - js/src/storage.ts
  - js/src/number.ts
  - js/src/checksum.ts
  - js/src/structured.ts
  - js/src/composition.ts
  - js/src/file-composition.ts
  - js/src/editing.ts
  - rust/src/lib.rs
  - rust/src/storage.rs
  - rust/src/checksum.rs
  - rust/src/structured.rs
  - rust/src/composition.rs
  - rust/src/file_composition.rs
  - rust/src/editing.rs
  - rust/src/diagnostics.rs
  - Sources/ThreeMDInterop/Protocol.swift
  - Sources/ThreeMDInterop/SwiftAdapter.swift
  - Sources/ThreeMDInterop/main.swift
  - Sources/ThreeMDInterop/FileCases.swift
  - Sources/ThreeMDInterop/FileCases+Hardening.swift
  - Sources/ThreeMDInterop/FileBundleHost.swift
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

ThreeMD 2.1 implements SPEC.md 1.2. The general binary container gains payload
kind 2, the structured document payload of SPEC.md section 11.3: length-prefixed
records that decode without building or parsing text, with one canonical
encoding per `Document`, the same accepted documents as the 2.1 `validate`, and
byte-identical writers in all three languages. `.binary(compression:)` now
writes payload kind 2. The new `encodeTextContainer` is deprecated for new
files. It writes payload kind 1, the ThreeMD 2.0 binary bytes, for consumers
that still run ThreeMD 2.0. Readers still open those files. Payload kind 3 is
reserved and rejected.

## Public API

Each symbol appears once. Descriptions identify its owning type and overloads.
Initializers are grouped under `init`. New storage and composition operations
are pure synchronous APIs; they never open paths or resolve URLs.

| Export | Contract |
|--------|----------|
| `Axis` | RawRepresentable, Sendable, Hashable, Codable normalized axis label. |
| `rawValue` | Trimmed and lowercased axis string; DocumentPayloadKind header byte at offset 10. |
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
| `binary` | .binary(compression: DocumentCompression); since 2.1 the version 1 container with payload kind 2, the structured document payload (SPEC.md 11.3). |
| `DocumentDecodeLimits` | Equatable, Sendable bounded resource policy. |
| `maximumEncodedBytes` | Encoded input ceiling. Default is the largest host integer (Swift `Int.max`, Rust `usize::MAX`, TypeScript `Number.MAX_SAFE_INTEGER`). A caller can set a lower positive value. There is no smaller absolute ceiling. |
| `maximumDecodedBytes` | Decoded UTF-8 ceiling checked before allocation. Same default. For payload kind 2 it bounds the canonical text length T (L4) and, at D10, the declared payload length at min(maximumEncodedBytes − 40, 2 × maximumDecodedBytes). That product and difference saturate at the host maximum. |
| `maximumLines` | Physical lines. Same default. |
| `maximumPlanes` | Planes. Same default. |
| `maximumRecordBytes` | Per-line, scalar, preamble, and plane-body bytes. Same default. |
| `standard` | Named default policy. Storage defaults are the largest host integer. Composition and edit defaults keep their documented ceilings. |
| `DocumentStorageCodec` | Pure content-detecting general storage. |
| `containerVersion` | UInt16 binary envelope version 1; DocumentContainerInfo raw container version field. |
| `headerByteCount` | Header length 40 bytes. |
| `isBinary` | isBinary(_ data: Data) -> Bool recognizes complete magic only. |
| `validate` | validate(_ document: Document, limits: DocumentDecodeLimits = .standard) throws; 2.1 keeps the signature and corrects only Rust number spelling and the Swift frozen whitespace set W. |
| `encode` | Storage encode(_:format:limits:) throws -> Data defaults to text, and `.binary` writes payload kind 2; composition encode(_:limits:documentLimits:) emits readable profile. |
| `decode` | Storage Data -> Document from text, payload kind 1 or payload kind 2; composition Data/Document -> DocumentComposition, all throwing with explicit policies. |
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
| `invalidContainer` | Invalid/truncated header, or an invalid structured payload encoding (Var form, undefined flag bit, z form 0, non-canonical number form, key byte order). |
| `unsupportedVersion` | Binary version other than 1. |
| `unsupportedPayloadKind` | Payload kind other than 1 (canonical UTF-8 text) or 2 (structured document); kind 3 is reserved. |
| `unsupportedCompression` | Unknown algorithm identifier. |
| `unsupportedFlags` | Nonzero flags. |
| `nonzeroReserved` | Nonzero reserved header field. |
| `lengthMismatch` | Truncated/trailing/concatenated stream or inconsistent lengths. |
| `checksumMismatch` | Header/payload corruption checksum differs. |
| `compressionUnavailable` | Requested compression absent on platform. |
| `compressionFailed` | System compression fails. |
| `DocumentPayloadKind` | Swift RawRepresentable, Hashable, Sendable, CustomStringConvertible struct for header byte 10 that represents every UInt8, so future kinds stay additive; TypeScript frozen constant object with a number type alias. |
| `canonicalText` | Payload kind 1: canonical UTF-8 3md text behind the binary header (ThreeMD 2.0, SPEC.md 11.1). |
| `structuredDocument` | Payload kind 2: structured document records (ThreeMD 2.1, SPEC.md 11.3). |
| `description` | DocumentPayloadKind name: canonicalText, structuredDocument or reserved(N). |
| `DocumentContainerInfo` | Swift Hashable, Sendable struct, TypeScript readonly interface and Rust non-exhaustive Copy struct of the raw fixed header fields, reported without validating them, the payload or the checksum. |
| `payloadKind` | DocumentContainerInfo payload kind byte; Swift DocumentPayloadKind, TypeScript number. |
| `compression` | DocumentContainerInfo raw compression identifier; compare it with DocumentCompression.rawValue. |
| `flags` | DocumentContainerInfo raw feature flags. |
| `reserved` | DocumentContainerInfo raw reserved field. |
| `encodedPayloadByteCount` | DocumentContainerInfo declared encoded payload byte count; Swift UInt64, TypeScript bigint. |
| `decodedPayloadByteCount` | DocumentContainerInfo declared decoded (uncompressed) payload byte count; Swift UInt64, TypeScript bigint. |
| `checksum` | DocumentContainerInfo declared CRC-32/ISO-HDLC value, not verified by inspection. |
| `supportedPayloadKinds` | Payload kinds this release decodes, canonicalText and structuredDocument: Swift Set of DocumentPayloadKind, TypeScript frozen readonly number array [1, 2]. |
| `containerInfo` | containerInfo(_ data: Data) throws -> DocumentContainerInfo? reads at most the first 40 bytes; nil (TypeScript null) without the binary magic; invalidContainer when the magic is present and fewer than 40 bytes exist. |
| `encodeTextContainer` | Deprecated for new files. encodeTextContainer(_:compression:limits:) throws -> Data writes payload kind 1, byte-identical to the ThreeMD 2.0 `.binary` output, with the 2.0 binary writer's validation and error order; TypeScript takes optional compression, limits and AbortSignal. Readers still open it. |
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
| `PAYLOAD_KIND_CANONICAL_TEXT` | Rust payload kind 1 constant, canonical UTF-8 text. |
| `PAYLOAD_KIND_STRUCTURED_DOCUMENT` | Rust payload kind 2 constant, structured document records. |
| `SUPPORTED_PAYLOAD_KINDS` | Rust array of the two payload kinds this release decodes, [1, 2]. |
| `container_info` | Rust header-only inspection: Ok(None) without the binary magic, Err(InvalidContainer) when the magic is present and fewer than 40 bytes exist. |
| `encode_text_container` | Rust payload kind 1 writer with explicit compression, limits and OperationOptions, byte-identical to the 2.0 encode with Binary and with its errors. |
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
| `adopt_composition_entries` | Rust additive adoption that returns the adopted entries without building the graph, so a caller constructing it with `DocumentComposition::new` receives the specific composition error, for example at the exact reference attribute bound. |
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
| `canonicalNumber` | Internal TypeScript Swift-compatible finite decimal spelling, moved to the side-effect-free js/src/number.ts and re-exported from storage.ts. |
| `BoundedTextWriter` | Internal TypeScript byte-budgeted canonical text accumulator. |
| `frozenReference` | Internal TypeScript copied immutable reference. |
| `frozenEntry` | Internal TypeScript copied immutable definition. |
| `crc32` | Envelope checksum for every payload kind, not authenticity. Rust keeps it crate-internal in checksum.rs. TypeScript exports crc32 from js/src/checksum.ts for the storage codec. |
| `crc32Update` | Internal TypeScript slicing-by-16 CRC step over a half-open byte range. The register is the raw state, before the final XOR. |
| `crc32UpdateBytes` | Internal TypeScript byte-at-a-time CRC step, the reference the slicing update matches. |
| `containerChecksum` | Internal TypeScript CRC of header bytes 0..<36 followed by the encoded payload. |
| `validateRecords` | Internal TypeScript record-limit and lone-surrogate check used before a kind-2 writer merges equivalent keys. |
| `structuredProbe` | Internal TypeScript test counter of Phase Q parses. Production decode does not read it. |
| `validateUTF8` | Internal TypeScript fatal UTF-8 check of one complete byte range, used by chunked string validation. |
| `decodeUTF8` | Internal TypeScript UTF-8 decode of one complete byte range. |
| `compareCodePoints` | Internal TypeScript code-point order, equal to raw UTF-8 byte order for well-formed strings. |
| `StructuredMetrics` | Internal TypeScript canonical-text size metrics for one structured payload. |
| `readStructured` | Internal TypeScript kind-2 payload reader over a half-open byte range. |
| `numberForm` | Internal TypeScript canonical number form: 1 integer, 2 binary32, 3 binary64. |
| `writeStructuredPayload` | Internal TypeScript kind-2 payload writer. Bytes 0..<40 of the returned buffer are left zero for the header. |
| `cancellation_hook` | Crate-internal Rust test hook that can fail a storage operation at a chosen check. Absent outside tests. |
| `arm` | Crate-internal Rust function that arms cancellation_hook at a check index. |
| `checks` | Crate-internal Rust count of cancellation_hook observations. |
| `MAGIC` | Crate-internal Rust binary magic bytes, 3mdbin followed by CR LF. |
| `CHECKED_CHARS_STEP` | Crate-internal Rust cancellation stride for long character scans, 65,536. |
| `CheckedChars` | Crate-internal Rust iterator that charges cancellation while reading characters. |
| `update` | Crate-internal Rust slicing-by-16 CRC update. |
| `container` | Crate-internal Rust checksum of the 36 header bytes and the encoded payload. |
| `parse_data` | Crate-internal Rust bounded UTF-8/text decode and Unicode key reconstruction. |
| `position_key` | Crate-internal Rust exact finite coordinate set key. |
| `normalized_key` | Crate-internal Rust bounded NFC key normalization. |
| `canonical_keys` | Crate-internal Rust normalized scalar key ordering. |
| `canonical_number` | Crate-internal Rust Swift-compatible finite decimal spelling; 2.1 emits the shortest round-trip digits, fixing 92 powers of two that 2.0 misspelled. |
| `swift_double` | Crate-internal Rust shortest decimal formatter with Swift notation threshold and ties-to-even spelling; it uses an explicitly rounded spelling only when that spelling parses back to the same value. |
| `trimFoundationWhitespace` | Internal TypeScript linear scan using the frozen whitespace set W of SPEC.md 11.3.6. |
| `isFoundationWhitespace` | Internal TypeScript predicate for the frozen whitespace set W; no newline/BOM trimming. |
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
Each storage field is a positive integer up to the host maximum. A non-positive
value is invalidLimits. JavaScript also rejects a value above
Number.MAX_SAFE_INTEGER. DocumentCompositionLimits takes
all eight maximum-properties above with their defaults; references and attribute
limits can be zero, while other limits are positive. DocumentReference defaults
attributes to [:]; DocumentEntry defaults references to [].
DocumentComposition(rootID:entries:limits:documentLimits:) throws defaults both
policies to .standard and validates every definition before returning.
DocumentPayloadKind(rawValue:) accepts every UInt8, including reserved kinds.
DocumentContainerInfo has no public initializer: values come only from
containerInfo, and the Rust struct is `#[non_exhaustive]`.

Editing snapshot constructors validate source values and canonicalize revision text. DocumentPatch and CompositionPatch
constructors take expectedRevision and ordered operations without executing them. DocumentEditLimits takes the four
maximum-properties above; payload/diagnostic limits are positive. DocumentHeader captures a Document or explicitly takes
version, axis and optional title/metadata/preamble. Diagnostic/report constructors retain the evidence supplied by callers.
Codable editing transport is not a bounded streaming JSON reader: callers must cap untrusted wire bytes before decoding.

### Portable surfaces

Portable API contracts: TypeScript exports the analogous storage/composition/editing types through `js/src/index.ts`, with Uint8Array storage, named policy options and optional AbortSignal as the last argument. Its snapshots and graphs copy/freeze values, and fromJSON reconstructs and validates exact revision pairs. `stableID(value)` reads the namespaced attribute without altering existing Plane/Document interfaces. Rust exposes storage, composition, editing and diagnostics modules plus model/policy/error reexports. Operations accept policies and `OperationOptions`; private snapshot/graph fields use immutable accessors. New Rust canonical storage uses pinned unicode-normalization for NFC scalar ordering, rejects ambiguous canonically equivalent keys in direct BTreeMap values and reconstructs first-spelling/last-value behavior while decoding source. The interchange follow-up aligns existing Unicode whitespace and source-key grammar interpretation, and repairs lossless legacy scalar quoting. Public signatures and frozen syntax remain. Legacy spelling may vary while canonical bytes and reimported semantics agree. The development coordinator uses processes only in its separate executable target; the library remains pure.



Cancellation is cooperative. JavaScript work is synchronous, so an AbortSignal dispatched on the same event loop cannot preempt it mid-call; callers can pre-cancel or schedule work and cancellation in their own execution context. No library worker or external service is created. Rust's shared atomic flag can be canceled from another thread. Both ports check bounded work and return no partial result.

### Payload kinds and binary writers (ThreeMD 2.1)

The 2.1 additions are additive: no public enum gains a case, no existing
signature changes, and no error code is added. `DocumentStorageFormat`,
`DocumentCompression`, `DocumentStorageError`, `DocumentDecodeLimits`, the
composition types and their error enums stay as in 2.0, so exhaustive `switch`
and `match` statements compiled against 2.0 keep compiling. There is no lazy or
partial-access API; the only inspection reads the 40-byte header.

The one behavior change is that storage encode with `.binary(compression:)`
(Rust `DocumentStorageFormat::Binary(c)`) writes payload kind 2. Its accept or
reject decision equals `.text` and the 2.1 `validate`, except that kind 2
requires the file, not the canonical text, to fit `maximumEncodedBytes`; for an
invalid document the reported code follows the structured precedence of SPEC.md
11.3.9 and can differ from `.text`. Storage decode accepts text, payload kind 1
and payload kind 2 and reports `unsupportedPayloadKind(k)` for kinds 0 and 3 to
255. Composition decode and the linked-file resolver accept text, kind-1 and
kind-2 envelopes and children through storage decode, and refuse kind 3 with
`unsupportedPayloadKind(3)`. Encoding `DocumentCompositionCodec.document(for:)`
with `.binary` yields a kind-2 envelope; composition encode still writes the
readable profile text. `isBinary` is unchanged.

The header-only inspection is Swift `DocumentStorageCodec.containerInfo(_:)`,
TypeScript `DocumentStorageCodec.containerInfo(data)` and Rust
`storage::container_info(data)`, with fields `containerVersion`, `payloadKind`,
`compression`, `flags`, `reserved`, `encodedPayloadByteCount`,
`decodedPayloadByteCount` and `checksum` (Rust spells them in snake case; Swift
uses UInt16, DocumentPayloadKind, UInt8, UInt32 and UInt64 values; TypeScript
uses numbers and bigint lengths). The kind-1 writer is Swift
`encodeTextContainer(_:compression:limits:)`, TypeScript
`encodeTextContainer(document, compression?, limits?, signal?)` and Rust
`storage::encode_text_container(document, compression, limits, options)`.
Decoding a 2.0 kind-1 file and encoding it with `.binary` gives kind 2 with an
identical `Document`; `encodeTextContainer` reproduces the 2.0 bytes exactly.

TypeScript adds exactly two root exports, `DocumentPayloadKind` and the type
`DocumentContainerInfo`; the structured reader, writer and slicing CRC modules
are internal. Its decoded values are the plain objects of the 2.0 bounded
decoder (document properties `version, axis, title, metadata, preamble,
planes`, plane properties `z, label, x, y, attributes, body`, created in that
order, `null` for absent values, maps created with `Object.create(null)` and
filled in stored byte order, nothing frozen); equality ignores key enumeration
order. The TypeScript writer merges canonically equivalent keys (first
spelling, last value) as the 2.0 `canonicalStrings` does; when a map actually
contains equivalent keys it first runs the 2.0 `validateRecords` check on the
unmerged input. It rejects a lone surrogate with `invalidDocument`, never a
U+FFFD substitution. Rust re-exports `DocumentContainerInfo`,
`PAYLOAD_KIND_CANONICAL_TEXT`, `PAYLOAD_KIND_STRUCTURED_DOCUMENT` and
`SUPPORTED_PAYLOAD_KINDS` from the crate root and rejects a direct map with
canonically equivalent keys, as in 2.0.

### Public file composition APIs

| Export | Contract |
|--------|----------|
| `DocumentFileSource` | Explicit normalized project path plus supplied encoded document/profile bytes; never a filesystem read. |
| `data` | Caller-supplied Data/Uint8Array/Vec bytes for file composition. |
| `DocumentFileReference` | One printable ASCII glyph and relative source filename. |
| `glyph` | Host-defined printable ASCII ledger character. |
| `source` | Relative child filename; bundled profile source remains canonical embedded document text. |
| `DocumentFileCompositionResult` | Validated portable graph plus normalized root and contributing-path index. |
| `rootPath` | Normalized project-relative root filename. |
| `fileRootIDs` | Normalized filename to generated root-definition ID mapping. |
| `resolvedPaths` | Reachable filenames sorted by Unicode scalar order. |
| `DocumentFileCompositionError` | Typed file-intake failures; wrapped storage/graph/cancellation failures retain their codes. |
| `DocumentFileComposition` | Pure ledger parsing, relative path resolution and supplied-byte graph bundling. |
| `ledger` | Parse strict 3md-files metadata to glyph-ordered filename references. |
| `resolvePath` | Normalize a relative filename against its containing file without project escape. |
| `resolve` | Discover supplied reachable files, preserve nested sharing and produce a self-contained graph under existing policies. |
| `invalidPath` | Absolute, escaping, forbidden delimiter/control or malformed project path. |
| `duplicatePath` | Multiple source inputs normalize to the same project path. |
| `invalidLedger` | Malformed JSON, duplicate keys or nonstring ledger values. |
| `invalidGlyph` | Key is not one printable ASCII character. |
| `missingFile` | A reachable normalized filename has no supplied bytes. |
| `inputLimit` | Supplied count/path bytes, reachable input bytes or standalone ledger/path policy exceeded. |
| `DocumentFileCompositionErrorCode` | TypeScript stable file-intake error code union. |
| `file_composition` | Rust pure supplied-file resolver module; ledger and resolve take explicit OperationOptions/policies. |
| `resolve_path` | Rust relative path normalization with explicit cancellation options. |

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
   Header/version/kind/lengths/CRC follow SPEC.md section 11.1 and its
   validation order D1 to D14. The payload kind is 1 (canonical text) or 2
   (structured document, SPEC.md 11.3) behind the same container, magic and CRC.
   Uncompressed storage is portable; system LZFSE is optional. CRC is not
   authenticity.
4. Declared decoded size is checked against the payload kind's bound before
   allocation (D10): `maximumDecodedBytes` for kind 1, and
   min(maximumEncodedBytes − 40, 2 × maximumDecodedBytes) for kind 2. Exact
   stream termination, output size and full input consumption are required.
   Errors yield no partial data.
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
9. Payload kind 2 has exactly one uncompressed encoding per `Document`, and
   readers reject every other byte sequence: for any uncompressed kind-2 input,
   if decode succeeds, re-encoding with `.binary(.none)` under the same limits
   returns the input bytes. A kind-2 file decodes exactly when its `Document`
   passes the 2.1 `validate` under the same limits and the uncompressed
   container fits `maximumEncodedBytes`; the decoded value equals the bounded
   text decode of the document's canonical text. Readers establish this with
   local rules and exact arithmetic, building text only for the Phase Q
   directive check of keys that contain quotes.
10. With compression 0, the Swift, TypeScript and Rust writers produce
    byte-identical kind-2 files for every `Document` that all three accept.
    Maps with canonically equivalent keys and LZFSE output are outside this
    guarantee and never appear in cross-port vectors.
11. Kind-2 keys are stored in strictly increasing raw UTF-8 byte order (equal to
    Unicode code point order, not UTF-16 order), keep their spelling, and a map
    with canonically equivalent keys is `invalidDocument`. Strings are stored
    verbatim, without normalization or trimming. Kind-2 bytes never depend on
    Unicode data; the cross-port guarantee covers strings of code points
    assigned in Unicode 13.0 on the pinned CI toolchains (SPEC.md 11.3.15).
12. Trimming, blank-line and edge-whitespace tests use the frozen whitespace set
    W in every port: U+0009, U+0020, U+00A0, U+1680, U+2000 to U+200B, U+202F,
    U+205F and U+3000 (19 scalars). U+0085, U+000B, U+000C, U+180E, U+2028 and
    U+FEFF are not in W. Swift replaces the platform's
    `CharacterSet.whitespaces` with this set; TypeScript and Rust already use it.
13. Canonical storage numbers use the shortest round-trip spelling in every
    port. Rust `canonical_number` is fixed in 2.1 to match TypeScript and Swift
    for every signed power of two (2.0 misspelled 92 of them); the 2.1 Rust
    `validate` therefore accepts those values.
14. `encodeTextContainer` is the 2.0 binary writer, unchanged, including its
    validation and error order. Every 2.0 `.3mdb` file stays readable and
    byte-unchanged, and a 2.0 reader stops at the payload kind with
    `unsupportedPayloadKind(2)` before it computes the CRC.
15. Payload kind 3 is reserved for a structured composition payload; no constant
    names it, and storage decode, composition decode and the file resolver
    report `unsupportedPayloadKind(3)`. Compositions and linked-file bundles keep
    the readable `3md-composition-1` profile, whose envelope may be stored as
    kind 2.

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

Given the document of SPEC.md 11.3.17 example 1 (144 bytes of canonical text)
When Swift, TypeScript and Rust encode it with .binary(compression: .none)
Then each writes the same 113-byte kind-2 file with CRC-32 0x8A5B3B70,
containerInfo reports version 1, kind 2 and equal 73-byte lengths,
and decoding it returns the document that decoding its canonical text returns.

Given a committed ThreeMD 2.0 kind-1 .3mdb file
When a 2.1 reader decodes it and encodeTextContainer re-encodes the result
Then the Document equals the 2.0 decode and the bytes equal the original file.

Given a ThreeMD 2.1 kind-2 file
When a ThreeMD 2.0 reader decodes it
Then it reports unsupportedPayloadKind(2) at header byte 10, before the CRC.

Given a kind-2 file whose metadata keys are stored in NFC text order
(`z` before a decomposed `é`) instead of raw UTF-8 byte order
When any port decodes it
Then decoding fails with invalidContainer.

Given a container that declares payload kind 3
When storage decode, composition decode or the file resolver reads it
Then it is refused with unsupportedPayloadKind(3).
```

## Error Cases

The export table records each typed failure. Storage rejects excess resources,
invalid UTF-8/text/direct values, malformed or unsupported headers, corruption,
unavailable compression and inexact/trailing streams. Composition rejects
unsafe/duplicate IDs, absent roots/targets, cycles, every budget excess and
malformed/unsupported profiles. Cancellation is distinct. Existing parser
errors retain their stable cases and metadata.

Payload kind 2 adds no error code. It maps onto the existing
`DocumentStorageError` codes of SPEC.md 11.3.12: truncated fields, framing,
count and trailing bytes are `lengthMismatch`; Var form, undefined flag bits,
z form 0, non-canonical number forms and key byte order are
`invalidContainer`; ill-formed UTF-8 is `invalidUTF8`; record limits are
`oversizedRecord`; the D10 bound and a canonical text length over
`maximumDecodedBytes` are `oversizedOutput`; `tooManyLines` and
`tooManyPlanes` keep their meaning; an input over `maximumEncodedBytes`, a
writer payload over `maximumEncodedBytes − 40` and `maximumEncodedBytes < 40`
on write are `oversizedInput`; representability failures are
`invalidDocument(detail)`, whose detail text is not compared across languages.
Only two Swift descriptions change: `invalidContainer` becomes "The binary
container or its structured payload encoding is invalid." and
`unsupportedPayloadKind` becomes "Unsupported 3md binary payload kind N for this
operation."

| Entry point | Error type | Kind-2 codes |
|-------------|------------|--------------|
| Storage decode | `DocumentStorageError` in all three languages | Every code of SPEC.md 11.3.12, plus cancellation |
| Storage encode with `.binary` | `DocumentStorageError` | `invalidLimits`, `oversizedInput`, the reader's codes from the writer self-check, `compressionUnavailable`, `unsupportedCompression` (TypeScript only), cancellation |
| `encodeTextContainer` | `DocumentStorageError` | Exactly the 2.0 `.binary` codes |
| `containerInfo` | `DocumentStorageError` | `invalidContainer` only |
| Composition decode | Swift and TypeScript: `DocumentCompositionError` for `profileBytesExceeded`, profile and graph codes, and `DocumentStorageError` for other storage codes; Rust: `DocumentCompositionError` with storage codes wrapped as `Storage(code)` | As 2.0: `oversizedInput`, `oversizedOutput` and `oversizedRecord` from the envelope become `profileBytesExceeded`; kind 3 is `unsupportedPayloadKind(3)` |
| File resolver | As 2.0 | Children of kind 1 and 2 accepted; kind 3 refused with `unsupportedPayloadKind(3)` |

Cancellation stays Swift `CancellationError`, the TypeScript AbortSignal reason
and Rust `DocumentStorageError::Cancelled`, and a cancelled or failed operation
returns no document and no encoded bytes.

## Dependencies

- Swift Foundation for text, Data, JSON and localized errors.
- Conditional Apple system Compression for optional LZFSE; no third-party Swift
  dependency or CryptoKit requirement. The original text surface stays portable.
- TypeScript adds no production dependency. Rust adds exact unicode-normalization 0.1.25 for new canonical key comparison, locked with its small dependencies. Existing text parsing/serialization behavior is unchanged.
- ThreeMD 2.1 adds no runtime dependency in any language. Rust keeps
  `unicode-normalization = "=0.1.25"` as its only dependency and adds
  `#![forbid(unsafe_code)]`. The fast CRC is table-driven code in each port,
  with no hardware intrinsics required.

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
| 6 | 2026-10-05 | guarantee-portable-cross-language-document-and-composition-interchange-with-a-nine-pair-public-api-verification-matrix: Guarantee portable cross-language document and composition interchange with a nine-pair public API verification matrix |
| 8 | 2026-10-05 | add-linked-file-composition-with-a-glyph-ledger-recursive-supplied-file-resolution-and-portable-self-contained-bundling: Add linked file composition with a glyph ledger recursive supplied-file resolution and portable self-contained bundling in all three languages |
| 9 | 2026-10-06 | harden-linked-composition-parity-across-swift-typescript-and-rust-after-2-0-0: Harden linked composition parity across Swift TypeScript and Rust after 2.0.0 |
