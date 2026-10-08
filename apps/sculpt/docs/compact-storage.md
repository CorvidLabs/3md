# Compact sculpture storage

Save and Cmd-S write a compact `.3mdb` sculpture. File → Save readable 3md, Cmd-Shift-S, and the command palette write the existing `.3md` text schema instead. Open accepts both through a user-selected native file panel. The extension and content type distinguish binary data from readable Markdown.

Compact storage is specific to Sculpt.3md. It does not change the ThreeMD text grammar 1.0 or claim to be an upstream binary standard. Both storage formats reconstruct the same title, dimensions, palette and cells. Camera, selection, appearance and derived occupancy caches are not stored. The gallery's five existing interchange formats remain readable 3md, PNG, GIF, MP4 and OBJ.

The Swift implementation uses Apple's Compression framework with LZFSE and CryptoKit SHA256. It compresses the raw voxel sequence rather than Markdown, so reopening does not allocate or parse text planes. There are no added package dependencies, processes, network connections or file entitlements.

Version 1 has this layout. Integers are little endian; voxel order is Z slices, then Y rows, then X columns.

| Byte offsets | Value |
| --- | --- |
| 0–7 | Magic `33 4D 44 42 0D 0A 1A 0A` |
| 8–9 | UInt16 version, `1` |
| 10 | Compression identifier, `1` for LZFSE |
| 11 | Reserved, `0` |
| 12–17 | UInt16 width, height, depth |
| 18–19 | UInt16 title byte count |
| 20–23 | UInt32 uncompressed voxel count |
| 24–27 | UInt32 compressed stream byte count |
| 28–59 | SHA256 of bytes 0–27, title, then uncompressed voxels |
| 60 onward | Printable ASCII title followed by one complete LZFSE stream |

Each axis is 1–256, the title is 1–80 printable ASCII bytes, and the voxel count must equal width × height × depth. Encoded files are bounded at 20 MiB. Decompression checks the output budget before appending each chunk, requires exactly the declared count, and rejects trailing or incomplete streams. It withholds the final four-byte LZFSE end marker while draining buffered output, preventing SDK read-ahead from concealing a concatenated stream. The marker is defined by the [LZFSE format source](https://github.com/lzfse/lzfse/blob/master/src/lzfse_internal.h). Unsupported versions/compression, invalid lengths, invalid glyphs and checksum mismatches are errors. The checksum detects corruption; it does not authenticate authorship. Refused input leaves the open document unchanged.

Save preparation runs on a detached Swift task from an immutable snapshot. Cancel, replacement and disappearance invalidate obsolete preparation. The native save panel writes only after the person chooses a destination. Only a successful save for the same document generation marks its captured snapshot saved; newer edits stay dirty.

The development CLI autodetects either format on inspection or input. Apply chooses output format from `.3md` or `.3mdb`, validates the entire batch, and atomically publishes a new file without overwriting an existing path. See [document commands](../Examples/agent-commands.md).

Measurements and verification receipts are retained in [compact-storage evidence](evidence/compact-storage/verification-notes.md). Timing describes codec work in the measured build and excludes file I/O and rendering.
