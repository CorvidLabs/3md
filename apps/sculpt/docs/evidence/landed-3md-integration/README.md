# Landed ThreeMD repair integration, 2026-10-06

Leif merged ThreeMD PR66, head `7f07f0f58866b42b2ed9fc4568a908abc5959dbf`,
into main as `9ac2454dfec51a9d575a030236f046462059f847`. GitHub records
`0xLeif` as the merger at 2026-10-06T13:59:36Z. Root did not execute that merge.
Both commits have tree `0d5920f7b829e4ca68bcbf88617fc235e0f3a3e8`.

The existing SCULPTURE-35 adoption updates Package.swift and the generated
Package.resolved to the landed immutable revision. Swift Package Manager
resolved `.build/checkouts/3md` to that exact commit. Current dependency prose
is synchronized; existing test receipts, archives and approvals are unchanged.
No product source, format, editing limit, default save path, entitlement or
requirement behavior changes in this follow-up.

The pinned verification command is:

```text
PATH=/opt/homebrew/bin:/Users/leif/.cargo/bin:/Users/leif/.bun/bin:/usr/bin:/bin:/usr/sbin:/sbin FLEDGE_NON_INTERACTIVE=1 ROOK_HI=/tmp/rook-tools/hi ROOK_SPECSYNC=/Users/leif/.cargo/bin/specsync /opt/homebrew/bin/fledge lanes run verify
```

The ThreeMD candidate is not a published 2.0.0 tag. Prior retired-contract
SpecSync closing failures remain open. This record does not claim lifecycle
finalization, independent human implementation review, signed provenance,
Linux/Windows runtime proof, a release or a deployment.

## Verification

Implementation commit `583eb0d3b7df320461232070974b7c1434aeafbe` passed all
seven steps in 312.790 seconds. `verify.log` records 440 tests in 37 suites,
the 31-test harness, intent, five strict current specs with zero warnings,
72/72 file and 18,778/18,778 source-line coverage, product source boundaries
and optimized release fixtures. `test-result.json` and `harness-result.json`
retain the runner's successful completion receipts.

The tests include the 21 shipped voxel examples, OBJ/export artifacts, portable
scene round trips, preserved identities and metadata, exact world coordinates,
shared edit preconditions, insertion confirmation and stale-state refusal,
Undo/Redo, native accessibility fixtures and large-volume refusals. The
compiler still reports the pre-existing unused `modelRootID` local in
SculptureThreeMDCodec; this follow-up does not change product source.

Automated native fixtures ran on this dependency. The earlier manual native
insertion/save/reopen observations remain at their recorded implementation
heads; no new manual session or on-screen FPS result is claimed here.

The optimized package completed with a verified local ad-hoc signature,
the enabled app sandbox and only the existing user-selected read/write file
entitlement. `package.log` records it. The build is not notarized or distributed.
