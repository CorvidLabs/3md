---
change: add-stable-document-identities-transactional-patches-and-diagnostics-for-release-preparation
artifact: research
---

# Research

Existing Plane.attributes preserve unknown string keys, allowing id without grammar changes. Existing composition definitions already have IDs; keep those IDs and use opt-in reference attributes when identity is needed. Parser errors already carry some line evidence; additive diagnostics should reuse that evidence and add graph/plane paths without changing ParseError cases. Indexed storage, material profiles and full animation are later milestones.

