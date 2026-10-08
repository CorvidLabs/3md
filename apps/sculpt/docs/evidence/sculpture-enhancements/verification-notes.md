# Sculpture enhancement verification

Root ran the product tests. grok-build did not run Fledge, SwiftPM, or the product tests. This note is not a human review. grok-build recorded no SpecSync approval, review, or finalization. The latest lane is the post-UI-polish run below. The earlier lane, [final-tests](final-tests/), [final-harness](final-harness/), and [test-attempt-1](test-attempt-1/) stay as previous pre-UI-polish evidence.

## Previous pre-UI-polish lane

Codex executed `/opt/homebrew/bin/fledge` 1.7.2 `lanes run verify` on the then-frozen sources and reported that the lane finished in 36.953 seconds.

The seven steps, measured before SCULPTURE-17:

1. Formatter.
2. Harness: 29 tests in 0 suites passed after 0.975 seconds.
3. Complete suite: 80 tests in 2 suites passed after 8.153 seconds.
4. `hi check`: 23 active criteria, 53 retired.
5. `specsync check --strict`: 5 specs, 0 warnings, 28/28 files, 3623/3623 lines.
6. Source boundaries.
7. Release fixtures.

The copied receipts keep their original `.build` paths:

- Complete suite: `.build/verification/80075118-511B-4B15-881C-24542389B2C2/swift-test.log` and `swift-test-result.json`, copied to [final-tests](final-tests/).
- Harness: `.build/verification/C0C5BACC-CF74-418F-98F5-6A0909D544E9/swift-test.log` and `swift-test-result.json`, copied to [final-harness](final-harness/).

Both assessments record `passed: true` and upstream exit code 0. The earlier actor-binding compile failure is resolved. This lane has no pending compile blocker.

## GIF cancellation

[test-attempt-1](test-attempt-1/swift-test.log) reports `Test run with 79 tests in 2 suites failed after 8.744 seconds with 1 issue.` The GIF case of `cancellationRemovesPartialAnimationAndOwnedStagingFile` failed because the parent folder was not empty. ImageIO leaves a hidden atomic temporary file beside a directly staged GIF. The MP4 case of that test was not the recorded issue.

The frozen exporter creates `.rook-turntable-<uuid>/` beside the destination, writes `turntable.gif` or `turntable.mp4` inside it, moves that file to the destination, and removes the directory. The directory owns ImageIO's temporary file, so cleanup does not depend on an empty parent folder. The final complete suite records `cancellationRemovesPartialAnimationAndOwnedStagingFile` with 2 test cases passed after 0.096 seconds, and `AnimationExportTests` passed after 0.838 seconds.

## Gallery

Root generated 60 artifacts from the final Swift catalog: 12 entries, each with `.3md`, `.png`, `.gif`, `.mp4`, and `.obj`. [Examples/README.md](../../../Examples/README.md) links every format. `Examples/manifest.json` records the shared settings and each file's byte count. Map samples read Y six rows higher inside the same 24-cubed volume. The contact sheet is [examples-contact-sheet.png](examples-contact-sheet.png).

The final log records these artifact checks passed:

- `galleryManifestMatchesAllPublishedFilesAndDownloadLinks` after 0.018 seconds.
- `everyExampleHasFiveCompleteArtifacts` with 12 cases after 0.058 seconds.
- `everyPNGDecodesAtThePublishedSizeWithVisibleCharacters` with 12 cases after 0.565 seconds.
- `everyGIFLoopsForFourSecondsWithFortyTimedFrames` with 12 cases after 2.163 seconds.
- `everyMP4HasOneSilentFourSecondVideoTrackAndDecodableFrames` with 12 cases after 2.399 seconds.
- `everyOBJContainsBoundedOutwardFacingVoxelGeometry` with 12 cases after 0.533 seconds.

## Latest verified lane

