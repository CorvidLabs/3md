/**
 * <three-md> - the canonical, framework-agnostic interactive renderer for the
 * 3md format.
 *
 * Parsing is delegated to @corvidlabs/threemd (the shared, conformance-tested
 * data layer). This element owns only the visual: a 3D stack of planes you can
 * scrub, drag, and step through along the document's Z axis.
 *
 * Design invariants (these are the things that have actually broken before):
 *  1. Planes are positioned RELATIVE to the focus (d = idx - focus), so the
 *     selected plane is always frontmost at z = 0. A fixed z = -idx*150 layout
 *     leaves plane 0 in front no matter what is selected, which Safari exposes
 *     because it paints by true Z and ignores z-index inside preserve-3d.
 *  2. render() is synchronous and is called on every interaction. It does NOT
 *     depend on requestAnimationFrame, so it stays correct when iOS Low Power
 *     Mode throttles or pauses rAF. The rAF loop only adds optional idle drift.
 *  3. The stage uses touch-action: none so a finger drives the model: vertical
 *     drag moves along Z, horizontal drag orbits. The element never overflows
 *     horizontally.
 */

// Imported from source (not the built package) so the bundle never depends on
// js/dist being built first. bun inlines the parser into dist/three-md.js, so
// the published package is self-contained with zero runtime dependencies. This
// is the same code published as @corvidlabs/threemd.
import { parse, type Document, type Plane } from "../../js/src/index.ts";

// The renderer offers a small set of strong views. (Earlier builds had layers,
// parallax, elevator, and scene; those were weak or redundant and are folded in:
// see MODE_ALIAS, which keeps old documents and ?mode= values working.)
type Mode = "stack" | "play" | "single" | "present" | "blend" | "map" | "layers" | "elevator";

const VALID_MODES = ["stack", "play", "single", "present", "blend", "map", "layers", "elevator"] as const;

// Retired mode names map to their surviving equivalent so nothing breaks.
const MODE_ALIAS: Record<string, Mode> = {
  parallax: "stack", scene: "map", deck: "present",
};

const AXIS_MODE: Record<string, Mode> = {
  time: "stack",
  frame: "play",
  frames: "play",
  layer: "layers",
  layers: "layers",
  depth: "stack",
  space: "map",
  scene: "map",
  slide: "present",
  slides: "present",
  deck: "present",
  floor: "elevator",
  floors: "elevator",
};

// Modes driven by the orbit/pan/zoom camera (vs. flat reader/slides/flipbook).
const CAMERA_MODES: ReadonlySet<Mode> = new Set(["stack", "blend", "map", "layers", "elevator"]);

// The under-stage hint, tailored to how each view is driven.
const HINTS: Record<Mode, string> = {
  stack: "drag to orbit · WASD / arrows move · scroll to zoom · slider scrubs Z",
  layers: "aligned overlays — drag to orbit the stack · slider brings a layer to front",
  elevator: "floors stacked vertically — drag to orbit · slider rides the floors",
  map: "the full board · tap a tile to read it · tap empty space or Esc for the board · drag to orbit · scroll to zoom",
  blend: "drag to orbit the object · scroll to zoom",
  play: "animation — play / pause and loop in the controls",
  present: "arrows or space to advance slides",
  single: "scroll to read · arrows or slider change plane",
};

function esc(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

/** Escape for interpolation inside a double-quoted HTML attribute: also
 * neutralizes quote characters so a value can never break out of the attribute
 * (complete sanitization for the attribute sink). */
function escAttr(value: string): string {
  return esc(value).replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

/** Inline Markdown on already-escaped text: code, bold, italic. */
function inline(escaped: string): string {
  // Note: no `_italic_` rule - underscores are left alone so snake_case
  // identifiers (ship_to, acct_8821) render literally.
  return escaped
    // Cross-plane links: [[z=2|text]] or [[z=1.5|text]] become clickable jumps.
    // The z class matches the spec parser (decimals, sci-notation, +/-); bounded
    // quantifiers keep it linear-time (ReDoS-safe).
    .replace(/\[\[z=([-+0-9eE.]{1,40})(?:\|([^\]\n]{0,400}))?\]\]/g,
      (_m, z, text) => `<a class="xlink" part="link" data-z="${z}">${text || "z=" + z}</a>`)
    // Markdown links to http(s): [text](url). (Not preceded by ! so images are
    // left alone.) Only link URLs with no attribute-breaking characters; anything
    // else stays plain text, so the href sink is provably safe.
    .replace(/(^|[^!])\[([^\]]+)\]\((https?:\/\/[^)\s"'<>`]+)\)/g,
      (_m, pre, text, url) => `${pre}<a class="xlink" part="link" href="${escAttr(url)}" target="_blank" rel="noopener">${text}</a>`)
    .replace(/`([^`]+)`/g, "<code>$1</code>")
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/\*([^*]+)\*/g, "<em>$1</em>");
}

function fmt(text: string): string {
  return inline(esc(text));
}

/**
 * Parse the optional `legend:` frontmatter into a single-character substitution
 * map. Syntax: whitespace- or comma-separated `char=replacement` pairs, e.g.
 *   legend: g=🟫 w=🟦 .=·
 * The key is one source character; the value is what it renders as inside fenced
 * blocks (an emoji, symbol, or short string). Legends are entirely optional; with
 * no legend, fenced content renders exactly as written.
 */
function parseLegend(raw: string | null | undefined): Record<string, string> {
  const map: Record<string, string> = {};
  if (!raw) return map;
  for (const tok of raw.trim().split(/[\s,]+/)) {
    const eq = tok.indexOf("=");
    if (eq <= 0) continue;
    // Tolerate quoted keys/values, e.g. "#"=🟫, so characters that look special
    // in frontmatter can still be mapped.
    const rawKey = tok.slice(0, eq).replace(/^["']|["']$/g, "");
    const key = [...rawKey][0]; // one source character
    const val = tok.slice(eq + 1).replace(/^["']|["']$/g, "");
    // An empty value (e.g. `.=`) blanks the character: it renders as a space, so
    // a grid keeps its alignment but the character disappears. Values are HTML-
    // escaped here because applyLegend substitutes them into already-escaped fence
    // content that is later assigned to innerHTML: escaping at the single source
    // makes the legend sink provably safe (no markup injection from frontmatter).
    if (key) map[key] = val === "" ? " " : esc(val);
  }
  return map;
}

/** Apply a legend to a single line of (already HTML-escaped) fenced content. */
function applyLegend(escaped: string, legend: Record<string, string>): string {
  const keys = Object.keys(legend);
  if (!keys.length) return escaped;
  const cls = keys.map((k) => k.replace(/[.*+?^${}()|[\]\\\-]/g, "\\$&")).join("");
  return escaped.replace(new RegExp(`[${cls}]`, "g"), (c) => legend[c] ?? c);
}

/** A compact Markdown renderer: headings, lists, checkboxes, quotes, images,
 * fenced code, links, and GitHub-style tables. */
function renderMarkdown(body: string, legend: Record<string, string> = {}): string {
  const lines = body.split("\n");
  const fence = (rows: string[]) =>
    `<pre class="code" part="code">${rows.map((r) => applyLegend(esc(r), legend)).join("\n")}</pre>`;
  const isRow = (l: string) => /^\s*\|.*\|\s*$/.test(l);
  const isSep = (l: string) => /-/.test(l) && /^\s*\|?[\s:|-]*\|[\s:|-]*$/.test(l);
  const cells = (l: string) => l.trim().replace(/^\||\|$/g, "").split("|").map((c) => c.trim());
  const out: string[] = [];
  let code: string[] | null = null; // collecting a fenced code block
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i];
    if (l.startsWith("```")) {
      if (code === null) { code = []; }
      else { out.push(fence(code)); code = null; }
      continue;
    }
    if (code !== null) { code.push(l); continue; }
    // GitHub-style table: a header row, then a |---|---| separator, then rows.
    if (isRow(l) && i + 1 < lines.length && isSep(lines[i + 1])) {
      const head = cells(l);
      i += 2;
      const rows: string[][] = [];
      while (i < lines.length && isRow(lines[i])) { rows.push(cells(lines[i])); i++; }
      i--; // the for-loop will advance past the last consumed line
      out.push(
        `<table class="tbl" part="table"><thead><tr>${head.map((c) => `<th>${fmt(c)}</th>`).join("")}</tr></thead>`
        + `<tbody>${rows.map((r) => `<tr>${r.map((c) => `<td>${fmt(c)}</td>`).join("")}</tr>`).join("")}</tbody></table>`,
      );
      continue;
    }
    // Plane titles render as styled divs, not <h4>/<h5>, so the component never
    // injects headings that would break the host page's heading order (a11y).
    if (l.startsWith("# ")) out.push(`<div class="ph" part="plane-title">${fmt(l.slice(2))}</div>`);
    else if (l.startsWith("## ")) out.push(`<div class="ph2" part="plane-subtitle">${fmt(l.slice(3))}</div>`);
    else if (l.startsWith("### ")) out.push(`<div class="ph2" part="plane-subtitle">${fmt(l.slice(4))}</div>`);
    else if (l.startsWith("- [x] ") || l.startsWith("- [X] ")) out.push(`<div class="li"><span class="box">▣</span><span class="done">${fmt(l.slice(6))}</span></div>`);
    else if (l.startsWith("- [ ] ")) out.push(`<div class="li"><span class="box">▢</span><span>${fmt(l.slice(6))}</span></div>`);
    else if (/^\s*[-*] /.test(l)) { const t = l.replace(/^(\s*)[-*] /, "$1"); const indent = (l.match(/^\s*/)?.[0].length || 0) > 0; out.push(`<div class="li${indent ? " sub" : ""}"><span class="box">•</span><span>${fmt(t.trim())}</span></div>`); }
    else if (/^\d+\. /.test(l)) out.push(`<div class="li"><span class="box">${esc(l.slice(0, l.indexOf(".")))}</span><span>${fmt(l.slice(l.indexOf(".") + 2))}</span></div>`);
    else if (l.startsWith("> ")) out.push(`<div class="quote">${fmt(l.slice(2))}</div>`);
    else if (/^\s*(-{3,}|\*{3,}|_{3,})\s*$/.test(l)) out.push(`<hr class="rule">`);
    else if (/^!\[[^\]]*\]\([^)\s]+\)\s*$/.test(l.trim())) {
      // A Markdown image on its own line: ![alt](url). Renders images and GIFs.
      const m = l.trim().match(/^!\[([^\]]*)\]\(([^)\s]+)\)/);
      const alt = m ? escAttr(m[1]) : "";
      const url = m ? m[2] : "";
      // Allowlisted scheme AND no characters that could break out of the quoted
      // attribute. escAttr then fully neutralizes quotes/markup, so the sink is
      // sanitized both by rejection and by complete attribute escaping.
      const okUrl = /^(https?:\/\/|\/|\.{0,2}\/|data:image\/)/i.test(url) && !/["'<>`\s]/.test(url);
      const safe = okUrl ? escAttr(url) : "";
      if (safe) out.push(`<img class="img" part="image" src="${safe}" alt="${alt}" loading="lazy">`);
    }
    else if (l.trim() !== "") out.push(`<div>${fmt(l)}</div>`);
  }
  if (code !== null) out.push(fence(code));
  return `<div class="md" part="plane-body">${out.join("")}</div>`;
}

