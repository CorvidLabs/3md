---
change: stabilize-viewer-canvas-resizing-and-webgl-context-recovery
artifact: context
---

# Context

Leif reported repeated WebGL context loss and ResizeObserver undelivered notifications after the viewer/site adoption. Direct resize callbacks mutate the observed layout; lost contexts are retried on every draw. Slice zoom currently allocates the complete enlarged grid (3840 squared in a modest viewport). This repair is confined to browser drawables and scheduling. Native camera mathematics, editing semantics, parser/storage and trust policies remain unchanged.

PR95 and site PR528 merged. Leif's continued Safari failure report keeps this approved repair active. The startup path failed to latch null/already-lost contexts before event delivery; resource creation also lacked null guards. The follow-up covers that same loss-suspension/restoration requirement, with actual Safari and deterministic startup/resource regressions. No new camera, loader, format or trust-policy scope is added.