After the final UI polish, root ran a second `/opt/homebrew/bin/fledge` 1.7.2 `lanes run verify` on the frozen sources. The lane passed in 44.721 seconds. grok-build did not run it. There is no pending compile. The seven steps:

1. Formatter.
2. Harness: 29 tests in 0 suites passed after 1.322 seconds.
3. Complete suite: 80 tests in 2 suites passed after 8.495 seconds.
4. `hi check`: 24 active criteria, 53 retired.
5. `specsync check --strict`: 5 specs, 0 warnings, 28/28 files, 3664/3664 lines.
6. Source boundaries passed.
7. Release fixtures passed.

The copied receipts are unmodified and keep their original `.build` paths:

- Complete suite: `.build/verification/9C87E0CE-FB62-441B-A0F8-60DEFF7BC943/swift-test.log` and `swift-test-result.json`, copied to [verified-tests](verified-tests/). The receipt records `passed: true`, upstream exit code 0, and `✔ Test run with 80 tests in 2 suites passed after 8.495 seconds.`
- Harness: `.build/verification/24625EFD-3D7D-41A9-9ED9-8C67B2129E48/swift-test.log` and `swift-test-result.json`, copied to [verified-harness](verified-harness/). The receipt records `passed: true`, upstream exit code 0, and `✔ Test run with 29 tests in 0 suites passed after 1.322 seconds.`

The 23 criteria and 3623 lines above stay with the pre-UI-polish lane. The 24 criteria and 3664 lines stay with this lane. After SCULPTURE-17, and before this correction, a documentation recheck ran `/tmp/rook-tools/hi check` (24 criteria, 12 families, 12 files, 53 retired) and `specsync check --strict` (5 specs, 0 warnings, 28/28 files, 3629/3629 lines). That recheck is not either lane, and grok-build still did not run the product tests.

## Studio save path

Native testing showed the system file mover opened a folder chooser. Root replaced that path. `SculptureExportStudio` does not use `fileMover`. It writes the snapshot under `RookExport-<uuid>/`, reads the bytes asynchronously with `mappedIfSafe`, and presents one `FileDocument` `fileExporter` inside the studio. Content types are `.gif`, `.mpeg4Movie`, and `.sculptureMesh` (`UTType` for the `obj` extension, or `.data` when that type is unavailable). The default filename is the generated file's name. Save 3md, PNG, and ASCII text still share one other `fileExporter` in the main editor. Each view has one `fileExporter`. A save or export error keeps the generated file for another attempt. The studio applies the Brand palette. Duration, frames per second, and resolution stay locked while a job is running or a generated file is waiting. The brush size row shows the caption Brush once. `ScrollViewReader` centers the selected slice on appear, on a layer change, and on a depth change. `RookTool examples` refuses a symlink at `Examples/`, at a target artifact, and at `manifest.json`.

## Native editor session

Codex observed the updated editor. grok-build did not run that session. The window was 940 by 682 in dark appearance. Gallery search for canal opened the 960-cell Canal city. Maps use pitch 0.7. A grid pointer drag across 24 empty map cells raised the occupied count from 960 to 984, and one Cmd-Z restored 960. The original document was saved as a native 3md backup outside the repository and restored once. That backup is not published. The selected slice was visible on reopen, and the Brush label was not duplicated. The final GIF export presented a normal Export As filename Save panel. The user then resumed using the app; Codex stopped native testing to preserve their active Pixel bonsai session. Final native GIF, MP4, and OBJ saving was not completed. Automated export checks passed, but are not evidence of completing those native Save dialogs.

## Still open

The 60 catalog artifacts match the generated gallery. [Examples/README.md](../../../Examples/README.md) links every format. [Pull request 28](https://github.com/CorvidLabs/rook/pull/28) tracks feature-branch publication and CI. Final native GIF, MP4, and OBJ saving has not been exercised. Merge and release remain unauthorized. There is no pending compile. Codex completed the publication documentation after the bounded Grok docs task reached its turn limit; no additional lifecycle approval or review was recorded.
