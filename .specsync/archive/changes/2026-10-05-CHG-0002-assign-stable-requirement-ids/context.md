---
change: CHG-0002-assign-stable-requirement-ids
artifact: context
---

# Context

SpecSync 5 uses durable requirement identifiers to connect canonical requirements, implementation,
and verification evidence. Existing requirement companions predate that convention, so this change
adds stable `REQ-*` identifiers while preserving their original acceptance language and meaning.
