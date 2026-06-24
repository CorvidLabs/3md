---
spec: ThreeMDElement.spec.md
---

# ThreeMDElement Requirements

These requirements describe the `<three-md>` custom element: the canonical
interactive renderer for the 3md format. They are traceable against `SPEC.md`
(the format definition), the cross-browser tests in `uitests/component.spec.mjs`,
and the implementation in `element/src/three-md.ts`. The element renders a
parsed document; it delegates all parsing to `@corvidlabs/threemd`. Each
requirement is numbered so tests and reviews can reference it directly.

## User Stories

- As a web developer, I want a single custom element that renders a 3md document
  the same way in plain HTML, React, Vue, Svelte, and Angular so I do not
  reimplement the viewer per app.
- As a reader, I want to scrub, drag, step, and use arrow keys to move through a
  document's Z axis so I can explore stacked planes.
- As an author, I want the focused plane to always be the one in front, even in
  Safari and on a throttled iPhone, so the viewer never lies about what is
  selected.
- As a designer, I want to theme the element with CSS custom properties and
  target its internals with `::part` so it fits a site without forking it.
- As an integrator, I want a `planechange` event and `document`, `currentIndex`,
  and `mode` reads so I can react to navigation from my own code.

## Acceptance Criteria

### Functional Requirements

- **FR-1 (Parsing is delegated).** The element does not parse 3md text. It calls
  `parse` from `@corvidlabs/threemd` to turn source into a `Document` and reads
  `document.planes` and each plane's `z`, `x`, `y`, `label`, and `body`. The
  format grammar lives in `SPEC.md` and the shared parser; this element only
  renders the result.

- **FR-2 (Source resolution).** On connect, if the `src` attribute is set the
  element fetches that URL and renders the response text; otherwise it renders
  its inline text content. `setSource(text)` replaces the rendered document with
  new source at any time, building the DOM first if needed.

- **FR-3 (`src` fetch and staleness).** Fetching `src` is asynchronous and
  guarded by a load token: each load increments the token, and a response whose
  token no longer matches the latest is discarded. A non-ok HTTP status or a
  rejected request renders the error part with a message naming the source.

- **FR-4 (Empty and invalid source).** Blank source (after trim) renders the
  error part with "No 3md source provided." When `parse` throws, the element
  renders the error part with "Invalid 3md: <message>" and builds no planes.

- **FR-5 (Observed attributes).** `observedAttributes` is `["src", "mode"]`.
  Changing `src` triggers a fetch and render; changing `mode` re-applies the mode
  and re-renders. Attribute changes before the element has built its DOM are
  ignored until connect.

- **FR-6 (Mode selection).** The active `Mode` is one of `stack`, `play`,
  `layers`, `scene`, `parallax`, `present`, `elevator`. The `mode` attribute may
  be a `Mode` value or an axis name; an axis name (for example `time`, `frame`,
  `frames`, `layer`, `layers`, `depth`, `space`, `scene`, `slide`, `slides`,
  `deck`, `floor`, `floors`) maps to its mode. With no usable `mode` attribute,
  the mode is derived from `document.axis`, defaulting to `stack`.

- **FR-7 (Focus-relative layout).** Each plane is positioned by its distance
  from the focus, `d = idx - focus`, so the focused plane is frontmost at the
  largest true Z. The layout MUST NOT pin a fixed plane to the front, because
  Safari paints by true Z and ignores `z-index` inside `preserve-3d`.

- **FR-8 (Synchronous render).** `render()` applies all current state to the DOM
  synchronously and is the single source of truth for the stage. It is called on
  every interaction (scrub, drag, step, key, pointer up) and does not depend on
  `requestAnimationFrame`.

- **FR-9 (Optional animation loop).** The `requestAnimationFrame` loop adds only
  gentle idle drift and is progressive enhancement. Every value it produces is
  also produced by a direct interaction plus a synchronous `render()`, so the
  element stays fully correct and usable when rAF is throttled or never fires
  (iOS Low Power Mode). The loop is started on connect and cancelled on
  disconnect.

