---
hi: 1
families: [REUSE]
---

# Reuse

## Intent

I want one self-contained file to hold named documents I can point at many times, and I want a glyph ledger of local ThreeMD files that resolves from bytes I supply.

## Criteria

- **REUSE-1**  I can put several named documents in one self-contained file and point at the same name more than once, with that document stored once.
- **REUSE-2**  Each named document keeps its own axis.
- **REUSE-3**  I can put attributes on a reference and they stay opaque. The format does not turn them into voxels, placements, or scene nodes.
- **REUSE-4**  Resolving a self-contained file uses the bytes already stored in it, and the library does not read the filesystem or the network.
- **REUSE-5**  I get a self-contained composition only when its references resolve inside that file under the id, target, cycle, depth, and work checks, and those checks include a definition nothing points at.
- **REUSE-6**  I can name local ThreeMD files from a 3md-files ledger that maps one printable ASCII glyph to a relative filename.
- **REUSE-7**  I supply the bytes for those files, resolution follows the references they contain, and supplying new child bytes on a later resolve refreshes the linked snapshot.
- **REUSE-8**  An invalid path, a cycle, a missing file, or a limit overflow is refused, and the document I already have stays as it was.
- **REUSE-9**  I can store the 3md-composition-1 profile as readable text or as payload kind 2.
- **REUSE-10**  I can bundle a resolved ledger into that self-contained profile, and the bundle does not need the source folder afterward.
- **REUSE-11**  Gallery cards show the text and do not expand composition references. In the viewer I can open a composition profile and switch to another entry.
