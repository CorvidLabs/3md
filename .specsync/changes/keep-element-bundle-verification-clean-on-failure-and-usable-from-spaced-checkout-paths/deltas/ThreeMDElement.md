# ThreeMDElement delta

## MODIFIED

### Spec Section Invariants

1. Planes are positioned relative to the focus (`d = idx - focus`), so the
   selected plane is always frontmost at the largest true Z. A fixed
   `z = -idx * 150` layout would leave plane 0 in front no matter what is
   selected, which Safari exposes because it paints by true Z and ignores
   `z-index` inside `preserve-3d`.
2. `render()` is synchronous and is called on every interaction. It does not
   depend on `requestAnimationFrame`, so it stays correct when iOS Low Power Mode
   throttles or pauses rAF. The rAF loop only adds optional idle drift and the
   element is fully usable if it never runs.
3. The stage uses `touch-action: none` so a finger drives the model: a vertical
   drag moves along Z, a horizontal drag orbits. The element never overflows
   horizontally, from 320px to 1440px wide.
4. The element bundle contains no storage code and stays within a size budget.
   The freshly built bundle (`bun build element/src/three-md.ts --format esm
   --target browser --minify`) contains none of the markers `TextDecoder`,
   `Int32Array`, `Float32Array`, `DocumentStorageError`,
   `Scalar fields cannot contain`, `structured payload` and `getBigUint64`, and
   is at most 50,000 bytes (2.0.0: 48,816 bytes). This holds because the
   library's `storage.ts`, `structured.ts` and `checksum.ts` have no top-level
   side effects (every module-level initializer is a literal, a function or class
   declaration, or an expression marked `/* @__PURE__ */`; CRC tables, the
   `TextDecoder`, `TextEncoder`, `DataView` scratch buffers and typed arrays are
   created lazily), and because `canonicalNumber` lives in the pure
   `js/src/number.ts`, so the parser has no import edge into `storage.ts`. The
   fresh build still equals `web/assets/three-md.js` and, when present,
   `element/dist/three-md.js`.
5. Bundle verification removes its temporary build directory after both success
   and failure, preserves the committed bundles, and accepts checkout paths
   containing spaces. A failed validation exits nonzero without printing the
   success message.
