# Editor redesign verification

This iteration covers SCULPTURE-18 through SCULPTURE-20: canvas-focused editing, contextual accessible commands, and a development-only file interface shared with the Swift document model. These are Codex execution observations, not human diff review or SpecSync lifecycle approval.

## Retained attempts

The first complete-suite attempt passed 99 of 100 tests. A CLI relative-path test exposed an incorrectly constructed directory URL. The adapter now explicitly constructs its working-directory URL with `isDirectory: true`. The original failed receipt remains in [relative-path-attempt](relative-path-attempt/).

After that correction, the pinned seven-step lane passed in 37.275 seconds. It ran the formatter, 29-test harness, 100 complete-suite tests in three suites, hi, strict SpecSync, source boundaries, and release fixtures. The complete suite passed after 11.044 seconds and the harness after 0.997 seconds. hi reported 27 active criteria and 53 retired. Strict SpecSync reported five specs, zero warnings, and coverage of 32/32 source files and 4725/4725 lines. Original test receipts are copied without modification into [verified-tests](verified-tests/) and [verified-harness](verified-harness/).

The eight offscreen native captures in [native-layouts](native-layouts/) cover Sculpt and Slice modes at 940×650 and 1120×760 in light and dark appearance. They use unshown AppKit windows. The receipt explicitly records that the accessibility tree was unavailable in that context, and that AppKit bitmap caching may omit Metal drawable contents. These captures verify layout and presentation; they are not evidence of live keyboard focus, VoiceOver operation, or visible Metal output.

## Live app findings

Codex saved the user's Woven torus as a native 3md backup outside the repository before updating the bundle. The new editor reopened that backup with its 24×24×24 dimensions and 816 occupied cells intact. The real Metal canvas displayed the torus in the enlarged working area.

Live Cmd-K testing exposed a focus defect: the palette opened, but immediate typing reached the underlying title. Native accessibility inspection also showed parent container identifiers overriding descendant control identifiers. These findings occurred after the lane above; its green result does not claim those flows worked. The original title was restored and the saved sculpture remained intact.

Native search now takes first responder when mounted, and concrete controls keep distinct identifiers. Two teardown timing corrections did not restore reliable canvas focus in the actual app. The final correction uses a scoped native canvas responder with transparent pointer hit testing and explicit acquisition. Arrow and Space events route to the existing editing model. Other keys retain their responder chain. The native search releases focus on teardown; Escape restores the previous editor target. A focused attempt's two SwiftUI integration assertions could not reach unavailable accessibility elements in an unshown host. Those tests were replaced with native responder lifecycle tests, without skipping unavailable assertions. Live app checks remain the integration evidence.

The final running app passed this sequence: Cmd-K, immediately type show slice, Return, Right, Down, Space. The selected cell moved from 1,1 to 2,2; occupancy changed from 608 to 609. Cmd-Z restored 608. Opening search while the title was focused and pressing Escape restored title input; later typing changed only the title, which Codex restored. Cmd-O opened the native file picker without opening the toolbar's File menu first. Cmd-S opened a normal native Save panel with Woven torus.3md; cancel preserved the document. The user's Woven torus was reopened with 816 cells and left unchanged in Sculpt mode. VoiceOver itself was not run.

## Final frozen verification

The pinned seven-step lane passed in 34.176 seconds on the final frozen product and test sources. It passed the formatter, the 29-test harness after 1.048 seconds, and 103 complete-suite tests in four suites after 12.813 seconds. hi reported 27 active criteria and 53 retired. Strict SpecSync passed five specs with zero warnings and 35/35 files and 5029/5029 lines covered. Source boundaries and release fixtures passed. Packaging verified the sandbox and user-selected read/write entitlement; the bundle is an ad-hoc local build.

Original receipts are copied unchanged to [final-tests](final-tests/) and [final-harness](final-harness/). Eight fresh captures and their original receipt are in [final-layouts](final-layouts/). Earlier captures and attempts remain alongside them. The live Metal view visibly rendered the sculpture; the offscreen captures retain their stated drawable and accessibility limitations. The new native regressions exercise filtered Return, search-to-canvas responder handoff, arrow movement, modifier bypass, painting and undo, and Escape-to-title restoration in unshown windows.

## Structured file interface

The command engine validates strict tagged JSON, zero-based bounds, supported glyphs, versions, and batch size. A rejected batch preserves the original document and undo history. The CLI rejects nonregular and oversized inputs and publishes a new output without replacing existing files, directories, or symlinks. The adapter tests exercise directory aliases, relative paths, existing outputs, malformed input, and atomic failure.

Codex ran the documented four-command batch against Character orb. The new 3md output reopened through inspection with the title First agent sculpture and 608 occupied cells. Repeating the command against that same output path failed without changing its bytes. Temporary demonstration and user-session files remain outside the repository.

## Publication and lifecycle

The user's direct 2026-10-04 instruction authorizes merging the current PRs after required checks. PR27 merged at exact CI-passed head `28111071057031c38ac94ea2710c9bef28085746`, producing `7f875583ecc33c5870bbd85275aef44c106dc53c`. PR28 carries this iteration. Draft and halted SpecSync changes remain in their recorded states; no approval, review, or finalization is invented. hi and SpecSync structural checks do not replace product tests or GitHub CI.