/** Uniform control-bar icons: one viewBox, one stroke weight, sized by CSS, so
 * every button reads at the same optical size (the old unicode glyphs did not). */
const SVG = (body: string, fill = false): string =>
  `<svg viewBox="0 0 24 24" ${fill ? 'fill="currentColor" stroke="none"' : 'fill="none" stroke="currentColor" stroke-width="2"'} stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${body}</svg>`;
const ICONS = {
  prev: SVG('<path d="M15 5l-7 7 7 7"/>'),
  next: SVG('<path d="M9 5l7 7-7 7"/>'),
  play: SVG('<path d="M8 5.5v13l11-6.5z"/>', true),
  pause: SVG('<path d="M9 5v14M15 5v14"/>'),
  loop: SVG('<path d="M3.5 12a8.5 8.5 0 0 1 14.5-6M20.5 12a8.5 8.5 0 0 1-14.5 6"/><path d="M18 2.5V6h-3.5M6 21.5V18h3.5"/>'),
  fullscreen: SVG('<path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"/>'),
};

const STYLES = `
:host {
  display: block;
  max-width: 100%;
  box-sizing: border-box;
  /* Themeable surface. Override these (or use ::part) to restyle. */
  --three-md-bg: var(--three-md-surface-strong, #131619);
  --three-md-surface: #1b2024;
  --three-md-text: #f4f3ef;
  --three-md-muted: #9aa3a8;
  --three-md-faint: #6b7479;
  --three-md-accent: #45d0bc;
  --three-md-hairline: rgba(244, 243, 239, 0.14);
  font-family: var(--three-md-font, ui-monospace, "Spline Sans Mono", SFMono-Regular, Menlo, monospace);
  color: var(--three-md-text);
}
* { box-sizing: border-box; }
:host(:focus) { outline: none; } /* no harsh ring on pointer/drag while flying */
/* Keyboard focus DOES get a visible indicator (WCAG 2.4.7); focus-visible never
   fires on pointer interaction, so it doesn't reappear while dragging. */
:host(:focus-visible) { outline: none; box-shadow: 0 0 0 2px var(--three-md-accent); border-radius: 8px; }
/* An errored or empty document has no live scene: hide its stale controls. */
:host([data-state="error"]) .controls, :host([data-state="empty"]) .controls,
:host([data-state="error"]) .hint, :host([data-state="empty"]) .hint,
:host([data-state="error"]) .readout, :host([data-state="empty"]) .readout { display: none; }
@media (prefers-reduced-motion: reduce) {
  .plane, .scene, .floattext { transition-duration: .001ms !important; }
}
.wrap { width: 100%; max-width: 100%; }
.axis { font-size: 12px; letter-spacing: .14em; text-transform: uppercase; color: var(--three-md-accent); margin: 0 0 8px; }
.stage {
  position: relative; width: 100%; height: var(--three-md-height, 440px);
  border: 1px solid var(--three-md-hairline); border-radius: 8px;
  background: var(--three-md-bg); overflow: hidden;
  perspective: 1300px; perspective-origin: 50% 44%;
  cursor: grab; touch-action: none; user-select: none; -webkit-user-select: none;
}
.stage:active { cursor: grabbing; }
.scene { position: absolute; inset: 0; transform-style: preserve-3d; }
/* Flat 2D overlay for the focus-to-read card: lives OUTSIDE the perspective'd
   scene so the read card is never skewed by the board's tilt. Clicks pass through
   to the board behind, except on the card itself. */
.detail { position: absolute; inset: 0; display: none; align-items: center; justify-content: center; pointer-events: none; z-index: 5; }
:host([data-mode="map"]) .detail { display: flex; }
.detail .plane.popped { pointer-events: auto; position: relative; inset: auto; left: auto; top: auto; right: auto; bottom: auto;
  margin: 0; height: max-content; max-height: none; transform-origin: center center; }
/* The hint sits BELOW the stage, never over the plane content. */
.hint { margin: 8px 2px 0; font-size: 11px; color: var(--three-md-faint); }
.fs { margin-left: auto; }
.md .img, [part="image"] { display: block; max-width: 100%; height: auto; border-radius: 6px; margin: 8px 0; }
:host(:fullscreen) { background: var(--three-md-bg); padding: 2.5vh 3vw; box-sizing: border-box; }
:host(:fullscreen) .wrap { height: 100%; display: flex; flex-direction: column; }
:host(:fullscreen) .stage { flex: 1 1 auto; height: auto; }
:host(:fullscreen) .hint { display: none; } /* no instructional text over a presentation */
/* Fullscreen is a real reading/slideshow experience, not a bigger thumbnail:
   scale the type up, and turn card views into a wide, centered slide. */
:host(:fullscreen) .md, :host(:fullscreen) .grid { font-size: clamp(14px, 1.6vw, 21px); line-height: 1.7; }
:host(:fullscreen) .md .ph { font-size: clamp(20px, 2.6vw, 34px); }
:host(:fullscreen) .md .ph2 { font-size: clamp(15px, 1.7vw, 22px); }
:host(:fullscreen) .md .code { font-size: clamp(12px, 1.2vw, 16px); }
:host(:fullscreen) .ptag { font-size: clamp(11px, 1vw, 14px); }
:host(:fullscreen) .navbtn { width: 44px; height: 40px; }
:host(:fullscreen) .navbtn svg { width: 18px; height: 18px; }
/* Reader (single) and present become big centered slides. */
:host(:fullscreen[data-mode="single"]) .plane.reader {
  width: min(70vw, 900px); max-width: min(70vw, 900px); padding: clamp(20px, 3vw, 44px);
}
:host(:fullscreen[data-mode="present"]) .plane.hot {
  max-width: min(82vw, 1100px); padding: clamp(20px, 3vw, 44px);
}
.plane {
  position: absolute; left: 50%; top: 50%;
  width: min(var(--three-md-plane-width, 320px), 84%);
  margin-left: calc(min(var(--three-md-plane-width, 320px), 84%) / -2); margin-top: -104px;
  /* Keep cards inside the stage: cap height and clip; the focused card scrolls. */
  max-height: calc(100% - 18px); overflow: hidden;
  border-radius: 8px; padding: 14px 16px;
  background: var(--three-md-surface); border: 1px solid var(--three-md-accent);
  box-shadow: 0 18px 44px rgba(0,0,0,.45); cursor: pointer;
  transition: opacity .3s, box-shadow .3s, filter .3s;
}
.plane.hot { overflow-y: auto; } /* the focused card can scroll long content */
/* In card modes the focused card hugs its CONTENT (so a short plane is a small
   card, not a big empty box), stays vertically centered via auto margins, and only
   caps + scrolls when the content is genuinely taller than the stage. */
:host([data-mode="stack"]) .plane.hot,
:host([data-mode="elevator"]) .plane.hot,
:host([data-mode="present"]) .plane.hot {
  top: 0; bottom: 0; left: 0; right: 0; height: max-content; max-height: calc(100% - 20px);
  margin: auto; overflow-y: auto;
  /* Grow to fit WIDE content (grids, tables) up to a readable cap, so nothing is
     clipped on the sides; prose still wraps at ~64ch. Auto margins centre it. */
  width: max-content; min-width: min(var(--three-md-plane-width, 320px), 84%);
  max-width: min(64ch, calc(100% - 20px));
}
/* Layers: EVERY overlay (not just the focused one) is a centered, stage-height,
   scrollable box so a layer of any length fits in frame; they sit perfectly
   aligned, with depth + opacity (not a vertical fan) giving the stacked look. */
:host([data-mode="layers"]) .plane {
  top: 8px; bottom: 8px; height: auto; margin-top: 0; max-height: none; overflow-y: auto;
}
/* Map: each tile is a bounded, centered, scrollable card (margin-top matches half
   the cap) so a tall tile stays on the board instead of spilling off the bottom. */
:host([data-mode="map"]) .plane {
  max-height: 180px; margin-top: -90px; overflow-y: auto;
}
/* Layers: aligned translucent overlays seen together (not one-at-a-time). */
.layerchips { display: none; gap: 6px; flex-wrap: wrap; margin-top: 8px; }
:host([data-mode="layers"]) .layerchips { display: flex; }
.layerchip { font: inherit; font-size: 11px; color: var(--three-md-muted); background: var(--three-md-surface);
  border: 1px solid var(--three-md-hairline); border-radius: 999px; padding: 4px 11px; cursor: pointer;
  transition: color .15s, border-color .15s, opacity .15s; }
.layerchip:hover { color: var(--three-md-text); border-color: var(--three-md-accent); }
.layerchip[aria-pressed="true"] { color: var(--three-md-text); border-color: var(--three-md-accent); }
.layerchip[aria-pressed="false"] { opacity: .45; text-decoration: line-through; }
.plane.dim { opacity: .18; filter: saturate(.5); }
.plane.hot { box-shadow: 0 0 0 2px var(--three-md-accent), 0 18px 44px rgba(0,0,0,.5); }
/* Reader: the focused plane in single-card view fills the stage and scrolls its
   own body, so a plane of any length stays fully readable. Navigation moves to
   the slider, arrows, and keyboard; the body scrolls with wheel or touch. */
/* Reader (single): every plane shares ONE fixed, scrollable box, so changing
   plane never resizes or shifts the card - the content just swaps and scrolls. */
:host([data-mode="single"]) .plane {
  top: 50%; left: 50%; transform: translate(-50%, -50%) !important;
  width: min(var(--three-md-plane-width, 560px), 92%); height: calc(100% - 14px);
  margin: 0; max-width: none; max-height: none; overflow-y: auto; overscroll-behavior: contain;
  touch-action: pan-y; -webkit-overflow-scrolling: touch; cursor: auto; transition: opacity .15s;
  -webkit-user-select: text; user-select: text;
}
/* Flipbook frame (animations): a FIXED-size centered card (not content-sized, so
   it never grows/shrinks between frames; not full-bleed, so small animations are
   not lost in a huge box). Content is centered; swaps are instant (no ghosting). */
.plane.frame {
  top: 50%; left: 50%;
  /* Natural content size (measured in JS) scaled to fit the stage, so every frame
     is the same size AND the whole animation is visible with NO scrollbars. */
  transform: translate(-50%, -50%) scale(var(--three-md-frame-scale, 1)) !important;
  width: var(--three-md-frame-w, min(var(--three-md-plane-width, 360px), 88%));
  height: var(--three-md-frame-h, min(72%, 340px)); margin: 0;
  display: flex; flex-direction: column; justify-content: center; align-items: center;
  /* Real animations fit via the scale, so no scrollbar appears; only content that
     genuinely cannot fit (e.g. a long text doc forced into animation) scrolls. */
  overflow: auto; transition: none;
}
:host([data-mode="play"]) .plane { transition: none; } /* instant frame swaps */
/* No accidental text selection while orbiting/flying; the reader stays selectable. */
.scene, .plane { -webkit-user-select: none; user-select: none; }
.plane.reader { -webkit-user-select: text; user-select: text; }
.ptag { font-size: 10.5px; letter-spacing: .08em; text-transform: uppercase; color: var(--three-md-accent); display: flex; justify-content: space-between; margin-bottom: 8px; }
.ptag b { color: var(--three-md-text); font-weight: 700; }
.md, .grid { font-size: 12.5px; line-height: 1.65; color: var(--three-md-muted); }
.md .ph { font-family: var(--three-md-display, inherit); font-weight: 700; font-size: 16px; margin: 2px 0 8px; color: var(--three-md-text); }
.md .ph2 { font-weight: 700; font-size: 13px; margin: 6px 0 6px; color: var(--three-md-text); }
.md .code { margin: 6px 0; padding: 8px 10px; background: var(--three-md-hairline); border-radius: 4px; font-size: 11.5px; line-height: 1.5; white-space: pre; overflow-x: auto; max-width: 100%; color: var(--three-md-text); }
.md .li { display: flex; gap: 8px; }
.md .box { color: var(--three-md-accent); }
.md .done { color: var(--three-md-faint); text-decoration: line-through; }
.md .quote { border-left: 2px solid var(--three-md-hairline); padding-left: 10px; color: var(--three-md-faint); font-style: italic; }
.md .li.sub { padding-left: 16px; }
.md .rule { border: 0; border-top: 1px solid var(--three-md-hairline); margin: 8px 0; }
.md .tbl { border-collapse: collapse; margin: 8px 0; font-size: 12px; max-width: 100%; }
.md .tbl th, .md .tbl td { border: 1px solid var(--three-md-hairline); padding: 4px 8px; text-align: left; vertical-align: top; }
.md .tbl th { color: var(--three-md-text); font-weight: 700; background: var(--three-md-hairline); }
.md .tbl td { color: var(--three-md-muted); }
.md strong { color: var(--three-md-text); font-weight: 700; }
.md em { font-style: italic; }
.md code { font-family: inherit; background: var(--three-md-hairline); padding: 1px 5px; border-radius: 3px; color: var(--three-md-text); }
.grid { font-size: 16px; line-height: 1.25; letter-spacing: 3px; color: var(--three-md-faint); white-space: pre; max-width: 100%; overflow-x: auto; }
.grid .dot { color: var(--three-md-accent); }
/* A voxel IS its character glyph (legend-remapped): emoji/symbols render in full
   colour, plain chars in the accent. Depth is cued by opacity (near = focused). */
.voxel { position: absolute; left: 50%; top: 50%; width: 14px; height: 14px; margin: -7px 0 0 -7px;
  display: flex; align-items: center; justify-content: center;
  font-family: var(--three-md-mono, ui-monospace, "Spline Sans Mono", monospace);
  font-size: 13px; line-height: 1; color: var(--three-md-accent); opacity: .4;
  transition: opacity .2s; pointer-events: none; }
.voxel.near { opacity: 1; }
.floattext { position: absolute; left: 50%; top: 50%; font-size: 11px; line-height: 1.5;
  color: var(--three-md-faint); opacity: .5; white-space: pre; pointer-events: none; }
/* nowrap so the button row never reflows and shifts under the cursor. */
.controls { display: flex; align-items: center; gap: 8px; margin-top: 12px; flex-wrap: nowrap; }
.navbtn { flex: 0 0 auto; display: inline-flex; align-items: center; justify-content: center; color: var(--three-md-text); background: var(--three-md-surface); border: 1px solid var(--three-md-hairline); width: 38px; height: 34px; border-radius: 4px; cursor: pointer; }
.navbtn svg { width: 16px; height: 16px; display: block; }
.navbtn:hover { border-color: var(--three-md-accent); color: var(--three-md-accent); }
.navbtn.loop[aria-pressed="true"] { color: var(--three-md-accent); border-color: var(--three-md-accent); }
.navbtn.loop[aria-pressed="false"] { opacity: .55; }
input[type=range] { flex: 1 1 auto; min-width: 48px; accent-color: var(--three-md-accent); cursor: pointer; }
/* readout on its own line, so its changing width never moves the buttons. */
.readout { font-size: 12.5px; color: var(--three-md-muted); margin-top: 8px; min-height: 16px; }
.readout b { color: var(--three-md-accent); }
.md .xlink, [part="link"] { color: var(--three-md-accent); text-decoration: underline; text-underline-offset: 2px; cursor: pointer; }
.md .xlink:hover { opacity: .8; }
.err { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center;
  text-align: center; padding: 24px; color: var(--three-md-error, #ff8f8f); font-size: 13px; line-height: 1.6; }
:host([data-state="empty"]) .err { color: var(--three-md-muted); } /* empty is not an error */
`;

