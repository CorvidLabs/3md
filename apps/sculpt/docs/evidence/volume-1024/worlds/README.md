# Reusable 1024-cubed study worlds

These deterministic fixtures share a 1024 by 1024 by 1024 address domain, containing 1,073,741,824 possible cell addresses. Each referenced model is 64-cubed. Individual editable models retain the production limit of 256 cells per axis. The ordinary example gallery is unchanged.

[worlds.json](worlds.json) records the generated file sizes, SHA-256 values, counts and single-run CPU preparation, capture, encode and decode wall times. Generation validates the native world roundtrip and both portable roundtrips. Portable checks require scene equality and exact canonical revision equality.

| World | Placements | Library models | Unique voxel bytes | Occupied cells across placements |
| --- | ---: | ---: | ---: | ---: |
| Solid 1024 | 4,096 | 2 | 262,144 | 1,073,741,824 |
| Skyreach landscape | 280 | 9 | 2,097,152 | 28,057,022 |

The solid world repeats one solid 64-cubed model on a 16 by 16 by 16 lattice. Its disjoint chunk boxes fill every cell address exactly once. Its second library model is the required tile root, which is not placed in the world. Constructing or opening this sparse representation does not allocate a dense 1 GiB voxel buffer. The separate [dense study receipt](../dense-receipt.json) describes that physical allocation experiment.

Skyreach uses eight shared leaf models: meadow, forest, river and bridge, castle, mountain ridge, irrigated terraces, floating island and sky citadel. Its ninth library model is the required tile root. There are 256 ground chunks at Y=960 and 24 elevated chunks at Y=0, 256, 512 and 768. Y grows downward. All placements have distinct aligned origins and zero rotation. Their 64-cubed boxes are disjoint, so summing each referenced model's occupied count gives actual world occupancy without counting overlaps. Skyreach's 28,057,022 occupied cells are separate from its 1,073,741,824-cell address domain.

Unique voxel bytes count the stored UInt8 volumes of leaf models only. They exclude placement records, text encoding, headers, identities and the required root's resolved-volume budget. Including the root, resolved library volumes are 524,288 bytes for the solid world and 2,359,296 bytes for Skyreach, both below the existing 64 MiB library budget. These counts are not process-memory measurements.

| File | Bytes | Representation |
| --- | ---: | --- |
| [solid-1024.3md](solid-1024.3md) | 608,772 | Native `ascii-world-1` |
| [solid-1024.portable.3md](solid-1024.portable.3md) | 671,771 | Readable ThreeMD composition profile |
| [solid-1024.portable.3mdb](solid-1024.portable.3mdb) | 671,811 | Uncompressed portable binary envelope |
| [landscape-1024.3md](landscape-1024.3md) | 2,249,314 | Native `ascii-world-1` |
| [landscape-1024.portable.3md](landscape-1024.portable.3md) | 2,229,495 | Readable ThreeMD composition profile |
| [landscape-1024.portable.3mdb](landscape-1024.portable.3mdb) | 2,229,535 | Uncompressed portable binary envelope |

Native files embed the existing Sculpt world and reusable-model library. Portable files use the upstream `3md-composition-1` profile, including the Sculpt `ascii-world-2` root with exact Int64 placements, reusable model entries and namespaced identities. The binary copies wrap the same canonical profile content with an uncompressed envelope. Their additional 40 bytes are envelope overhead; these files do not demonstrate compression or an indexed voxel representation. All three representations are self-contained and preserve reusable scene structure.

Generate a new directory with a release build of `RookTool volume-worlds --output /absolute/new-directory`. The development exporter prepares all six copies and the receipt in a private staging directory, then publishes the complete directory with an exclusive rename. Existing target entries are refused. Failure cleanup checks owned file and directory identities and does not recursively remove replacement paths. No dense world expansion is needed to generate these files.

The [native observations](../native/observations.md) document opening Skyreach in the already packaged adopted app. The [Metal receipt](../metal/receipt.json) and its PNGs are separate bounded offscreen benchmark evidence. Instanced meshes retain chunk boundaries; no global face merging, full-billion-cell draw, or on-screen frame-rate claim follows from these fixtures.
