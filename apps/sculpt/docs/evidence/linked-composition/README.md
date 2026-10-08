# Linked composition reading verification

Change: `open-and-resolve-linked-3md-compositions-from-a-chosen-project-folder-and-import-self-contained-bundles` (SCULPTURE-40, iteration A). PR44 merged as `257904b`, whose tree equals the tested head `3a495f7`. ThreeMD stays pinned `exact: "2.0.0"` (`ca2d1e3`).

## Automated verification

GitHub Trust passed on `3a495f7` ([run 37568169673](https://github.com/CorvidLabs/sculpt-3md/actions/runs/37568169673)), recorded in [trust-3a495f7.log](trust-3a495f7.log):

- The complete pinned lane passed: 7 steps in 10 minutes 1 second, 36 harness tests, and 586 tests in 49 suites.
- The contract step ran strict SpecSync.
- Augur returned review at risk 41, below the block threshold of 65.
- Provenance was skipped under the soft policy.

Earlier runs:

- A local lane at `206d9b0`, before the review fixes, passed 580 tests in 49 suites.
- A GitHub run at `ac05f9f` passed every test but failed the lane's strict log check, because two presentation tests recorded a known issue when the offscreen host exposed no accessibility tree. `3a495f7` prints that note to the test log instead.

## Review

A five-lens adversarial review by read-only Claude agents produced 22 candidate findings; skeptics confirmed 15. The confirmed blocker was in confinement: the reader split paths by grapheme cluster, so a name ending in a Unicode prepend scalar could carry a separator into one `openat` and cross a symbolic link out of the folder. Paths are now split and checked by byte. The other confirmed findings, all fixed with tests that were checked to fail without their fix:

- a root whose name holds a colon or backslash was reported as outside the folder;
- a leading period with a combining mark escaped the hidden check;
- defaults and CoreFoundation bookmark APIs slipped past the boundary scan;
- the nested occurrence limit message, a stale notice after a cancelled reload, and spec rows;
- four test gaps.

These are agent reviews, not a human review, a GitHub approval or a signature.

## Packaged app

The sandboxed app was packaged from `3a495f7`. Strict codesign verification passes. The signature is ad hoc, the app is not notarized, and its only entitlements are the app sandbox and user-selected read-write files. The executable SHA-256 is `5870de48ce5f771dc3ce3748a01f24103fc71d2775dac4365415f1d47b929d47`.

## Native check

Not performed. Leif asked Claude to run the packaged nested-folder check (open `scenes/harbor.3md` from a demo project with models in nested folders, then the missing-file repair, Cancel and a folder that does not contain the root). This session could not drive the native panels: its requests to automate System Events timed out at the macOS permission prompt, and screen capture was refused (`could not create image from display`). In-process tests cover the confined reader with nested temporary folders, outside the sandbox. Sandboxed access to nested folders through the folder panel is therefore not natively observed. The check carries into iteration B, whose Insert Linked Model reads the same folders.

## Not claimed

No on-screen performance, exhaustive correctness, human review or signature is claimed.
