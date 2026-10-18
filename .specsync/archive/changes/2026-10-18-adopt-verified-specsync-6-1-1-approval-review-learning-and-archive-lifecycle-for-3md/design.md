---
change: adopt-verified-specsync-6-1-1-approval-review-learning-and-archive-lifecycle-for-3md
artifact: design
---

# Design

## Operations design

Pin the installed lifecycle writer and Trust selector to 6.1.1, retain Trust 1.2.2 and Fledge pins. Extend root meaningful paths to gdscript/, apps/sculpt/ and .agents/. Root lifecycle owns Sculpt operations; preserve nested specs and the existing Linux Sculpt and macOS app lanes. Do not invent a nested SDD policy or change its hashes.

The guard runs separately from canonical validation and product tasks to avoid recursive verification. It checks exact engine, required flags and native strict active audit, then refuses unfinished active workspaces. It never changes state, signs evidence, or repairs archives. Inherited debt is a blocker rather than a baseline exemption.

Learning stays in native change context/lesson bundles and applicable existing skills. Stronger risk and provenance controls remain unchanged.
