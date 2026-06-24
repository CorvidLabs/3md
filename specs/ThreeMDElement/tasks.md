---
spec: ThreeMDElement.spec.md
---

## Tasks

ThreeMDElement is the canonical `<three-md>` web component: a framework-agnostic
interactive renderer for the 3md format, backed by `@corvidlabs/threemd` for
parsing. The element renders format version 1.0 and ships as package version
1.0.0. The renderer is implemented in `element/src/three-md.ts` and guarded by
the cross-browser Playwright suite in `uitests/component.spec.mjs`. The sections
below track what is done and what is still open.

### Done

The full render/interact path is implemented and the three invariants are pinned
by cross-browser tests.

- [x] `ThreeMDElement` custom element registered as `three-md`, with an open
      shadow root and a built-once DOM (wrap, axis, stage, scene, controls)
- [x] Source loading: inline text content, `src` fetch with a load-token
      staleness guard, and `setSource(text)` to replace the document
- [x] Delegated parsing through `parse` from `@corvidlabs/threemd`; the element
      reads `document.planes` and each plane's `z`, `x`, `y`, `label`, `body`
- [x] Error handling: blank source, invalid 3md, and fetch failure render the
      error part rather than throwing
- [x] `observedAttributes` `["src", "mode"]` with `attributeChangedCallback`
      reloading on `src` and re-rendering on `mode`
- [x] Seven render modes (`stack`, `play`, `layers`, `scene`, `parallax`,
      `present`, `elevator`) and mode selection from `document.axis` via
      `AXIS_MODE`, overridable by the `mode` attribute and axis-name mapping
- [x] Focus-relative positioning (`d = idx - focus`) so the focused plane is
      frontmost in true Z (invariant 1)
- [x] Synchronous `render()` independent of `requestAnimationFrame`, with the rAF
      loop as optional idle drift only (invariant 2)
- [x] `touch-action: none` stage with unified pointer handling: vertical drag
      moves along Z, horizontal drag orbits; no horizontal overflow 320-1440px
      (invariant 3)
- [x] Scrubber, prev/next buttons, arrow-key stepping, click-to-focus, and
      `goTo(index)`, all snapping focus and rendering synchronously
- [x] Read accessors `document`, `currentIndex`, and `mode`
- [x] `planechange` `CustomEvent` (bubbles, composed) with detail
      `{ index, z, label, plane }`, emitted once per focus-index change
- [x] Small Markdown subset for plane bodies (headings, lists, task items,
      blockquotes, inline code, bold, italic, fenced grid) with HTML escaping
- [x] Theming through CSS custom properties and `::part` (`wrap`, `axis`, `stage`,
      `arrow`, `scene`, `hint`, `controls`, `prev`, `scrubber`, `next`, `readout`,
      `plane`, `plane-title`, `plane-body`, `grid`, `error`)
- [x] Cross-browser Playwright suite (Chromium and WebKit) covering upgrade and
      render, the three invariants, and `planechange`, with a clean-console check

### Next

Near-term work that builds directly on the 1.0 surface.

- [ ] Test coverage for the non-default render modes and the `mode` attribute
      override (including axis-name mapping)
- [ ] Test coverage for the error paths (blank source, invalid 3md, failing
      `src` fetch) and the load-token staleness guard
- [ ] Test coverage for pointer/touch drag and keyboard navigation, plus direct
      tests of `goTo`, `setSource`, `document`, `currentIndex`, and `mode`
- [ ] Accessibility pass: focus management, reduced-motion handling, and ARIA on
      the scrubber, buttons, and live readout

### Later

Open questions tied to format-level features from `SPEC.md`. These require the
data layer and shared vectors to lead before the renderer follows.

- [ ] Render cross-plane `[[z=N]]` links as anchors that navigate to the target
      plane
- [ ] A fuller CommonMark plane-body renderer (tables, images, nested lists)
- [ ] Per-plane transition or timing hints for the `frame` and `time` axes
- [ ] Inline 3D model embeds once the format defines them
