# Text-only element bundle for ThreeMD 2.1

## ADDED

### REQUIREMENT REQ-ThreeMDElement-022

The published `<three-md>` bundle SHALL stay text-only in ThreeMD 2.1 and SHALL contain no general storage code from `@corvidlabs/threemd`: the freshly built bundle SHALL contain none of the markers TextDecoder, Int32Array, Float32Array, DocumentStorageError, `Scalar fields cannot contain`, `structured payload` and getBigUint64, SHALL be at most 50,000 bytes, and SHALL still equal web/assets/three-md.js and, when present, element/dist/three-md.js. (Change requirement SB-28.)

Acceptance Criteria:
- scripts/check-element-bundle.mjs, the element-bundle step of the verify lane, asserts the markers are absent, the size is at most 50,000 bytes and the drift check passes.
- The library's storage.ts, structured.ts and checksum.ts have no top-level side effects, and canonicalNumber lives in the side-effect-free js/src/number.ts, so the parser has no import edge into storage.ts.
- A `.3mdb` source is not decoded: parse fails and the element shows its error part.
