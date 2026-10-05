---
change: implement-generic-binary-storage-and-document-composition-with-specsync-6-and-trust-1-2-2
artifact: design
---

# Design

## Binary v1

New DocumentStorage.swift, DocumentStorageCodec.swift, DocumentStorageValidation.swift and DocumentStorageCompression.swift. Public DocumentCompression(UInt8 none0/lzfse1), DocumentStorageFormat(text/binary), DocumentDecodeLimits, DocumentStorageError; codec encode/decode/isBinary/validate. APIs are synchronous throwing and Sendable, permitting caller-chosen executors.

40-byte little-endian header: magic "3mdbin\\r\\n" bytes0..<8, UInt16 version1@8, UInt8 UTF8Document payloadkind1@10, compression@11, UInt32 flags0@12/reserved0@16, UInt64 encodedbytes@20/decodedbytes@28, UInt32 CRC@36. CRC-32/ISO-HDLC covers header0..<36 then encoded payload; reflected polynomial EDB88320, init/finalxorFFFFFFFF; check123456789=CBF43926. It detects corruption, not authorship. Marker is disjoint from Rook's voxel 3MDB header.

New storage canonical source writer quotes scalars to preserve valid single-quote literals, leaving Serializer untouched. Programmatically created Documents are validated. Apple LZFSE imports are conditional; unsupported platforms report unavailable backend. Exact one stream, EOF, decoded count and input exhaustion are mandatory. Cancellation propagates.

## Composition v1

New DocumentComposition.swift, DocumentCompositionLimits.swift, DocumentCompositionCodec.swift and DocumentCompositionJSON.swift. Public immutable DocumentReference(targetID,attributes), DocumentEntry(id,document,references), DocumentComposition(rootID,entries,limits,documentLimits), rootEntry/entry(id:), limits and errors. Codec document(for:), encode, decode(Data/Document) and isComposition(Document).

Outer Document: version0.1,axislayer,metadata profile=3md-composition-1, onez0plane labelledComposition; body fencedJSON manifest schema/rootID/entries. Entrykeys:id/source/references; referencekeys:targetID/attributes. Duplicate/unknown keys fail. IDs1-64 ASCII [A-Za-z0-9][A-Za-z0-9_-]*; library sorts byID,referenceorder preserved. Definitions encode once with shared storage text writer. Explicit20MiB outer record override handles escaped JSON while embedded documents keep supplied policy.

No automatic imports, executable content, axis coercion, geometry, voxel palette, rotation, sparse-world allocation or Markdown flattening. In-memory lookup and validated graph inspection only.