export class ThreeMDElement extends HTMLElement {
  static get observedAttributes(): string[] {
    return ["src", "mode", "autoplay"];
  }

  private _root: ShadowRoot;
  private _scene!: HTMLDivElement;
  private _stage!: HTMLDivElement;
  private _detail!: HTMLDivElement; // flat overlay (outside the 3D scene) for the focus-to-read card
  private _axisEl!: HTMLDivElement;
  private _scrub!: HTMLInputElement;
  private _readout!: HTMLDivElement;
  private _hintEl!: HTMLDivElement;
  private _wrap!: HTMLDivElement;

  private _doc: Document | null = null;
  private _planes: readonly Plane[] = [];
  private _els: HTMLDivElement[] = [];
  private _voxels: HTMLDivElement[] = [];
  private _billboard = false;
  private _mode: Mode = "stack";
  private _legend: Record<string, string> = {};

  private _focus = 0;
  private _target = 0;
  // Orbit/pan/zoom camera (used in stack, blend, map). yaw/pitch in degrees,
  // pan in px, zoom in px added to the base distance.
  private _yaw = 0;
  private _pitch = 0;
  private _panX = 0;
  private _panY = 0;
  private _zoom = 0;

  private _dragging = false;
  private _mapOverview = true; // map shows the whole board until a tile is opened
  private _downTarget: HTMLElement | null = null;
  private _lastX = 0;
  private _lastY = 0;
  private _dragStartX = 0;
  private _dragStartY = 0;
  private _dragStartTarget = 0;
  private _dragAxis: "x" | "y" | null = null;
  private _pointerId: number | null = null;
  private _pendingDrag = false;
  private _hiddenLayers = new Set<number>(); // layers toggled off in layers view
  private _chipsEl!: HTMLDivElement;
  private _keys = new Set<string>();
  private _camRaf: number | null = null;
  private _lastEmitted = -1;
  private _error: string | null = null;
  private _errorLine: number | null = null;
  private _errorCode: string | null = null;
  private _loadToken = 0;
  private _playBtn!: HTMLButtonElement;
  private _loopBtn!: HTMLButtonElement;
  private _loop = true;
  private _playing = false;
  private _playTimer: ReturnType<typeof setInterval> | null = null;

