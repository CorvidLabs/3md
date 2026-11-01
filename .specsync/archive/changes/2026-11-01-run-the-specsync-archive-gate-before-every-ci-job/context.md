---
change: run-the-specsync-archive-gate-before-every-ci-job
artifact: context
---

# Context

CorvidLabs is rolling out the SpecSync archive gate across the organization.
CorvidLabs/spec-sync#832 (merged as 106aaa43d0bcf049f19b173ddb63815a25c3f931)
added an `archive-gate-only` input to the spec-sync GitHub Action. With it set
to `'true'` the action runs only `.github/scripts/archive-readiness.sh`, which
needs bash and python3 and no binary download, and fails while any change under
`.specsync/changes/` is still open. 0xLeif approved the org-wide rollout. Branch
protection through an org ruleset that requires a check named Archive is
configured separately and is not part of this change.

Published releases v6.1.1 and older ignore the input, so the step pins the
merge commit. Move the pin to the first release that ships the gate.

At the base commit six earlier changes are open under `.specsync/changes/`.
They belong to other sessions and are not touched here. Until their owners
archive them, the Archive job on this pull request (and on every pull request)
stays red, which is the intended behavior of the gate.

The same recipe already landed on CorvidLabs/chough (pull request 18).
