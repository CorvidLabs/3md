---
change: document-viewer-examples-and-supported-file-folder-and-github-opening-workflows
artifact: context
---

# Context

Leif directly requested updating the README and docs with examples and links after the current support audit. PR 93 is merged at e1beb095; this docs-only follow-up starts there in an isolated worktree, leaving the edited local viewer alone. The audit opened 299 text and 4 uncompressed binary examples, refused the two LZFSE fixtures as expected, passed the full main-corpus component render check on Chromium/WebKit, and checked public GitHub text/binary/linked-folder inputs. GitHub linked folders and non-GitHub direct binary URLs still have documented loading gaps. No loader repair, storage migration, native editing change, release, merge or deployment is added. Actor and verification claims identify agent:codex, not a human review or signature.

## Verification and publication (2026-10-10)

Implementation: `07e4d7d8858452029ec2cac2694f73ec8563d72f` on `leif/viewer-opening-guide`, based on merged PR 93. Subsequent changes record lifecycle evidence only.

- Source and local-link audit passed 100 checks. Five unique live GitHub file samples decoded successfully: canopy text, layered notes text, canopy uncompressed kind 1, canopy structured kind 2, and shared-grove structured composition with its two embedded documents. Repo/folder URLs use supported GitHub locators.
- Both generated docs mirrors are identical and parse into 11 planes; the VIEWER plane preserves the guide text. The published viewer opened the actual linked `canopy.structured.3mdb` as Reusable canopy, two planes and six cubes.
- The new `web/docs.html#viewer` section was inspected in the local browser at its normal viewport; it displays all example links and surrounding docs. This preview is local, not a deployment. The existing edited viewer tabs were preserved.
- Strict root specs passed with no errors or warnings, 100% source coverage; Hi passed 87 criteria across 12 families and 10 files; `git diff --check` passed.
- Pinned Trust 1.2.2 with Fledge 1.7.2 passed the complete eight-step verify lane in 4m 0.045s, including 322 Swift tests, TypeScript and Rust checks/tests, nine-pair interchange, bundle drift and editor grammar. Augur returned proceed, risk 30. The configured soft provenance remained degraded.
- Actual unsigned `agent:codex` Attest evidence was recorded after Trust passed and published through a normal notes push. Strict Attest verification correctly refused the unchanged signature and allowed-reviewer requirements. No Leif diff review, independent human review or permitted signature is claimed.
- Documentation PR: https://github.com/CorvidLabs/3md/pull/94. Leif merges it. No merge, deployment or release was performed. Scope verification remains separate from closing approval and archive.

Verified artifact SHA-256:
- `README.md`: `a8e7ab63095b8a184e692a0e0977ddb1666b4b384cf6f7e5edf6c94820e1abdf`
- `docs/VIEWER.md`: `d362773f0efc7f5f8b7ec17300d5a1d9c6613b7279d3645e36fcdb866f507db1`
- `web/docs.html`: `e20148d65dff48dbca47ff05a44994a52922c66e62a696b1df41445f03f2c658`
- `scripts/build-docs-3md.mjs`: `bae5d95d93de3dfb6da906d0d61f3e75e9afc1bdf6f8712ef11d1c828dfba920`
- `docs.3md`: `44ef2f8032b350ac01be85140bf75396d7de96f89624530baea47d79b6955b04`
- `web/docs.3md`: `44ef2f8032b350ac01be85140bf75396d7de96f89624530baea47d79b6955b04`
