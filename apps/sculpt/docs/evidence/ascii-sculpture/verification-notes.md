# ASCII sculpture verification

Observed by Codex on 2026-10-04. This is agent testing and visual inspection, not an independent human review or lifecycle approval.

The pinned `/opt/homebrew/bin/fledge lanes run verify` completed all seven steps in 28.391 seconds: formatting, guarded tooling harness (29 tests), guarded complete suite (49 tests), hi intent, strict specification checking, source/dependency boundaries, and the release fixture scan. The suite includes a real offscreen Metal command whose completed texture contains visible glyphs. Strict specs report 5 passing specs, zero warnings, and 21/21 source files covered. hi reports 17 active criteria and 53 retired IDs.

Raw logs and unmodified JSON receipts are retained in `final-tests/` and `final-harness/`. The receipts preserve their original `.build/verification/` run paths. The three `native-*` fixtures came from the actual native importer/exporter, rather than a mocked filesystem path.

The packaged, sandboxed app was inspected at 940 by 682 in dark appearance. Native keyboard cell painting updated the preview from 608 to 609 occupied cells. Orbit controls changed the rendered view. Quit with unsaved changes produced a cancel/discard alert. Opening another file produced a discard warning. Saving and reopening the native 5126-byte 3md fixture restored the 608-cell orb. Clicking the rendered preview selected cell 11, 5 in slice 13. Native PNG export produced a 576 by 648 image; ASCII export produced 36 rows of 64 characters. The initial competing exporters prevented Save 3md from opening; consolidating them into one exporter fixed that and the native save/reopen flow was checked again.

Inline computer-use screenshots were inspected; they are not golden baselines or archived screenshot evidence. The PNG here is an artwork export, not a window screenshot. Pointer drag verification was interrupted by active user interactions, so there is no claim of a completed native drag-paint test. Model tests cover stroke undo coalescing. No menu-bar-extra click, VoiceOver run, alternate-theme capture, notarization, or distribution test was performed. The running editor was left available to the user without discarding their session.

Product sources and tests were not changed after this final lane. CI, publication state, and SpecSync lifecycle approval/review/finalization are separate from these local results. The sculpture scope remains a draft lifecycle record; old halted changes and the lifecycle archive were not rewritten.
