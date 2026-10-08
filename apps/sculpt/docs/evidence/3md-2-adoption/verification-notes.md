# ThreeMD 2 adoption verification

Implementation: `633df65184959ff724ebbe8204d0ed115236c845` on
`leif/adopt-3md-2`, based on landed Sculpt `e4c7819a47a36a98e6e0da20fb9e1b105ef26e34`.
Dependency: landed immutable ThreeMD `9dfbdb649891a95f27e7590e9e6ddc72b9e58d08`.
No release tag or registry publication is assumed.

## Gates

The pinned `/opt/homebrew/bin/fledge lanes run verify` passed formatting,
the 31-test harness, all 350 Swift Testing tests in 28 suites, and hi 0.8.0
at 42 active and 53 retired criteria. Product tests took 210.250 seconds.
The lane then stopped on current contract prose: duplicate symbol rows and
a requirement header that interrupted public API coverage. That prose was
corrected without changing product sources or tests.

`specsync check --strict --force` then passed all five current specs, zero
warnings, 65/65 files and 15,953/15,953 lines. The required remaining
`RookTool boundaries` and `RookTool release-fixture` gates passed. A release
package was built, ad-hoc signed and strictly verified with only the existing
app sandbox and user-selected-file read/write entitlements. Raw lane failure,
corrected contract receipt, remaining gates and package receipt are preserved
in `verification/`. Product tests were not repeated for the prose-only repair.

Focused core verification passed 37 tests in three suites. Focused native/tool
verification passed 33 tests in five suites. Regressions cover imported
identities, full 256-cubed voxel input, 65,536 world placements, exact Int64
anchors, unused definitions, graph mismatches, stale parents, one-step Undo,
capacity-only fallback, cancellation, and atomic no-replace output.

## Language interchange

`interchange/` retains six generated files and a manifest, the temporary
catalog extension source, the coordinator log and its typed receipt. The
public Swift/TypeScript-Node/Rust producer-consumer gate passed 429 cases,
17,091 imports and nine pairings with 1,899 imports each. The standard
426-case catalog stayed mandatory; three Sculpt cases added 108 imports.
Fixture hashes and uncompressed binary payloads match the original generated
bytes and the corresponding text files exactly.

The composition keeps shared and unused definitions, A/B bindings and rotations.
The sparse world keeps exact Int64 text at the limits and adjacent coordinates
above 2^53. This generic gate treats app JSON as opaque text; Sculpt's numeric
decoding and valid scene editing have their own Swift tests. Generic test edits
can append outside app fences and are not promises of valid edited Sculpt
scenes. Apple LZFSE and legacy app-format cross-language export are excluded.
Browser, Linux and Windows execution are not established by these receipts.

## Native observations

Root closed the previous clean test build and opened this optimized package.
Native file selection opened portable voxel text, composition binary and world
binary into their existing editors. The macOS File menu exposes the new copy
exports. The toolbar File menu retains its existing creation/open actions.

A shared leaf title edit updated both A and B composition references. One
parent Undo restored both labels. Canceling a native portable export returned
the same composition with Redo still available. A subsequent successful
readable export retained that history and the composition closed cleanly.

The world showed all three persisted placements and exact focus fields
`-9223372036854775808`, `9007199254740993`, `-9007199254740993`.
Selecting maximum and Jump changed focus to `9223372036854775551, 0, 0`.
A binary copy restored that same focus and draft; closing needed no discard.
The live Metal view was observed, but these tiny fixture models occupy only a
small part of its camera framing. No frame-rate or performance claim is made.

`native/` retains exported voxel binary, composition text and world binary,
with CLI inspection receipts. Each file is byte-identical to its deterministic
canonical fixture. Some export completion occurred while the user interacted
with the native panel; those clicks are not claimed as exclusively agent input.
The original chosen files remain outside the staged evidence copies.

## Review and limits

`agent:codex-threemd-editing` reviewed committed implementation `633df651`,
including both corrected findings. Unmarked general binary voxel adoption now
adds its portable marker to the immutable snapshot while preserving IDs and
the original input. Native Open validates its nonblocking opened descriptor,
reads bounded chunks through EOF and propagates cancellation. No remaining
scoped source defect was found. The reviewer previously authored upstream
library portions and fixtures, not this adoption; this is finite technical
agent evidence, not a GitHub approval, human review or permitted signature.

All 44 fresh native view captures in `layout/` were visually inspected across
themes and sizes. Fixed primary controls fit. World instance controls continue
below the sidebar scroll boundary; solar glyphs need zoom at Fit. Blank GPU
panes in offscreen captures do not verify live Metal rendering or native panels.

Augur scored this implementation range 30.8687, verdict proceed. An unsigned
Attest note records the actual scoped agent reviewer and passes this repository's
configured verifier. It is not a cryptographic signature or a permitted signed
upstream ThreeMD attestation. Git notes were not pushed as release provenance.

Official `specsync change check <adoption-id> --commit --strict` materialized
the approved three requirement deltas, then refused its effective contract
because old active launcher scopes refer to missing canonical modules
AppletEssentials, Launcher, RookAutomation and RookLanguage. The raw failure
is `verification/specsync-change-check.log`. Forced current canonical checking
still passes with full coverage and zero warnings after materialization.

The current scope remains implementing without official verification, review
or finalization. Historical scopes and archives remain unchanged. The new PR
is a draft pending supported lifecycle recovery and exact published-head CI;
no old record was edited to manufacture acceptance. SpecSync 6 has no halt
command. This closing failure is separate from product tests, scoped technical
agent review and the current canonical contract checks.