  constructor() {
    super();
    this._root = this.attachShadow({ mode: "open" });
  }

  connectedCallback(): void {
    this._build();
    const src = this.getAttribute("src");
    if (src) {
      void this._loadFromSrc(src);
    } else {
      this._loadFromText(this.textContent || "");
    }
  }

  disconnectedCallback(): void {
    this._stopPlay();
  }

  attributeChangedCallback(name: string, _old: string | null, value: string | null): void {
    if (!this._scene) return;
    if (name === "src" && value) {
      void this._loadFromSrc(value);
    } else if (name === "mode") {
      const wasBlend = this._mode === "blend";
      this._applyMode();
      // blend renders voxels, every other mode renders plane cards: crossing that
      // boundary needs a DOM rebuild, otherwise a dynamic switch into blend leaves
      // stale cards and zero voxels (and a switch out leaves stale voxels).
      if (wasBlend || this._mode === "blend") this._buildPlanes();
      this._resetCamera(); // each view has its own default camera
      this._buildLayerChips(); // show/hide the layer toggles for this view
      this.render();
    } else if (name === "autoplay") {
      if (value !== null) this._startPlay(); else this._stopPlay();
    }
  }

  // MARK: - Public API

  /** The parsed document, or null before content has loaded or when the most
   * recent load failed to parse. Callers should check `error` first; a stale
   * document is never returned after an error. */
  get document(): Document | null {
    return this._error ? null : this._doc;
  }

  /** The 1-based source line a parse error was attributed to, or null. */
  get errorLine(): number | null {
    return this._errorLine;
  }

  /** The stable parser error code from the most recent failed load, or null. */
  get errorCode(): string | null {
    return this._errorCode;
  }

  /** Whether the document has voxelizable ASCII-art (so blend/3D mode is
   * meaningful). False for pure-text docs, which blend cannot render usefully. */
  get voxelizable(): boolean {
    return this._planes.some((p) => this._gridOf(p.body) !== null);
  }

  /** The index of the currently focused plane. */
  get currentIndex(): number {
    return Math.round(this._focus);
  }

  /** The active render mode. */
  get mode(): Mode {
    return this._mode;
  }

  /** The parse error from the most recent load, or null if it parsed cleanly. */
  get error(): string | null {
    return this._error;
  }

  /** Focus a plane by index, clamped to range. */
  goTo(index: number): void {
    this._setTarget(index);
  }

  /** Toggle fullscreen for the element (the whole component fills the screen). */
  toggleFullscreen(): void {
    const d = document as Document & { webkitFullscreenElement?: Element; webkitExitFullscreen?: () => void };
    const el = this as HTMLElement & { webkitRequestFullscreen?: () => void };
    const active = d.fullscreenElement || d.webkitFullscreenElement;
    if (active) { (d.exitFullscreen || d.webkitExitFullscreen)?.call(d); }
    else { (el.requestFullscreen || el.webkitRequestFullscreen)?.call(el); }
  }

  /** Replace the rendered document with new 3md source text. */
  setSource(source: string): void {
    if (!this._scene) this._build();
    this._loadFromText(source);
  }

  /** Start auto-advancing through the planes (honors the document's fps metadata). */
  play(): void {
    this._startPlay();
  }

  /** Stop auto-advancing. */
  pause(): void {
    this._stopPlay();
  }

  /** Whether playback is currently running. */
  get playing(): boolean {
    return this._playing;
  }

  // MARK: - Loading

  private async _loadFromSrc(src: string): Promise<void> {
    const token = ++this._loadToken;
    try {
      const res = await fetch(src);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const text = await res.text();
      if (token !== this._loadToken) return;
      this._loadFromText(text);
    } catch (error) {
      if (token !== this._loadToken) return;
      this._showError(`Could not load ${src}: ${(error as Error).message}`);
    }
  }

  private _loadFromText(source: string): void {
    const trimmed = source.trim();
    if (!trimmed) {
      this._error = "Nothing to render yet — start typing or load a 3md document.";
      this._errorLine = null;
      this._errorCode = null;
      this._doc = null; this._planes = [];
      this._stopPlay();
      this.setAttribute("data-state", "empty");
      this._showError(this._error);
      return;
    }
    let doc: Document;
    try {
      doc = parse(trimmed);
    } catch (error) {
      const pe = error as { message?: string; line?: number; code?: string };
      this._error = pe.message ?? String(error);
      this._errorLine = typeof pe.line === "number" ? pe.line : null;
      this._errorCode = typeof pe.code === "string" ? pe.code : null;
      // Drop the stale document so programmatic callers never read a doc that no
      // longer matches the source, and a dead scene's controls are not left live.
      this._doc = null; this._planes = [];
      this._stopPlay();
      this.setAttribute("data-state", "error");
      this._showError(`Invalid 3md: ${this._error}`);
      return;
    }
    this._error = null;
    this._errorLine = null;
    this._errorCode = null;
    this.setAttribute("data-state", "ready");
    this._doc = doc;
    this._planes = doc.planes;
    this._legend = parseLegend(doc.metadata?.legend);
    const bb = String(doc.metadata?.billboard ?? "").toLowerCase();
    this._billboard = bb === "true" || bb === "yes" || bb === "1";
    this._applyMode();
    this._stopPlay();
    // Reset all accumulated view state so each document starts fresh. Without
    // this, orbit/parallax drift piles up across loads and the stage gets more
    // and more skewed the longer the element is used.
    this._focus = 0;
    this._target = 0;
    this._resetCamera();
    this._keys.clear();
    this._hiddenLayers.clear();
    if (this._camRaf != null) { cancelAnimationFrame(this._camRaf); this._camRaf = null; }
    this._dragAxis = null;
    this._dragging = false;
    this._pendingDrag = false;
    this._lastEmitted = -1;
    this._buildPlanes();
    this.render();
    // Animations (flipbook/play) auto-run; so does an explicit autoplay attribute.
    if (this.hasAttribute("autoplay") || this._mode === "play") this._startPlay();
  }

  // Mode precedence: the `mode` attribute (an explicit override the viewer sets)
  // wins; then the document's own preference (`view:` or `display:` in
  // frontmatter) so an author can suggest a default; then a mode derived from
  // the axis; else stack. Either way the viewer can always switch.
  private _applyMode(): void {
    const pick = (v: string | null | undefined): Mode | null => {
      const k = (v || "").toLowerCase();
      if (!k) return null;
      if (MODE_ALIAS[k]) return MODE_ALIAS[k]; // retired names -> survivor
      if (VALID_MODES.includes(k as Mode)) return k as Mode;
      if (AXIS_MODE[k]) return AXIS_MODE[k];
      return null;
    };
    const docView = this._doc ? (this._doc.metadata.view ?? this._doc.metadata.display) : null;
    this._mode =
      pick(this.getAttribute("mode")) ||
      pick(docView) ||
      (this._doc ? (AXIS_MODE[this._doc.axis] || "stack") : "stack");
    // Reflect the resolved mode so CSS (notably the fullscreen presentation
    // styles) can adapt to the active view without reading JS state.
    this.setAttribute("data-mode", this._mode);
    if (this._hintEl) this._hintEl.textContent = HINTS[this._mode] ?? "";
  }

  // MARK: - DOM

