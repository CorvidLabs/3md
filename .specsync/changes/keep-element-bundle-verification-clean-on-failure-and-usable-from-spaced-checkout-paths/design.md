---
change: keep-element-bundle-verification-clean-on-failure-and-usable-from-spaced-checkout-paths
artifact: design
---

# Design

Keep bundle contents, parser-only restrictions, byte budget and validation exit codes unchanged. Set process.exitCode on validation failure so finally removes the scratch directory, and emit success only on the success branch. Decode the source file URL with fileURLToPath. Test copied actual checker processes against minimal browser module fixtures, inspecting scratch before parent cleanup. Wire the regressions into the existing element-bundle task.
