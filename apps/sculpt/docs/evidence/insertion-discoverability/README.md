# Discoverable and reliable insertion verification

Change: `make-3md-file-and-folder-insertion-discoverable-and-reliable-for-people-and-explicit-file-agent-tools` (SCULPTURE-39). Branch `leif/linked-file-insertion` (PR38). Implementation commits `5eb21f9`, `12c0379` and `0fb74ae`, with specs and docs in `a6873c0` and `93b00b3`. ThreeMD is pinned to the published `exact: "2.0.0"` (`ca2d1e3`), whose library sources equal the earlier `9ac2454` pin.

## Automated verification

The complete pinned seven-step lane passed at `0fb74ae` in 7 minutes 27.9 seconds, recorded in [verify-0fb74ae.log](verify-0fb74ae.log):

- Format check.
- 31 harness tests.
- 513 tests in 41 suites.
- hi 0.8.0 with 46 criteria and 53 retired.
- Strict SpecSync 6.0.0 with 5 specs, zero warnings, 77/77 files and 20,652/20,652 lines.
- Source boundaries and the release fixture.

Earlier passing lanes on `5eb21f9` (487 tests in 40 suites) and on the repaired code before its documentation commit (513 tests in 41 suites) preceded it; their logs are not retained in the repository. Later commits change only documentation, specs and SpecSync records.

The packaged sandboxed app was built at `93b00b3` in a separate worktree, recorded in [package-93b00b3.log](package-93b00b3.log). The app sources there are identical to `0fb74ae`, which changes only RookTool output and SpecSync records.

- Strict codesign verification passes.
- The signature is ad hoc and the app is not notarized.
- The entitlements are only the app sandbox and user-selected read-write files.
- The executable SHA-256 is `789e8feb9d4a695792cc03b354db28da5b105e662cc026f762628625f2060944`.

[package-verify-93b00b3.txt](package-verify-93b00b3.txt) records the strict verification, entitlements and hash.

[cli-insert-runs.md](cli-insert-runs.md) records real explicit-file runs of both insert commands: native and portable successes, reopen checks and named refusals.

## Review

Two adversarial read-only Claude workflow reviews examined the work, and a final read-only audit checked these claims against the logs and source; their transcripts stay in the local session and are not retained in the repository.

The first examined the composition, world, plan and codec changes. It confirmed an order-dependent native fallback, a shared-edit Apply race with menu Undo, ambiguous Edit shared model labels, a missing resolved-volume budget and several smaller defects. `12c0379` repairs them, with mutation-checked tests.

The definition's palette wording did not match the implemented design. It was corrected before verification in `4ddc947`, with a second recorded definition approval.

## Lifecycle

SpecSync `change check` for this change and for SCULPTURE-38 both report verified in a scratch clone at `c4bcf2a` that applies PR39's move of the halted launcher-era records, recorded in [lifecycle-check-with-pr39.txt](lifecycle-check-with-pr39.txt). The same receipt shows the remaining audit items: the never-approved draft and the missing requirement evidence rows of the 1024 and exploration changes on PR36 and PR37. On this branch alone, the retired-contract gate still blocks `change check` until PR39 lands. Scoped review and finalization are not recorded.

## Not performed

As Leif chose, nobody drove the packaged app interactively for this iteration. Menu delivery to a key sheet, the delayed importer presentation and on-screen layout are therefore not natively observed. The offscreen presentation hosts exposed no accessibility tree, and their receipts list the controls whose identifiers could not be checked.

These are agent reviews and finite tests. They are not a human review, a GitHub approval, a signature or an on-screen FPS claim.