  private _build(): void {
    if (this._scene) return;
    const style = document.createElement("style");
    style.textContent = STYLES;
    this._root.appendChild(style);

    this._wrap = document.createElement("div");
    this._wrap.className = "wrap";
    this._wrap.setAttribute("part", "wrap");
    this._wrap.innerHTML = `
      <div class="axis" part="axis"></div>
      <div class="stage" part="stage">
        <div class="scene" part="scene"></div>
        <div class="detail" part="detail"></div>
      </div>
      <div class="hint" part="hint">drag to orbit · WASD / arrows move · slider or ↑↓ scrub Z</div>
      <div class="controls" part="controls">
        <button class="navbtn" part="prev" type="button" aria-label="previous plane">${ICONS.prev}</button>
        <input type="range" part="scrubber" min="0" max="0" step="0.001" value="0" aria-label="scrub the Z axis" />
        <button class="navbtn" part="next" type="button" aria-label="next plane">${ICONS.next}</button>
        <button class="navbtn" part="play" type="button" aria-label="play">${ICONS.play}</button>
        <button class="navbtn loop" part="loop" type="button" aria-label="toggle loop" title="Loop playback" aria-pressed="true">${ICONS.loop}</button>
        <button class="navbtn fs" part="fullscreen" type="button" aria-label="fullscreen" title="Fullscreen">${ICONS.fullscreen}</button>
      </div>
      <div class="readout" part="readout"></div>
      <div class="layerchips" part="layer-toggles"></div>`;
    this._root.appendChild(this._wrap);

    this._axisEl = this._wrap.querySelector(".axis")!;
    this._stage = this._wrap.querySelector(".stage")!;
    this._scene = this._wrap.querySelector(".scene")!;
    this._detail = this._wrap.querySelector(".detail")!;
    this._scrub = this._wrap.querySelector("input")!;
    this._readout = this._wrap.querySelector(".readout")!;
    this._chipsEl = this._wrap.querySelector(".layerchips")!;
    this._hintEl = this._wrap.querySelector(".hint")!;
    this._playBtn = this._wrap.querySelector('[part="play"]')!;

    this._scrub.addEventListener("input", () => {
      this._stopPlay(); // manual scrub takes over from playback
      this._target = parseFloat(this._scrub.value);
      this._focus = this._target; // snap: correct without rAF
      this.render();
    });
    this._playBtn.addEventListener("click", () => this._togglePlay());
    this._wrap.querySelector('[part="prev"]')!.addEventListener("click", () => this._setTarget(Math.round(this._target) - 1));
    this._wrap.querySelector('[part="next"]')!.addEventListener("click", () => this._setTarget(Math.round(this._target) + 1));
    this._wrap.querySelector('[part="fullscreen"]')!.addEventListener("click", () => this.toggleFullscreen());
    this._loopBtn = this._wrap.querySelector('[part="loop"]')!;
    this._loopBtn.addEventListener("click", () => {
      this._loop = !this._loop;
      this._loopBtn.setAttribute("aria-pressed", String(this._loop));
    });
    // Cross-plane links ([[z=N|text]]) jump to that plane. Bound to the stage (not
    // just the scene) so links on the focus-to-read overlay card also navigate.
    // Capture so the click does not also trigger the plane card's select handler.
    this._stage.addEventListener("click", (e) => {
      const link = (e.target as HTMLElement)?.closest?.(".xlink") as HTMLElement | null;
      if (!link) return;
      e.preventDefault();
      e.stopPropagation();
      const z = Number(link.dataset.z);
      const idx = this._planes.findIndex((p) => p.z === z);
      if (idx >= 0) this._setTarget(idx);
    }, true);
    this.tabIndex = this.tabIndex < 0 ? 0 : this.tabIndex;
    this.addEventListener("keydown", (e) => this._onKey(e));
    this.addEventListener("keyup", (e) => this._onKeyUp(e));
    this.addEventListener("blur", () => this._keys.clear()); // no stuck keys

    // Unified pointer handling: one path for mouse, touch, and pen.
    this._stage.addEventListener("pointerdown", (e) => this._onPointerDown(e));
    this._stage.addEventListener("pointermove", (e) => this._onPointerMove(e));
    this._stage.addEventListener("pointerup", (e) => this._onPointerUp(e));
    this._stage.addEventListener("pointercancel", (e) => this._onPointerUp(e));
    this._stage.addEventListener("wheel", (e) => this._onWheel(e), { passive: false });
  }

  private _showError(message: string): void {
    if (!this._wrap) this._build();
    this._scene.innerHTML = "";
    if (this._detail) this._detail.innerHTML = "";
    this._els = [];
    this._scene.style.transform = ""; // flat, not skewed by a stale camera pose
    if (this._axisEl) this._axisEl.textContent = "";
    if (this._readout) this._readout.textContent = "";
    const box = document.createElement("div");
    box.className = "err";
    box.setAttribute("part", "error");
    box.textContent = message;
    this._scene.appendChild(box);
  }

  private _buildPlanes(): void {
    this._scene.innerHTML = "";
    if (this._detail) this._detail.innerHTML = ""; // drop any popped focus-to-read card
    this._els = [];
    this._voxels = [];
    this._axisEl.textContent = this._doc ? `axis = ${this._doc.axis}` : "";
    if (this._mode === "blend") {
      // Blend is only meaningful for docs with real voxelizable ASCII art. A
      // pure-text doc would render as a garbled text cloud, so fall back to the
      // deck instead (the viewer also hides the blend option when !voxelizable).
      if (!this.voxelizable) {
        this._mode = "stack";
        this.setAttribute("data-mode", "stack");
        if (this._hintEl) this._hintEl.textContent = HINTS.stack;
      } else {
        this._buildBlend();
      }
    }
    if (this._mode !== "blend") {
      this._planes.forEach((plane, idx) => {
        const el = document.createElement("div");
        el.className = "plane";
        el.setAttribute("part", "plane");
        const tag = plane.label ? plane.label : `z ${plane.z}`;
        el.innerHTML = `<div class="ptag"><span>z = ${plane.z}</span><b>${esc(tag)}</b></div>${renderMarkdown(plane.body, this._legend)}`;
        el.addEventListener("click", () => { if (this._mode === "map") this._mapOverview = false; this._setTarget(idx); });
        this._scene.appendChild(el);
        this._els.push(el);
      });
    }
    this._scrub.max = String(Math.max(0, this._planes.length - 1));
    this._scrub.value = "0";
    this._measureFrames();
    this._buildLayerChips();
    this._updateReadout();
  }

  /** In layers view, a row of toggle chips shows/hides each overlay. */
  private _buildLayerChips(): void {
    if (!this._chipsEl) return;
    this._chipsEl.innerHTML = "";
    if (this._mode !== "layers") return;
    this._planes.forEach((p, idx) => {
      const chip = document.createElement("button");
      chip.type = "button";
      chip.className = "layerchip";
      chip.setAttribute("part", "layer-toggle");
      chip.textContent = p.label || `z${p.z}`;
      chip.setAttribute("aria-pressed", String(!this._hiddenLayers.has(idx)));
      chip.addEventListener("click", () => {
        if (this._hiddenLayers.has(idx)) this._hiddenLayers.delete(idx);
        else this._hiddenLayers.add(idx);
        chip.setAttribute("aria-pressed", String(!this._hiddenLayers.has(idx)));
        this.render();
      });
      this._chipsEl.appendChild(chip);
    });
  }

  /**
   * Size the flipbook frame to the WIDEST/TALLEST frame's natural content, so the
   * animation box is tight to the content yet identical for every frame (no
   * grow/shrink between frames). Clamped to the stage. Only runs in play mode.
   */
  private _measureFrames(): void {
    this.style.removeProperty("--three-md-frame-w");
    this.style.removeProperty("--three-md-frame-h");
    this.style.removeProperty("--three-md-frame-scale");
    if (this._mode !== "play" || !this._els.length) return;
    const sw = (this._stage?.clientWidth || 9999) - 24;
    const sh = (this._stage?.clientHeight || 9999) - 24;
    // Pass 1: the widest frame's natural (unwrapped) width. Pass 2: measure each
    // frame's height AT that width, so wrapped text is accounted for and never
    // clipped. The frame is sized to that content (its min size) and scaled to fit.
    let w = 0;
    for (const el of this._els) {
      const save = el.style.cssText;
      el.classList.remove("frame");
      el.style.transform = "none"; el.style.opacity = "0";
      el.style.width = "max-content"; el.style.height = "auto"; el.style.maxWidth = "none"; el.style.maxHeight = "none";
      w = Math.max(w, el.offsetWidth);
      el.style.cssText = save;
    }
    if (w <= 0) return;
    let h = 0;
    for (const el of this._els) {
      const save = el.style.cssText;
      el.classList.remove("frame");
      el.style.transform = "none"; el.style.opacity = "0";
      el.style.width = w + "px"; el.style.height = "auto"; el.style.maxWidth = "none"; el.style.maxHeight = "none";
      h = Math.max(h, el.offsetHeight);
      el.style.cssText = save;
    }
    if (h <= 0) return;
    const scale = Math.min(sw / w, sh / h, 1);
    this.style.setProperty("--three-md-frame-w", w + "px");
    this.style.setProperty("--three-md-frame-h", h + "px");
    this.style.setProperty("--three-md-frame-scale", scale.toFixed(3));
  }

