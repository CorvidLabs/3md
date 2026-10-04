---
change: implement-generic-binary-storage-and-document-composition-with-specsync-6-and-trust-1-2-2
artifact: requirements
---

# Requirements

## Added durable requirements

### REQ-ThreeMD-021
General Document values SHALL round-trip through a separately versioned binary envelope with portable uncompressed payloads and optional conditional Apple LZFSE. Existing text grammar, Parser/Serializer signatures, version leniency and duplicate-key semantics SHALL remain unchanged.

### REQ-ThreeMD-022
Storage SHALL validate finite unique positions, serializable values, exact lengths, CRC32, full stream consumption, allocation bounds and cancellation. Invalid headers, unsupported backends, corrupt/truncated/trailing/concatenated streams and oversized input SHALL fail without partial output.

### REQ-ThreeMD-023
Composition SHALL store one root ID and named Document definitions with explicit in-memory references, storing shared definitions once. All nodes, including unused definitions, SHALL satisfy unique safe IDs, existing targets, acyclic traversal and bounded depth, bytes, reference records and traversal occurrences. No filesystem/network/process access SHALL be performed.

### REQ-ThreeMD-024
Composition SHALL use existing 3md syntax with a strictly decoded versioned JSON manifest. Generic reference attributes and mixed axes SHALL be preserved; no voxel or automatic flattening semantics are imposed. The same profile Document SHALL be supported by binary storage.

### REQ-ThreeMD-025
SpecSync 6.0.0 workflow-v2 definition approval and later actual verification/review/finalization evidence SHALL govern this work. Immutable Trust 1.2.2 SHALL retain the native cross-language lane and existing risk/provenance policies without weakening them.

Storage defaults/hard bounds: encoded/decoded64MiB,100000lines,65536planes,defaultrecord8MiB with explicit ceiling64MiB. Composition lowering-only defaults:1024definitions,16384references,64-node depth,16MiB unique canonical source,1000000traversal occurrences per entry subtree,20MiB profile,64attributes and16KiB UTF8attributes per reference. New capability is Swift-first; other implementations retain existing text conformance.
