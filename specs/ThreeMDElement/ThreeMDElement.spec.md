---
module: ThreeMDElement
version: 1
status: draft
files:
  - element/src/three-md.ts
  - element/three-md.d.ts

db_tables: []
depends_on: []
---

# ThreeMDElement

## Purpose

ThreeMDElement is the canonical, framework-agnostic interactive renderer for the
3md format: the `<three-md>` custom element. It owns the visual only - a 3D stack
of planes you can scrub, drag, and step through along the document's Z axis. It
does NOT parse 3md text; parsing is delegated to `@corvidlabs/threemd`, the
shared, conformance-tested data layer, whose `parse` turns source into a typed
`Document` of `Plane` values. The authoritative format definition lives in
`SPEC.md`; this module spec describes the rendering element that displays a
parsed document. The element is published as `@corvidlabs/three-md-element`.
Its package version follows the ThreeMD release version, and it renders format
version 1.0; the package version is not the format version.

The element stays text-only in ThreeMD 2.1. It does not decode general binary
storage (`.3mdb`, payload kind 1 or 2), and its published bundle carries no
storage code: although `element/src/three-md.ts` imports only `parse`, the
library's storage modules are in its module graph and must tree-shake away
completely.

## Public API

### Custom element

| Name | Description |
|------|-------------|
| `<three-md>` | The custom element tag, registered as `three-md` via `customElements.define`. |
| `ThreeMDElement` | The `HTMLElement` subclass backing the tag, exported from the module. |
| `Mode` | The render mode union: `stack`, `play`, `layers`, `scene`, `parallax`, `present`, `elevator`. |

### Attributes

| Attribute | Description |
|-----------|-------------|
| `src` | URL of a `.3md` file to fetch and render. When absent, inline text content is used as source. |
| `mode` | Override the render mode. Accepts a `Mode` value or an axis name (for example `time`, `frame`, `layer`, `depth`, `space`); an axis name maps to its mode. When unset, the mode is chosen from the document's `axis`. |

`observedAttributes` is `["src", "mode"]`. Inline text content (the `.3md`
source between the tags) is the source when no `src` is given.

### Properties and methods

| Member | Signature | Description |
|--------|-----------|-------------|
| `document` | `get document(): Document \| null` | The parsed document, or `null` before content has loaded. |
| `currentIndex` | `get currentIndex(): number` | The index of the currently focused plane (`Math.round` of the focus). |
| `mode` | `get mode(): Mode` | The active render mode. |
| `goTo` | `goTo(index: number): void` | Focus a plane by index, clamped to range. |
| `setSource` | `setSource(source: string): void` | Replace the rendered document with new 3md source text. |
| `render` | `render(): void` | Apply the current state to the DOM synchronously. The single source of truth for what the stage looks like. |

### Events

| Event | Detail | Description |
|-------|--------|-------------|
| `planechange` | `{ index, z, label, plane }` | Dispatched when the focused plane changes. Bubbles and is composed so it crosses the shadow boundary. |

### Theming

The element renders inside an open shadow root for style isolation. It is themed
through CSS custom properties (for example `--three-md-accent`, `--three-md-bg`,
`--three-md-surface`, `--three-md-text`, `--three-md-muted`, `--three-md-hairline`,
`--three-md-height`, `--three-md-plane-width`) and exposes internals through
`::part`: `wrap`, `axis`, `stage`, `arrow`, `scene`, `hint`, `controls`, `prev`,
`scrubber`, `next`, `readout`, `plane`, `plane-title`, `plane-body`, `grid`, and
`error`.

## Invariants

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

## Behavioral Examples

```
Given a <three-md> with inline 3md source declaring three planes
When the element upgrades and connects
Then it parses the source through @corvidlabs/threemd, builds one plane node per
     plane, and renders the focused plane frontmost in true Z
```

```
Given the scrubber is dragged to a new value
When the input event fires
Then the focus snaps to that value and render() runs synchronously, so the newly
     focused plane is frontmost even with requestAnimationFrame paused
```

```
Given the next button is clicked while plane 0 is focused
When the focus advances to plane 1
Then a planechange event is dispatched once with detail { index: 1, z: 1, label,
     plane }
```

## Error Cases

| Condition | When | Behavior |
|-----------|------|----------|
| Empty source | Inline content or fetched text is blank | Renders the error part with "No 3md source provided." |
| Invalid 3md | `parse` throws on malformed source | Renders the error part with "Invalid 3md: <message>"; no planes are built |
| Fetch failure | `src` returns a non-ok status or the request rejects | Renders the error part with "Could not load <src>: <message>" |
| Stale load | A newer `src` load supersedes an in-flight one | The stale response is discarded by load token; only the latest source renders |
| Binary source | `src` or inline content is a `.3mdb` container | The element stays text-only: the text does not begin with frontmatter, so `parse` throws and the error part shows "Invalid 3md: <message>" |

## Dependencies

- `@corvidlabs/threemd` (the shared parser; provides `parse`, `Document`, and
  `Plane`). All parsing is delegated to it; the element does not parse 3md text.
- The DOM and the Custom Elements, Shadow DOM, and Pointer Events platform APIs.
  `requestAnimationFrame` is used only for optional idle drift.
- The bundle invariant is enforced by `scripts/check-element-bundle.mjs`, the
  `element-bundle` step of the `verify` lane.

## Change Log

| Version | Date | Changes |
|---------|------|---------|
| 1 | 2026-06-23 | Initial spec for the `<three-md>` element: attributes (`src`, `mode`), properties (`document`, `currentIndex`, `mode`), methods (`goTo`, `setSource`, `render`), the `planechange` event, the seven render modes, theming through CSS custom properties and `::part`, and the three rendering invariants. Renders format 1.0; package version 1.0.0. |
