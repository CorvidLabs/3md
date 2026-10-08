# Shared-model editing verification

The approved SCULPTURE-34 slice edits reusable voxel definitions inside the existing composition or world editor. Apply publishes one validated complete-graph change; Cancel retains the source. Make Unique clones a voxel leaf and rebinds one world placement. Existing schemas, ThreeMD 1.8.1, finite limits and offline sandbox stay intact.

## Automated verification

The initial full lane passed 316 tests and 31 harness tests. Scoped source review then found that dismissing a reference editor for Save reconstructed its draft and lost history. The correction retains the actual draft object through preparation and the native panel. Five new save-session tests cover successful real file writing, cancellation/failure, captured baselines, newer edits and draft identity/history/presentation.

The final `/opt/homebrew/bin/fledge lanes run verify` passed all seven steps in 191.593 seconds: 321 Swift Testing tests in 25 suites, 31 harness tests, hi 0.8.0 at 41 active and 53 retired criteria, strict SpecSync 6.0.0 at five specs with zero warnings and 60/60 files and 14,526/14,526 lines, product boundaries and optimized release fixture scanning. Raw logs and typed receipts are retained in `initial/` and `final/`. The five save-session tests use the actual asynchronous graph save job and temporary output, rather than only mirroring presentation state.

Four final shared-editor captures cover 840 by 640 and 1120 by 780 in light and dark. They establish rendered layout. Offscreen SwiftUI accessibility is unavailable in these captures; their receipts explicitly say no accessibility activation occurred. Packaged-app interaction below establishes activation separately. CPU captures and native observations do not establish an on-screen FPS guarantee.

## Packaged-app interaction

`RookTool package` built the optimized ad-hoc app with its existing sandbox and user-selected read/write entitlement. Native interaction used that exact package, not a reconstructed preview.

- Opened the courtyard, edited its shared bonsai, painted one previously empty cell and canceled. Reopening showed its original 978 voxels, with no graph Undo entry.
- Repeated the edit and applied. The reference draft gained Undo. Canceling the native save panel preserved history. Undo and Redo restored/reapplied the shared edit.
- Successfully saved the composition. Inspection of `native/courtyard.3md` shows the tree has 979 voxels, gate retains 976 and the root and nested tile models remain references. Undo and Redo remain available after Save.
- Opened the wide world. Make Unique is disabled for a nested tile model. Placed a bonsai voxel leaf, made it unique, then used Undo/Redo. Only its model binding changed; its instance ID, zero origin and rotation were retained. The four original garden placements remained unchanged, including exact trillion-cell coordinates.
- Successfully saved that world and verified its graph using the explicit-file CLI. `native/world.3md` and its inspection receipt preserve all five placements, the copied 978-voxel leaf and original tree. Undo/Redo remain available after successful Save and after a subsequent canceled save. Closing the restored saved draft required no discard confirmation.

The native panel initially saved to an owned temporary filename inside the isolated checkout. That test output was moved to the retained evidence destination. No preexisting example or user file was overwritten, and no additional generated gallery artifacts were staged.

## Review and delivery

Scoped agent review initially blocked on Save history loss and passed after the correction. It is agent evidence under Leif's direct preparation request, not a GitHub human approval. No signature, agent merge, release, main push or automatic upstream adoption is claimed. Leif merged PR33's definition-only head `4ea1a967c8e8d7b97a1f6d6f28796f130a252d5f` as `e260c0584fb45a519908602444d9237d225f0fac` while implementation was underway. That main tree is byte-identical to the definition branch tip. PR34 contains the actual implementation, reconciled against that main without changing its tested tree. Leif will merge PR34 later.

The new change's `specsync change check --commit --strict` materialized its three approved requirements, then refused verification because historical active launcher scopes still reference missing canonical modules `AppletEssentials`, `Launcher`, `RookAutomation` and `RookLanguage`. The raw failure is `final/specsync-change-check.log`. Forced current `specsync check --strict --force` still passes at five specs with no warnings. Historical scopes were intentionally left unchanged. The new change remains implementing, without a verification, review or finalization claim; PR34 stays draft pending a separately authorized lifecycle retirement/recovery. This gate failure is distinct from passing product tests and scoped source review.
