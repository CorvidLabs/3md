---
change: document-viewer-examples-and-supported-file-folder-and-github-opening-workflows
artifact: context
---

# Context

Leif directly requested updating the README and docs with examples and links after the current support audit. PR 93 is merged at e1beb095; this docs-only follow-up starts there in an isolated worktree, leaving the edited local viewer alone. The audit opened 299 text and 4 uncompressed binary examples, refused the two LZFSE fixtures as expected, passed the full main-corpus component render check on Chromium/WebKit, and checked public GitHub text/binary/linked-folder inputs. GitHub linked folders and non-GitHub direct binary URLs still have documented loading gaps. No loader repair, storage migration, native editing change, release, merge or deployment is added. Actor and verification claims identify agent:codex, not a human review or signature.
