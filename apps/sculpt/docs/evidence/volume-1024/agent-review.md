# Scoped agent technical review

Reviewer claim: `agent:threemd_typescript`. This records agent technical source review and direct inspection of retained images. It is not a human review, GitHub approval, cryptographic signature, or SpecSync review/finalization record. Root owns the official lifecycle decision.

Reviewed Source/Test commit: `619a0efc2fd41b51e02daacbce4e7404546fd8d9`. A read-only `git diff` against this commit was empty for the four peer-owned files listed below. The world files were generated earlier at `6644ed2a9f8bfe5c5475ee3e86b00dc8e786d550`; that provenance remains separate from the later decoder repair.

## Direct source review

The reviewed files were:

- `Sources/RookTool/SculptureVolumeStudy.swift`
- `Tests/RookToolTests/SculptureVolumeStudyTests.swift`
- `Sources/RookTool/SculptureVolumeStudyWorldExport.swift`
- `Tests/RookToolTests/SculptureVolumeStudyWorldExportTests.swift`

I read these files without editing them or running their tests. This review does not independently review the rendering test or interchange driver that I authored, the fixture factories, production rendering code, native editor integration, package settings, or lifecycle records.

The dense probe allocates the exact byte count, writes a nonzero value into every byte, hashes the full live allocation, streams compression to a file, and compares every decoded byte against the original allocation with `memcmp`. Its decoded length and raw/encoded SHA256 checks cover the full payload. The decoder withholds the final four-byte LZFSE marker, drains each prefix chunk, rejects an earlier stream end, requires exact consumption of the final marker, and rejects remaining file bytes. This supports the concatenation/truncation checks without accepting an earlier complete stream through decoder read-ahead.

The resource and memory descriptions match their implementation. System free memory is an instantaneous conservative guard, kernel peaks cover process lifetime, and phase snapshots can miss transient peaks. Nonzero stores establish that the allocation was touched; they do not establish that macOS kept every page resident or uncompressed. Encode/decode timers include hashing and file work. `free` relinquishes the owned allocation without proving immediate operating-system reclamation. The experimental `.voxels.lzfse` file is explicitly separate from Sculpt and ThreeMD containers.

### Findings and repairs

1. The original dense staging cleanup used recursive `removeItem` on a mutable path. Replacing that path before cleanup could remove an unrelated directory. I reported this source finding to root and the owning agent. The frozen repair pins directory descriptors, records device/inode/type identities, uses relative exclusive/no-follow file creation, checks ownership before publication, and cleans only recorded files plus an empty owned directory. The replacement tests preserve a foreign sentinel before encoding and publication. The original blocker is closed in the reviewed source.
2. The original reduced tests used an all-one 16-cube and a 262,144-byte codec fixture, both below the 1 MiB streaming boundary. I reported the missing refill/output-boundary and spatial-pattern coverage. The owner added a deterministic pseudorandom `2 * chunkBytes + 17` fixture that requires encoded output above 2 MiB, plus an independently constructed 64-cube digest covering all eight block values. Those source coverage gaps are closed.
3. Root reported that the first full dense run's decode footprint grew alongside the compressed input size. I did not perform that measurement or independently establish its cause. I directly reviewed the subsequent POSIX repair: one reusable 1 MiB read allocation, one 1 MiB decoded-output allocation, EINTR-aware reads, cancellation checks, and complete stream consumption before the read allocation is overwritten. Full byte/digest/trailing validation remains. The new receipt fields describe read-buffer capacity, successful read-call count and largest returned read, rather than claiming a two-buffer process-memory peak. Actual footprint improvement belongs to root's execution evidence.

Root also reported that the exporter owner was fixing staged-directory replacement and cleanup. I then directly read the frozen exporter and its tests. Writes use the opened staging directory, exclusive/no-follow file creation and synchronization. Publication checks staging identity and uses `renameatx_np(RENAME_EXCL)`, so an existing target is refused. Cleanup uses recorded file identities and an empty-directory removal rather than a recursive walk through a substituted path. The tests cover existing files/directories/links, a substituted staging directory, a racing destination, a substituted file during cleanup, cancellation, and supported-format round trips. I did not execute those tests. This review does not certify atomic protection against arbitrary concurrent same-user filesystem mutation between every ownership check and syscall.

