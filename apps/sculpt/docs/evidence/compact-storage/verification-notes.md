# Compact storage verification

Request: save large sculptures efficiently in binary form while preserving readable 3md. SCULPTURE-28 records this scope. The new `.3mdb` format is native sculpture storage, not an upstream ThreeMD standard. Historical draft/halted SpecSync records remain unchanged; no new definition approval, review or finalization is claimed.

## Implementation and regression checks

The shared codec validates a versioned little-endian header, bounded dimensions/title, exact voxel and container lengths, LZFSE stream completion, palette bytes and SHA256 integrity. App and CLI read either format by content. Normal Save uses compact storage; readable Save remains explicit. Immutable save preparation runs off the main actor and invalidates obsolete work. Success marks only the written snapshot in its original document generation.

The first build caught a missing C stream initializer argument under Swift 6.3.3; it was corrected before testing. The first focused run completed 17 tests with two failures in the trailing/concatenated-stream test: Apple's decoder had read ahead and reported no remaining source bytes while ignoring trailing input. The decoder now validates and withholds its four-byte final marker, drains prefix output first, and rejects an early end. The original failing tests remain unchanged. A new independently checksummed concatenation fixture expands the first stream across four output chunks.

An initial full lane was stopped with exit 143 after those focused failures were identified. Its 29-test harness passed; its complete product suite did not finish and is not completion evidence. The stopped run's available logs are preserved separately. After repair, focused runs passed 14 tests covering stream rejection, save snapshots and CLI conversions, then eight remaining codec tests including the full 256-cubed dense volume and four-chunk concatenation. The complete final lane is recorded below when finished.

## Measurements

`benchmark.json` records five samples per operation, reporting their median in an optimized Swift build on this Mac. Each case was checked for exact readable and compact round-trip equality before measurement. CPU timing excludes file I/O, window presentation and rendering. Inputs include the orb, actual solar-system file, empty/dense 256-cubed volumes, and a deterministic mixed-palette 256-cubed volume. Sparse compression results do not imply the same ratio for arbitrary models. Saving compact data spends CPU on compression; it is not claimed to encode faster than readable text.

The preliminary benchmark predates the EOF repair and is retained as `benchmark-before-eof-repair.json`. `benchmark.json` was rerun against the repaired release codec; `Benchmark.swift` preserves the exact Swift probe. Encoding bytes are unchanged by the decoder repair. The optional compact solar-system example preserves all 185,400 occupied cells, title and dimensions; the five-format gallery manifest remains unchanged.

| Volume | Readable bytes | Compact bytes | Readable decode median | Compact decode median |
| --- | ---: | ---: | ---: | ---: |
| Orb | 5,126 | 505 | 0.55 ms | 0.013 ms |
| Grand solar system | 16,854,166 | 60,313 | 444.33 ms | 19.34 ms |
| Empty 256³ | 16,854,157 | 10,127 | 439.70 ms | 18.17 ms |
| Dense 256³ | 16,854,157 | 10,127 | 453.14 ms | 28.85 ms |
| Mixed 256³ | 16,854,157 | 8,163,571 | 574.84 ms | 170.94 ms |

Solar compression encodes in 82.83 ms versus 10.82 ms for readable text. The measured solar file is 99.64% smaller and codec decoding is about 23 times faster. These optimized measurements do not describe the debug development bundle's wall-clock native opening time.

## Final verification

The final pinned `/opt/homebrew/bin/fledge lanes run verify` completed all seven steps in 148.771 seconds: strict formatting, the 29-test harness, 177 complete-suite tests in seven suites (114.514 seconds), hi with 35 active criteria and 53 retired, strict SpecSync with five specs and zero warnings at 43/43 files and 7513/7513 lines, source boundaries, and release fixtures. Raw logs and typed receipts are preserved under `final/tests` and `final/harness`. The actual native editor tests generated 32 layout captures under `final/layout`. A separate agent inspected all eight solar Sculpt/Slice captures in both themes and sizes: essential controls and the smaller Save header fit, and selected slice 129 remains on one line. Those offscreen captures show loading placeholders rather than rendered Metal pixels; they establish layout only.

Packaging completed through `RookTool package`. Root checked the actual running app through native CUA: Open accepts the catalog compact file as a Compact 3md sculpture, restores 256-cubed dimensions and 185,400 cells, and visibly renders the solar system in Metal. Cmd-S proposes `.3mdb`; Cmd-Shift-S proposes `.3md`. Completed native saves at `/private/tmp/sculpt-compact-native-solar-20261004-1345.3mdb` and `/private/tmp/sculpt-readable-native-solar-20261004-1345.3md` match their respective catalog files byte for byte. Sizes and SHA256 are retained in `native-file-receipt.json`. Both saved files were reopened natively and returned an editable clean solar-system document.

A deliberate checksum corruption was refused with the native error; dismissing it retained the original title, cells and clean state. One reversible slice edit raised occupancy to 185,401; canceling its native Save panel kept it unsaved. Undo restored 185,400 and clean state. The app remains open on the original clean solar-system volume. The earlier user torus backup and prior solar-system evidence were not altered. These are automated checks, not an independent human review or lifecycle approval.

Publication uses the existing private feature branch and PR30. Its new exact-head CI is tracked in GitHub; no merge, direct main push, deployment or release is performed for this extension. Earlier solar-system receipts establish the prior revision only.