- **FR-10 (Pointer interaction).** The stage handles `pointerdown`,
  `pointermove`, `pointerup`, and `pointercancel` through one unified path for
  mouse, touch, and pen. A vertical drag moves the focus along Z; a horizontal
  drag orbits the scene. Pointer capture is attempted and failures are tolerated.

- **FR-11 (Touch behavior and no overflow).** The stage sets
  `touch-action: none` so a finger drives the model rather than scrolling the
  page. The element is `max-width: 100%` and `box-sizing: border-box` and MUST
  NOT overflow horizontally at any width from 320px to 1440px.

- **FR-12 (Scrubber, buttons, and keys).** A range input scrubs the Z axis; its
  max is the last plane index. Prev and next buttons step the focus by one. Arrow
  keys step too: Right or Up advances, Left or Down retreats. Each of these snaps
  the focus to the target and renders synchronously.

- **FR-13 (Read accessors).** `document` returns the parsed `Document` or `null`
  before load. `currentIndex` returns the rounded focus index. `mode` returns the
  active `Mode`. `goTo(index)` focuses a plane by index, clamped to range.

- **FR-14 (planechange event).** When the rounded focus index changes, the
  element dispatches a single `planechange` `CustomEvent` whose detail is
  `{ index, z, label, plane }`. The event bubbles and is composed so it crosses
  the shadow boundary. It is not re-emitted while the focused index is unchanged.

- **FR-15 (Plane rendering and Markdown subset).** Each plane renders a tag line
  (its `z` and `label`, or `z <value>` when unlabeled) plus a body rendered with
  a deliberately small Markdown subset: headings, ordered and unordered list
  items, task items, blockquotes, inline code, bold, italic, and a fenced-block
  grid. All text is HTML-escaped before formatting.

- **FR-16 (Shadow DOM, theming, and parts).** The element attaches an open
  shadow root and isolates its styles there. It is themeable through CSS custom
  properties and exposes internals through `::part`: `wrap`, `axis`, `stage`,
  `arrow`, `scene`, `hint`, `controls`, `prev`, `scrubber`, `next`, `readout`,
  `plane`, `plane-title`, `plane-body`, `grid`, and `error`.

### Non-Functional Requirements

- **NFR-1 (Framework agnostic).** As a standard custom element, `<three-md>`
  works unchanged in plain HTML and in React, Vue, Svelte, and Angular. There is
  one tested renderer, not a per-app reimplementation.

- **NFR-2 (Cross-browser tested).** The element is covered in CI by the Playwright
  suite under `uitests/`, run in both Chromium and WebKit, guarding the three
  invariants and a clean console.

- **NFR-3 (Self-contained bundle).** The published bundle includes the parser, so
  loading the one module is enough; no separate parser script is required.

- **NFR-4 (Style isolation).** All component styles live inside the shadow root
  so the host page cannot leak in and the component cannot leak out, except
  through the documented custom properties and parts.

- **NFR-5 (Resilience).** The element degrades gracefully: it tolerates absent
  pointer capture, a missing `requestAnimationFrame`, fetch failures, and invalid
  source, surfacing problems through the error part rather than throwing.

## Constraints

- The format definition in `SPEC.md` is authoritative, and parsing conformance
  is owned by `@corvidlabs/threemd` and its shared vectors, not by this element.
- The element renders format version 1.0. Its package version is 1.0.0; that is
  the package release, not a format version bump.
- The Markdown rendered inside a plane body is a deliberately small subset
  matching the reference lab renderer, not full CommonMark.
- The element requires a DOM with Custom Elements, Shadow DOM, and Pointer
  Events. `requestAnimationFrame` is optional.

## Out of Scope

- Parsing, serializing, validating, or interpreting 3md or its grammar; that is
  delegated to `@corvidlabs/threemd`.
- Full CommonMark rendering of plane bodies, including tables, images, and nested
  structures beyond the documented subset.
- Editing, authoring, or persisting 3md documents.
- Resolving or rendering cross-plane `[[z=N]]` links (a format feature handled in
  the data layer and prose, not by this renderer).
- Server-side rendering, networking beyond fetching `src`, and any 3D engine
  beyond CSS 3D transforms.