No remaining concrete blocker was found within this source-review scope. This is narrower than approval of the complete product or verification lane. The retained [dense test log](verification/dense-tests.log) and [Metal test log](verification/metal-tests.log) are root-run receipts that I read; they are not tests executed by this reviewer. The full lane and its specification status remain root's responsibility.

## Direct image inspection

I opened all sixteen images below with `view_image` and inspected their actual pixels. These observations are independent of the receipt's pixel-count checks. Every assigned image is nonblank, with coherent shaded models and/or bounds proxies against the dark clear background. I found no visibly corrupt, missing, or entirely blank assigned image.

| Images inspected under `metal/` | Direct observation |
| --- | --- |
| `dense-equivalent-center-narrow-frame-3.png` | A large shaded violet cuboid cluster remains visible inside a dense mint wireframe proxy lattice. The overlapping lines obscure some surfaces. |
| `dense-equivalent-center-wide-frame-0.png` | The populated cluster is very small in the center of the frame and dominated by overlapping proxy lines. It gives little readable model detail. |
| `dense-equivalent-shifted-narrow-frame-0.png`, `dense-equivalent-shifted-narrow-frame-3.png` | Both angles show shaded nearby blocks and surrounding bounds. The asymmetry changes with orbit; the cluster remains coherent and visible. |
| `dense-equivalent-ground-narrow-frame-0.png`, `dense-equivalent-ground-narrow-frame-3.png` | A broad shaded cluster is visible from both angles, surrounded and crossed by proxy bounds. Individual local faces are readable, although line overlap remains heavy. |
| `dense-equivalent-wide-detail-budget-frame-0.png`, `dense-equivalent-wide-detail-budget-frame-3.png` | Both show a small centered wireframe-dominated cluster, similar to the wide-distance view. Raising detail distance does not produce a readable rendering of every placement under the unchanged face budget. |
| `landscape-center-narrow-frame-0.png`, `landscape-center-narrow-frame-3.png` | A small elevated castle-like model with colored caps/base and a separate wireframe proxy are visible. Most of the frame is empty sky; fine structure is limited by object size. |
| `landscape-center-wide-frame-0.png` | A coherent ground grid and separated elevated bounds are visible. Ground detail and island geometry are mostly represented by proxies at this scale. |
| `landscape-shifted-narrow-frame-0.png`, `landscape-shifted-narrow-frame-3.png` | A small green island with pointed tree-like features is visible from two angles. It is recognizable as geometry but too small for close detail inspection. |
| `landscape-ground-narrow-frame-3.png` | The most readable assigned landscape frame: colored ground bands/channels, rows of pointed trees and raised yellow structures are visible among outer and overlapping proxy bounds. |
| `landscape-wide-detail-budget-frame-0.png`, `landscape-wide-detail-budget-frame-3.png` | A small central patch of detailed ground and more colored elevated islands appear among retained proxies. Most of the ground remains a dense bounds lattice; it is not a fully detailed world view. |

Root reported inspecting these four additional images; I did not reopen them and do not claim their direct visual review: `landscape-ground-narrow-frame-0.png`, `landscape-center-wide-frame-3.png`, `dense-equivalent-center-narrow-frame-0.png`, and `dense-equivalent-center-wide-frame-3.png`.

Root reported the 23.189-second Metal probe passing, with twenty PNGs and a [typed receipt](metal/receipt.json); the retained test log confirms that result. The actual pixel inspection above supports successful offscreen image production and the distinction between nearby detail and farther proxies. It does not establish on-screen FPS, responsive native interaction, globally merged chunk surfaces, or GPU rendering of all 1,073,741,824 occupied cells. Small framing and overlapping wireframes are candid readability limitations of these benchmark captures.

## Interchange evidence boundary

I authored and executed the focused SDK-Swift evidence driver, so its [receipt](interchange/receipt.json), [log](interchange/run.log) and [source](interchange/Verify.swift) are execution evidence rather than independent review of my own implementation. It passed two worlds, four original text/binary inputs, twelve producer imports and 144 transfer imports across nine pairs, sixteen per pair. The existing pinned public adapters were used without changing their old catalog or the generated fixtures.

The check establishes exact original canonical/binary bytes and cross-runtime semantic/revision/adoption/edit parity. Sculpt JSON is preserved as opaque ThreeMD content in Node/Rust; their adapters do not interpret the Sculpt world schema. The deterministic root-body edit tests a ThreeMD transaction and is not asserted to remain a valid Sculpt world. Its elapsed time is interchange-driver work, not a storage or rendering benchmark.
