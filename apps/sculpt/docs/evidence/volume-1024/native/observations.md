# Native Skyreach walkthrough

Root performed this native check with the existing adopted app at `/private/tmp/sculpt-3md2-adoption-20261005/dist/Rook.app`. The product editor and renderer source remained unchanged relative to that adoption checkout. The new 1024-cubed fixtures and development study tools are separate changes; this observation is not a native check of a newly packaged case-study app.

Using the actual NSOpenPanel, root selected [landscape-1024.portable.3mdb](../worlds/landscape-1024.portable.3mdb). The window displayed `Skyreach 1024-cubed landscape` and 280 placements.

| Focus | Visible | Full detail | Bounds proxies | Outside render distance | Omitted by capacity |
| --- | ---: | ---: | ---: | ---: | ---: |
| 0, 960, 0 | 17 | 6 | 11 | 263 | 0 |
| 512, 960, 512 | 66 | 20 | 46 | 214 | 0 |

Root entered the second focus in the native coordinate fields and selected Go. Dragging the actual Metal canvas changed the orbit. These observations establish native opening, focus navigation and interactive orbit with the existing bounded renderer. They do not measure on-screen FPS or establish that all world occupancy was drawn simultaneously.

Native Save world produced [landscape-native-save.3md](landscape-native-save.3md), a 2,249,314-byte native `ascii-world-1` file. The saved file is byte-identical to [landscape-1024.3md](../worlds/landscape-1024.3md), including its reusable models and placement records. This comparison concerns the native scene representation. The generated portable-copy revision checks are recorded separately by the world exporter.

The documentation agent verified the save with:

```text
cmp docs/evidence/volume-1024/native/landscape-native-save.3md docs/evidence/volume-1024/worlds/landscape-1024.3md
shasum -a 256 docs/evidence/volume-1024/native/landscape-native-save.3md docs/evidence/volume-1024/worlds/landscape-1024.3md
wc -c docs/evidence/volume-1024/native/landscape-native-save.3md
```

`cmp` exited zero. Both SHA-256 values were `753a593c8557c313225e078cc29513590958b8d8716c4f5c24150acd21b2552a`; the save size was 2,249,314 bytes.

The native screenshot was shown inline during the walkthrough. No persistent native screenshot was captured for this record. PNGs in the neighboring Metal benchmark directory are synchronized offscreen captures from that benchmark and are not screenshots of this walkthrough.

Native interaction facts above are root's agent observations. File equality and byte-size checks are this documentation agent's read-only evidence. Neither is an independent human review, GitHub approval, permitted signature or release claim.