  // Extract the first fenced block in a plane body as a grid (boolean cell
  // matrix), wherever it appears - text before the fence is fine. A cell is
  // "lit" when it is not a space and not a dot. Returns null when there is no
  // fence, or when the block looks like code rather than ASCII art (a code
  // block such as JSON uses many distinct characters; art/games use a few), so
  // code never gets voxelized in blend view.
  private _gridOf(body: string): { w: number; h: number; cells: boolean[][]; rows: string[] } | null {
    const lines = body.split("\n");
    const start = lines.findIndex((l) => l.startsWith("```"));
    if (start < 0) return null;
    const rows: string[] = [];
    for (let i = start + 1; i < lines.length && !lines[i].startsWith("```"); i++) rows.push(lines[i]);
    if (!rows.length) return null;
    const chars = new Set<string>();
    for (const r of rows) for (const ch of r) if (ch !== " ") chars.add(ch);
    if (chars.size > 12) return null; // code-like, not a grid
    const w = Math.max(...rows.map((r) => r.length));
    const cells = rows.map((r) => {
      const out: boolean[] = [];
      for (let c = 0; c < w; c++) { const ch = r[c] ?? " "; out.push(ch !== " " && ch !== "."); }
      return out;
    });
    return { w, h: rows.length, cells, rows };
  }

  // Blended "object" view: drop the plane cards and place each plane's content
  // in true 3D space. Grid planes become a layer of voxels (so a stack of grids
  // is a rotatable 3D object, e.g. a cube); text planes float at their depth.
  private _buildBlend(): void {
    const CELL = 13;
    const grids = this._planes.map((p) => this._gridOf(p.body));
    const W = Math.max(1, ...grids.map((g) => (g ? g.w : 0)));
    const H = Math.max(1, ...grids.map((g) => (g ? g.h : 0)));
    const N = this._planes.length;
    this._planes.forEach((plane, idx) => {
      const g = grids[idx];
      const z = (idx - (N - 1) / 2) * CELL;
      if (g) {
        for (let r = 0; r < g.h; r++) {
          for (let c = 0; c < g.w; c++) {
            if (!g.cells[r][c]) continue;
            const raw = g.rows[r]?.[c] ?? "";
            // Each cell IS its character: a legend remaps it (e.g. #->🧱), otherwise
            // the raw glyph shows through. Emoji/symbols carry their own colour.
            const glyph = this._legend[raw] ?? raw;
            const v = document.createElement("div");
            v.className = "voxel";
            v.setAttribute("part", "voxel");
            v.dataset.z = String(idx);
            v.textContent = glyph;
            const x = (c - (W - 1) / 2) * CELL;
            const y = (r - (H - 1) / 2) * CELL;
            v.dataset.tx = x.toFixed(1); v.dataset.ty = y.toFixed(1); v.dataset.tz = z.toFixed(1);
            v.style.transform = `translate3d(${x.toFixed(1)}px,${y.toFixed(1)}px,${z.toFixed(1)}px)`;
            this._scene.appendChild(v);
            this._voxels.push(v);
          }
        }
      } else {
        const t = document.createElement("div");
        t.className = "floattext";
        t.setAttribute("part", "floattext");
        t.dataset.z = String(idx);
        t.style.transform = `translate3d(${(-W * CELL) / 2}px,0,${z.toFixed(1)}px)`;
        t.innerHTML = renderMarkdown(plane.body, this._legend);
        this._scene.appendChild(t);
        this._voxels.push(t);
      }
    });
  }

  // MARK: - Playback

  /** Advance one plane, wrapping. Used by the autoplay timer only. */
  private _step(): void {
    const n = this._planes.length;
    if (n <= 1) return;
    const next = Math.round(this._target) + 1;
    if (next >= n) {
      if (!this._loop) { this._stopPlay(); return; } // play once and stop
      this._target = 0;
    } else {
      this._target = next;
    }
    this._focus = this._target;
    this._scrub.value = String(this._target);
    this.render();
  }

  // MARK: - Camera

  /** Reset orbit/pan/zoom to a sensible default for the active mode. */
  private _resetCamera(): void {
    this._panX = 0; this._panY = 0; this._zoom = 0;
    this._mapOverview = true; // map opens on the full-board overview, nothing forced open
    if (this._mode === "blend") { this._yaw = -28; this._pitch = 14; }
    else if (this._mode === "stack") { this._yaw = -18; this._pitch = 8; }
    else if (this._mode === "layers") { this._yaw = -22; this._pitch = 12; } // angle to see the stacked sheets
    else if (this._mode === "elevator") { this._yaw = -10; this._pitch = 6; } // mostly front, slight angle
    else if (this._mode === "map") { this._yaw = 0; this._pitch = 30; this._zoom = 0; } // tilt; auto-fit scales the board to the stage
    else { this._yaw = 0; this._pitch = 0; } // flat modes look head-on
  }

  /** The scene transform from the current camera, around a base distance. */
  private _cameraTransform(baseZ: number): string {
    return `translate3d(${this._panX.toFixed(1)}px, ${this._panY.toFixed(1)}px, ${(baseZ + this._zoom).toFixed(1)}px) `
      + `rotateX(${this._pitch.toFixed(2)}deg) rotateY(${this._yaw.toFixed(2)}deg)`;
  }

  private _startPlay(): void {
    if (this._playing || this._planes.length <= 1) return;
    this._playing = true;
    if (this._playBtn) { this._playBtn.innerHTML = ICONS.pause; this._playBtn.setAttribute("aria-label", "pause"); }
    // Honor the document's fps metadata; clamp so playback stays watchable.
    // setInterval (not rAF) keeps animations running under iOS Low Power Mode.
    // Clamp playback to a calm, watchable range (about 1.5-7.5 fps) so animations
    // never feel frantic; default to ~600ms when no fps is given.
    const fps = this._doc ? parseInt(this._doc.metadata?.fps ?? "", 10) : NaN;
    const delay = fps > 0 ? Math.min(1400, Math.max(135, 1000 / fps)) : 600;
    this._playTimer = setInterval(() => this._step(), delay);
  }

  private _stopPlay(): void {
    this._playing = false;
    if (this._playTimer) { clearInterval(this._playTimer); this._playTimer = null; }
    if (this._playBtn) { this._playBtn.innerHTML = ICONS.play; this._playBtn.setAttribute("aria-label", "play"); }
  }

  private _togglePlay(): void {
    if (this._playing) this._stopPlay(); else this._startPlay();
  }

  // MARK: - Interaction

  private _setTarget(index: number): void {
    this._stopPlay(); // manual navigation takes over from playback
    const max = this._planes.length - 1;
    this._target = Math.max(0, Math.min(max, index));
    this._focus = this._target; // snap so it is correct even with rAF paused
    this._scrub.value = String(this._target);
    this.render();
  }

  private _onKey(e: KeyboardEvent): void {
    // Camera modes (deck, 3D object, map): WASD/arrows fly, Q/E orbit, +/- and
    // scroll zoom, PageUp/Down step the focused plane. Flat modes (reader, slides,
    // animation): arrows/space/PageDn navigate planes.
    if (CAMERA_MODES.has(this._mode)) {
      const k = e.key.length === 1 ? e.key.toLowerCase() : e.key;
      // Esc returns the map to its full-board overview (closes the read card).
      if (k === "Escape" && this._mode === "map" && !this._mapOverview) { this._mapOverview = true; this.render(); e.preventDefault(); return; }
      // Discrete keys: zoom and stepping the focused plane.
      if (k === "+" || k === "=") { this._zoom = Math.min(600, this._zoom + 40); this.render(); e.preventDefault(); return; }
      if (k === "-" || k === "_") { this._zoom = Math.max(-400, this._zoom - 40); this.render(); e.preventDefault(); return; }
      if (k === "PageDown") { this._setTarget(Math.round(this._target) + 1); e.preventDefault(); return; }
      if (k === "PageUp") { this._setTarget(Math.round(this._target) - 1); e.preventDefault(); return; }
      // Held movement keys drive a smooth loop while down (no multi-press).
      if ("wasdqe".includes(k) || k === "ArrowUp" || k === "ArrowDown" || k === "ArrowLeft" || k === "ArrowRight") {
        this._keys.add(k);
        this._startCamLoop();
        e.preventDefault();
      }
      return;
    }
    const spaceAdvances = e.key === " " && this._mode !== "single";
    if (e.key === "ArrowRight" || e.key === "ArrowUp" || e.key === "PageDown" || spaceAdvances) { this._setTarget(Math.round(this._target) + 1); e.preventDefault(); }
    else if (e.key === "ArrowLeft" || e.key === "ArrowDown" || e.key === "PageUp") { this._setTarget(Math.round(this._target) - 1); e.preventDefault(); }
  }

  private _onPointerUpMap(wasDragging: boolean): void {
    // A tap on the empty board (not on a tile) returns map to the full overview.
    if (wasDragging || this._mode !== "map") return;
    const onCard = !!this._downTarget?.closest?.(".plane");
    if (!onCard && !this._mapOverview) { this._mapOverview = true; }
  }

  private _onPointerDown(e: PointerEvent): void {
    this._downTarget = e.target as HTMLElement;
    // Only the camera modes drag-to-orbit. Reader scrolls natively; slides and
    // animation navigate via the chrome. We do NOT capture the pointer yet: a tap
    // must stay a click so cross-plane links and plane cards still work. Orbit
    // only engages once the pointer moves past a small threshold (see move).
    if (!CAMERA_MODES.has(this._mode)) return;
    this._pendingDrag = true;
    this._dragging = false;
    this._pointerId = e.pointerId;
    this._lastX = e.clientX;
    this._lastY = e.clientY;
    this._dragStartX = e.clientX;
    this._dragStartY = e.clientY;
  }

