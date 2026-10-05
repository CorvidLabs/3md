---
change: retain-workflow-permissions-archive-evidence-and-correct-retrospective-delivery-history
artifact: design
---

# Design

Retain refs/heads/leif/evidence-workflow-permissions-777427d at the original commit. This historical evidence branch must remain while the archive relies on it. It is not a feature to merge or a release tag; forced updates are not authorized.

The repair feature branch starts at landed 8b09724 and adds documentation plus its own workflow-v2 lifecycle record. Add a correction rather than altering old cryptographic preimages. The historical evidence tree has generated/lifecycle differences from main; compare its workflow and product files separately.
