---
change: implement-generic-binary-storage-and-document-composition-with-specsync-6-and-trust-1-2-2
artifact: context
---

# Context

<!-- What led here: the problem, and how it was noticed. -->

<!-- What a session picking this up mid-flight needs to know: constraints,
     prior attempts, anything already ruled out. -->

Leif directly instructed: "make sure 3md is using spec-sync 6 and full sdd and I approve all. and also latest trust.. and make sure all of it is working". This authorizes this local definition scope and its approval, not a claim of human implementation-diff review, independent review, authenticated signature or completed verification.

Work is isolated at /private/tmp/3md-binary-composition-20261004 on leif/binary-composition-sdd from origin/main 8712c686b91a54a972b1ffcb7512055513990d73. The sibling checkout and Rook pin remain unchanged. SpecSync 6.0.0 workflow-v2 adoption was run, preserving historical workflow-v1 evidence. A scratch unapproved workflow-v1 draft created before adoption was removed before adopting; it had no approval or verification evidence.

Scope: general Document binary storage, self-contained named in-memory Document references, canonical contracts/docs and Trust 1.2.2 orchestration. No voxel expansion, language-port implementation, external resource resolver, UI or renderer.
