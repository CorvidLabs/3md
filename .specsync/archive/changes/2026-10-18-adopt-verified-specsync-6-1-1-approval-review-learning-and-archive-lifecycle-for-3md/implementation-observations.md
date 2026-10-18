# Implementation observations and pending qualification

Observed: native audit inspects archived state enough to reject an invented archive directory lacking state.json. Correction: tests use an empty clean fixture and archive-only note, explicitly not a fabricated accepted/finalized change. Genuine human-review/finalization remains manual. Evidence: initial control failure and final 3md-controls.log; this does not prove authentic finalized-delivery positive behavior.
Observed: placing an enforcing archive guard before existing Trust would skip existing checks when inherited debt fails. Correction: append independent always() guard/control steps after the unchanged Trust invocation. Evidence: workflow diff; hosted execution has not run.
Observed: approved definition tasks remain incomplete; scoped verification refuses them. Preserve approval-bound artifacts and record results externally pending a supported safe runtime-update path or exact amendment. No self reapproval.
Observed: Linux Sculpt package compilation fails CLzfse/lzfse.h absent. No product change is authorized by this operations migration; resolve build prerequisites separately and rerun. Godot absent; macOS Sculpt lane not runnable on Ubuntu.

Native change check --strict --commit passed, but rewrites change.md and removes unknown sections. A disposable native check preserved this file byte-exact with the approved digest unchanged (3md-observation-probe.json). Store observations here as supplemental human-readable package context; do not assume the native lesson synthesizer consumes it; this is not a machine approval or review. The original definition/context remain untouched. Checkboxes mean the planned operations and attempts were executed, not that product checks passed.

Canonical strict100 coverage passed. All 15 lifecycle controls passed, including ignored child-file/subtree regressions exercising the existing reject-all-exclusions policy. Scoped operations evidence is not product evidence. Global audit after scoped verification has exactly nine inherited errors. The archive guard remains blocked.

Cold full verify timed out at240 seconds after lint/build while Swift tests were running; warm full retry PASSED all eight steps in5m41.827s (exit0): lint/build,315 Swift tests,431 JS tests,115 Rust tests (one existing ignored exhaustive mutant test), nine-pair interchange, element bundle drift and editor grammar checks. Linux Sculpt exit1 missing lzfse.h; Godot missing; macOS lane unavailable. Trust initial invocation could not infer comparison range. The root product lane passed. No Sculpt, Godot, complete Trust pass, hosted CI, human implementation review or finalization is asserted.

Owners must recover incomplete inherited plans/interviews, REQ-ThreeMD-044 collision and stale verification separately. Provide Linux LZFSE/Godot prerequisites and macOS Sculpt validation; complete product/Trust gates before readiness.

Final workflow review: even always() steps in the same job make product Trust status red
until archive finalization. Moved only the new lifecycle controls/guard into an independent
archive-readiness job with checksum-verified6.1.1 installation. Existing canonical, product,
risk, provenance and Trust-block steps remain unchanged in the original trust job. Neither
job depends on the other; readiness still requires both, without forcing human finalization
before product evidence is available. YAML structure and fixture controls validate the split.
The prior explicit-range Trust run was interrupted for user-requested cleanup (exit15), not
a pass; a disk-monitored exact-candidate rerun is pending.
