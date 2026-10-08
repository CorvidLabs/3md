# Direct insertion verification

The complete pinned Sculpt lane passed on the new implementation tree: 426 tests in 37 suites, 31 harness tests, strict hi, five strict current specs with zero warnings, source boundaries and optimized release fixtures. Seven steps completed in 325.006 seconds. Coverage is 72/72 files and 18,470/18,470 lines. The package was built in release mode, ad-hoc signed and strictly verified with the existing offline sandbox and user-selected file entitlement.

The first focused run caught a folder enumeration defect: calling skipDescendants for a symlink also skipped a valid nested model. The repair removes that call and rejects a symlink folder root. The follow-up 30 tests passed. Complementary source review by agent `threemd_rust` then found that portable recapture reordered valid authored slices; agent `world_navigation` preserved previous surviving order and added two round-trip/resize regressions. The complete lane includes all 32 insertion tests.

Agent `threemd_rust` reviewed pure insertion and portable codec source, while having authored native draft tests. Agent `world_navigation` authored the pure insertion/codec changes and reviewed root-authored native integration. These are complementary agent reviews, not independent human approval. Claude's initial read-only review and follow-up corrections are recorded separately below.

Native observation confirmed the packaged build exposes Insert 3md and Insert model folder in the composition editor, with placement explanation, progress/cancellation code and the existing Undo/Redo/save actions. The actual selected-file insertion, Undo and portable native save flow remains unverified in this receipt; the active UI changed during interaction and was left for the user. The user's unsaved Valley castle was saved and preserved outside the PR at `/private/tmp/sculpt-session-preserved-valley-castle-20261005.3mdb`.

Native fixtures under `native/models/` are two small Swift-authored spatial files for the flow. Existing archives and screenshot baselines are unchanged. This is feature preparation, not a release or a completed lifecycle claim.

## Review corrections, 2026-10-06

The initial and follow-up Claude receipts are preserved unchanged. Source corrections at `02138387ab1c9bdff497b23a28922f72a984c1c1` pass the complete pinned seven-step lane in 314.516 seconds: 440 tests in 37 suites, 31 harness tests, intent, five strict current specs with zero warnings, boundaries and optimized release fixtures. Coverage is 72/72 files and 18,778/18,778 lines. `repair-final-verify.log` records this run. `repair-final-package.log` records its optimized ad-hoc package, sandbox and selected-file entitlement.

Claude's final read-only source review reports the previous actionable findings resolved with no new defect in the reviewed scope. `claude-final-review-receipt.json` retains its exact output and limits. It is an agent review, not runtime verification, an independent human review or a signature.

Root performed actual native selection, insertion, confirmation, Undo/Redo and portable save/reopen, then checked the final package's disabled portable export actions while confirmation was pending. `native-observations.md` records exact observations and source boundaries. The actual 35,586-byte self-contained native export and its tool inspection are retained in `native/inserted-portable.3md` and `native/inserted-portable-inspect.json`.

The official SpecSync 6 closing attempt materialized approved REQ-RookApp-084 and REQ-RookSculpture-042, then failed because effective retired contracts AppletEssentials, Launcher, RookAutomation and RookLanguage have no canonical files. `specsync-closing-blocker.log` preserves the actual failure. All five current strict specs still pass at 72/72 files and 18,778/18,778 lines. Old changes and archives are not reopened or rewritten to bypass that gate; the insertion scope remains verifying, with no successful closure evidence.

Publication and GitHub verification remain separate from local test and review receipts. No merge, release or human implementation approval is claimed.