  private _onPointerMove(e: PointerEvent): void {
    if (this._pointerId !== null && e.pointerId !== this._pointerId) return;
    if (this._pendingDrag && !this._dragging) {
      if (Math.hypot(e.clientX - this._dragStartX, e.clientY - this._dragStartY) < 8) return;
      this._dragging = true; // crossed the threshold: this is an orbit, not a tap
      this._stopPlay();
      try { this._stage.setPointerCapture(e.pointerId); } catch { /* ignore */ }
    }
    if (!this._dragging) return;
    this._yaw += (e.clientX - this._lastX) * 0.4;
    this._pitch = Math.max(-85, Math.min(85, this._pitch - (e.clientY - this._lastY) * 0.3));
    // Map is a board you tilt to read, not an object you flip: clamp its orbit so
    // an extreme yaw+pitch pose can never swing a tile's edge off the stage.
    // Other camera modes keep free 360 spin (cards/voxels are meant to be circled).
    if (this._mode === "map") {
      this._yaw = Math.max(-30, Math.min(30, this._yaw));
      this._pitch = Math.max(12, Math.min(52, this._pitch));
    }
    this._lastX = e.clientX;
    this._lastY = e.clientY;
    this.render(); // synchronous: works while rAF is paused
  }

  private _onPointerUp(e: PointerEvent): void {
    const wasDragging = this._dragging;
    this._pendingDrag = false;
    this._dragging = false;
    this._pointerId = null;
    try { this._stage.releasePointerCapture(e.pointerId); } catch { /* ignore */ }
    this._onPointerUpMap(wasDragging);
    this.render();
  }

  private _onWheel(e: WheelEvent): void {
    if (!CAMERA_MODES.has(this._mode)) return; // reader/slides scroll natively
    e.preventDefault();
    // Normalize line vs pixel deltas, and use a sensitivity strong enough that a
    // trackpad two-finger scroll (tiny deltaY) zooms noticeably. Pinch (ctrlKey)
    // gets a bigger step.
    const unit = e.deltaMode === 1 ? 16 : e.deltaMode === 2 ? 400 : 1;
    const factor = e.ctrlKey ? 6 : 2.2;
    this._zoom = Math.max(-420, Math.min(720, this._zoom - e.deltaY * unit * factor));
    this.render();
  }

  // Smooth, continuous camera movement while WASD/arrow/Q-E keys are held. The
  // rAF loop runs ONLY while keys are down (it stops itself when none remain), so
  // the element stays event-driven at rest.
  private _startCamLoop(): void {
    if (this._camRaf != null) return;
    const tick = () => {
      if (!this._keys.size) { this._camRaf = null; return; }
      const pan = 7, orbit = 1.6;
      const has = (k: string) => this._keys.has(k);
      if (has("w") || has("ArrowUp")) this._panY += pan;
      if (has("s") || has("ArrowDown")) this._panY -= pan;
      if (has("a") || has("ArrowLeft")) this._panX += pan;
      if (has("d") || has("ArrowRight")) this._panX -= pan;
      if (has("q")) this._yaw -= orbit;
      if (has("e")) this._yaw += orbit;
      this.render();
      this._camRaf = requestAnimationFrame(tick);
    };
    this._camRaf = requestAnimationFrame(tick);
  }

  private _onKeyUp(e: KeyboardEvent): void {
    this._keys.delete(e.key.length === 1 ? e.key.toLowerCase() : e.key);
  }

  // MARK: - Rendering

  /**
   * Apply the current state to the DOM synchronously. Safe to call at any time,
   * with or without requestAnimationFrame running. This is the single source of
   * truth for what the stage looks like.
   */
  render(): void {
    const m = this._mode;
    const focus = this._focus;
    const fr = Math.round(focus);

    // Re-home any card that was popped into the flat detail overlay (map focus-to-
    // read) back into the 3D scene before any mode renders, so every other mode sees
    // a clean set of plane cards in the scene.
    for (const el of this._els) {
      if (el.parentNode === this._detail) {
        el.classList.remove("popped");
        el.removeAttribute("style");
        this._scene.appendChild(el);
      }
    }

    // Blended object view: a static voxel/text cloud the user orbits freely.
    if (m === "blend") {
      if (!this._voxels.length) return;
      for (const v of this._voxels) v.classList.toggle("near", Number(v.dataset.z) === fr);
      // Billboard (opt-in via `billboard: true`): each glyph counter-rotates the
      // camera so it always faces the viewer (useful for emoji/character scenes).
      if (this._billboard) {
        for (const v of this._voxels) {
          if (v.dataset.tx === undefined) continue;
          v.style.transform = `translate3d(${v.dataset.tx}px,${v.dataset.ty}px,${v.dataset.tz}px) rotateY(${(-this._yaw).toFixed(2)}deg) rotateX(${(-this._pitch).toFixed(2)}deg)`;
        }
      }
      this._scene.style.transform = this._cameraTransform(-30);
      this._updateReadout();
      this._maybeEmit(fr);
      return;
    }

    if (!this._els.length) return;
    // Clear any per-layer pointer-event blocking; only layers view re-applies it.
    if (m !== "layers") for (const el of this._els) el.style.pointerEvents = "";

    // Single-card view: one stationary card whose contents swap as you scrub.
    // No deck, no 3D - the other planes fade out and the focused one fades in.
    if (m === "single") {
      this._els.forEach((el, idx) => {
        const on = idx === fr;
        // The focused card uses the .reader CSS for centering/scrolling, so clear
        // its inline transform; hidden cards keep a neutral one.
        el.style.transform = on ? "" : "translate3d(0px,0px,0px) scale(1)";
        el.style.opacity = on ? "1" : "0";
        el.style.zIndex = on ? "10" : "0";
        el.classList.toggle("hot", false);
        el.classList.toggle("dim", false);
        el.classList.toggle("reader", on); // focused card becomes the scroll container
      });
      this._scene.style.transform = "translateZ(0px)";
      this._updateReadout();
      this._maybeEmit(fr);
      return;
    }

    // Flipbook view (animations): only the current frame, shown flat and swapped
    // instantly in place, like a flipbook. No fanned deck, no perspective skew.
    if (m === "play") {
      this._els.forEach((el, idx) => {
        const on = idx === fr;
        el.style.transform = on ? "" : "translate3d(0px,0px,0px)";
        el.style.opacity = on ? "1" : "0";
        el.style.zIndex = on ? "10" : "0";
        el.classList.toggle("frame", on); // centered, instant, fit-to-stage
        el.classList.toggle("hot", false);
        el.classList.toggle("dim", false);
      });
      this._scene.style.transform = "translateZ(0px)";
      this._updateReadout();
      this._maybeEmit(fr);
      return;
    }

    // Layers: aligned overlays (NOT a fanned deck). Planes share x/y and stack in
    // depth; the focused one is opaque up front, the rest are translucent sheets
    // behind it. Orbit to see the layering. For annotations and overlays.
    if (m === "layers") {
      // Overlays of one thing, seen TOGETHER: aligned (same x), shallow depth so
      // you see through the stack; the focused layer is opaque, others ghosted;
      // toggle chips hide/show each. This is what makes layers != a sequence deck.
      this._els.forEach((el, idx) => {
        const hidden = this._hiddenLayers.has(idx);
        const d = idx - focus;
        const on = idx === fr;
        // Aligned overlays: no vertical fan (that pushed tall cards out of frame);
        // depth (z) + opacity carry the stacked-sheet look, revealed when orbited.
        // Cap the depth spread so that under the yaw angle the deepest sheet's
        // horizontal shift (|z|*sin yaw) never pokes a wide card past the edge,
        // however many layers a document has.
        const depth = -Math.min(Math.abs(d), 4) * 45;
        el.style.transform = `translate3d(0px, 0px, ${depth.toFixed(1)}px)`;
        el.style.opacity = hidden ? "0" : (on ? "0.97" : "0.42");
        el.style.zIndex = on ? "300" : String(120 - Math.abs(fr - idx));
        el.style.pointerEvents = hidden ? "none" : "auto";
        el.classList.toggle("hot", on && !hidden);
        el.classList.toggle("dim", false);
        el.classList.toggle("reader", false);
        el.classList.toggle("frame", false);
      });
      this._scene.style.transform = this._cameraTransform(-150);
      this._updateReadout();
      this._maybeEmit(fr);
      return;
    }

    // Elevator: floors stacked vertically; the focused floor is centered, the
    // others above and below it, receding. Ride the slider up and down.
    if (m === "elevator") {
      this._els.forEach((el, idx) => {
        const d = idx - focus;
        const on = idx === fr;
        el.style.transform = `translate3d(0px, ${(d * 150).toFixed(1)}px, ${(-Math.abs(d) * 70).toFixed(1)}px) scale(${on ? 1 : 0.84})`;
        el.style.opacity = Math.max(0.14, 1 - Math.abs(d) * 0.42).toFixed(2);
        el.style.zIndex = on ? "300" : String(120 - Math.abs(fr - idx));
        el.classList.toggle("hot", on);
        el.classList.toggle("dim", false);
        el.classList.toggle("reader", false);
        el.classList.toggle("frame", false);
      });
      this._scene.style.transform = this._cameraTransform(-160);
      this._updateReadout();
      this._maybeEmit(fr);
      return;
    }

    // Map: a board you orbit. Cards are placed by their x/y, NORMALIZED to fit the
    // board (so any coordinate range works); a doc without x/y is auto-gridded.
    if (m === "map") {
      // Authoritative orbit bound for map: clamp here (not only in the drag
      // handler) so the board stays framed no matter how the pose was set. Yaw is
      // the binding constraint - it swings back-row tiles up under the tilt - so
      // it is held to a gentle range; the board is meant to be viewed near top-down.
      this._yaw = Math.max(-30, Math.min(30, this._yaw));
      this._pitch = Math.max(12, Math.min(52, this._pitch));
      // Cards snap to GRID CELLS, not continuous positions: x/y are ranked among
      // their distinct values so coordinates are predictable (same x -> same column,
      // same y -> same row, adjacent numbers -> adjacent cells) and cells are wider
      // than a card so tiles NEVER overlap unless two planes share the exact x AND y.
      const cw = this._els[0]?.offsetWidth || 300, ch = this._els[0]?.offsetHeight || 180;
      const COL_W = cw * 1.1, ROW_H = ch * 1.25; // > card size => guaranteed gap
      const hasXY = this._planes.some((p) => p.x != null || p.y != null);
      const cols = Math.max(1, Math.ceil(Math.sqrt(this._els.length)));
      const rows = Math.ceil(this._els.length / cols);
      // Auto-grid (reading order) for planes with no coordinates of their own.
      const gridPos = (idx: number): [number, number] => [
        (idx % cols - (cols - 1) / 2) * COL_W,
        (Math.floor(idx / cols) - (rows - 1) / 2) * ROW_H,
      ];
      let posOf: (idx: number) => [number, number];
      if (hasXY) {
        const xVals = [...new Set(this._planes.filter((p) => p.x != null).map((p) => p.x as number))].sort((a, b) => a - b);
        const yVals = [...new Set(this._planes.filter((p) => p.y != null).map((p) => p.y as number))].sort((a, b) => a - b);
        const nCols = Math.max(1, xVals.length), nRows = Math.max(1, yVals.length);
        posOf = (idx) => {
          const p = this._planes[idx];
          if (p.x == null && p.y == null) return gridPos(idx); // unpositioned -> auto grid
          // Rank each coordinate to its column/row; a missing axis sits in a trailing lane.
          const col = p.x != null ? xVals.indexOf(p.x as number) : nCols;
          const row = p.y != null ? yVals.indexOf(p.y as number) : nRows;
          return [(col - (nCols - 1) / 2) * COL_W, (row - (nRows - 1) / 2) * ROW_H];
        };
      } else {
        posOf = gridPos;
      }
      // Auto-fit: scale the whole board so the outermost tiles stay on the stage
      // no matter how many tiles or how wide the coordinate range (the user can
      // still wheel-zoom in). Without this, big boards spilled off the sides.
      const stageW = this._stage.clientWidth || 1, stageH = this._stage.clientHeight || 1;
      let halfW = cw / 2, halfH = ch / 2;
      this._els.forEach((el, idx) => {
        const [x, y] = posOf(idx);
        halfW = Math.max(halfW, Math.abs(x) + cw * 0.45); // 0.45 = half x max tile scale
        halfH = Math.max(halfH, Math.abs(y) + ch * 0.45);
      });
      // 0.92 leaves headroom so a tilted/orbited board still stays inside the stage.
      const fit = Math.min(1, (stageW / 2 - 16) / halfW, (stageH / 2 - 16) / halfH) * 0.92;
      this.setAttribute("data-map-overview", String(this._mapOverview));
      // Overview: the WHOLE board, every tile shown equally, nothing forced open
      // (tap a tile to read it; tap empty space or Esc to come back here).
      if (this._mapOverview) {
        this._els.forEach((el, idx) => {
          const [x, y] = posOf(idx);
          el.style.transform = `translate3d(${x.toFixed(1)}px, ${y.toFixed(1)}px, 0px) scale(0.82)`;
          el.style.opacity = "1";
          el.style.zIndex = String(100 + idx);
          el.style.top = ""; el.style.bottom = ""; el.style.height = ""; el.style.marginTop = ""; el.style.marginBottom = ""; el.style.maxHeight = "";
          el.classList.toggle("hot", false);
          el.classList.toggle("dim", false); el.classList.toggle("reader", false); el.classList.toggle("frame", false);
        });
      } else {
        // Focus-to-read: board tiles dim, and the focused tile is lifted OUT of the 3D
        // scene into the flat overlay (never skewed by the tilt) and scaled so its WHOLE
        // content fits the stage - every line readable, no scroll.
        this._els.forEach((el, idx) => {
          if (idx === fr) return;
          const [x, y] = posOf(idx);
          el.style.transform = `translate3d(${x.toFixed(1)}px, ${y.toFixed(1)}px, 0px) scale(0.72)`;
          el.style.opacity = "0.4";
          el.style.zIndex = String(100 + idx);
          el.style.top = ""; el.style.bottom = ""; el.style.height = ""; el.style.marginTop = ""; el.style.marginBottom = ""; el.style.maxHeight = "";
          el.classList.toggle("hot", false); el.classList.toggle("dim", false); el.classList.toggle("reader", false); el.classList.toggle("frame", false);
        });
        const hotEl = this._els[fr];
        if (hotEl) {
          hotEl.classList.add("hot", "popped");
          hotEl.classList.toggle("dim", false); hotEl.classList.toggle("reader", false); hotEl.classList.toggle("frame", false);
          if (hotEl.parentNode !== this._detail) this._detail.appendChild(hotEl);
          // Content-width (capped to a readable measure) so wide grids/tables are not
          // clipped before we measure; pop then scales the whole card to fit the stage.
          hotEl.style.cssText = "position:relative;margin:0;top:auto;left:auto;right:auto;bottom:auto;height:max-content;max-height:none;width:max-content;min-width:280px;max-width:64ch;opacity:1;transform:none";
          const natH = Math.max(1, hotEl.offsetHeight), natW = Math.max(1, hotEl.offsetWidth);
          const pop = Math.max(0.6, Math.min(1.8, (stageH - 22) / natH, (stageW - 22) / natW));
          hotEl.style.transform = `scale(${pop.toFixed(3)})`;
        }
      }
      this._scene.style.transform = `${this._cameraTransform(-120)} scale(${fit.toFixed(3)})`;
      this._updateReadout();
      this._maybeEmit(fr);
      return;
    }

    // Deck (stack) and Slides (present).
    this._els.forEach((el, idx) => {
      let x = 0, y = 0, z = 0, s = 1, o = 1, hot = false, dim = false;
      const d = idx - focus;
      if (m === "present") {
        // Focused slide is NOT upscaled (that pushed long slides past the stage);
        // it fills the capped card and scrolls if long.
        if (Math.abs(d) < 0.5) { z = 0; s = 1; hot = true; }
        else { x = d * 70; z = -180 - Math.abs(d) * 50; s = 0.6; o = 0.22; dim = true; }
      } else { // stack (deck)
        z = -Math.abs(d) * 160; y = d * 26; x = d * 30;
        if (idx === fr) { s = 1; hot = true; } // focused fills a centered scrollable box
      }
      el.style.transform = `translate3d(${x}px,${y}px,${z}px) scale(${s.toFixed(3)})`;
      el.style.opacity = String(o);
      el.style.zIndex = idx === fr ? "300" : String(120 - Math.abs(fr - idx));
      el.classList.toggle("hot", hot);
      el.classList.toggle("dim", dim);
      el.classList.toggle("reader", false);
      el.classList.toggle("frame", false);
    });

    // Slides are a flat slideshow (no orbit); the deck uses the camera.
    this._scene.style.transform = m === "present" ? "translateZ(-110px)" : this._cameraTransform(-160);

    this._updateReadout();
    this._maybeEmit(fr);
  }

  private _updateReadout(): void {
    const i = Math.round(this._focus);
    const p = this._planes[i];
    if (!p) { this._readout.textContent = ""; return; }
    const label = p.label ? ` ${p.label}` : "";
    this._readout.innerHTML = `Z = <b>${p.z}</b>${esc(label)} <span>(${i + 1}/${this._planes.length})</span>`;
  }

  private _maybeEmit(index: number): void {
    if (index === this._lastEmitted) return;
    this._lastEmitted = index;
    const plane = this._planes[index];
    if (!plane) return;
    this.dispatchEvent(new CustomEvent("planechange", {
      detail: { index, z: plane.z, label: plane.label, plane },
      bubbles: true,
      composed: true,
    }));
  }

}

if (typeof customElements !== "undefined" && !customElements.get("three-md")) {
  customElements.define("three-md", ThreeMDElement);
}

declare global {
  interface HTMLElementTagNameMap {
    "three-md": ThreeMDElement;
  }
}
