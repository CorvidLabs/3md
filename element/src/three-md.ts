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

type Mode = "stack" | "play" | "layers" | "scene" | "parallax" | "present" | "elevator";

const AXIS_MODE: Record<string, Mode> = {
  time: "stack",
  frame: "play",
  frames: "play",
  layer: "layers",
  layers: "layers",
  depth: "parallax",
  space: "scene",
  scene: "scene",
  slide: "present",
  slides: "present",
  deck: "present",
  floor: "elevator",
  floors: "elevator",
};

const FOCUS_MODES: ReadonlySet<Mode> = new Set(["stack", "play", "layers", "present", "elevator"]);

function esc(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

/** Inline Markdown on already-escaped text: code, bold, italic. */
function inline(escaped: string): string {
  return escaped
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/\*([^*]+)\*/g, "<em>$1</em>")
    .replace(/_([^_]+)_/g, "<em>$1</em>");
}

function fmt(text: string): string {
  return inline(esc(text));
}

/** A deliberately small Markdown subset, matching the reference lab renderer. */
function renderMarkdown(body: string): string {
  const lines = body.split("\n");
  if (lines[0] && lines[0].startsWith("```")) {
    const rows = lines.filter((l) => !l.startsWith("```"));
    return `<div class="grid" part="grid">` +
      rows.map((r) => esc(r).replace(/o/g, '<span class="dot">●</span>')).join("<br>") +
      `</div>`;
  }
  const out: string[] = [];
  for (const l of lines) {
    if (l.startsWith("# ")) out.push(`<h4 part="plane-title">${fmt(l.slice(2))}</h4>`);
    else if (l.startsWith("## ")) out.push(`<h5 part="plane-title">${fmt(l.slice(3))}</h5>`);
    else if (l.startsWith("- [x] ")) out.push(`<div class="li"><span class="box">▣</span><span class="done">${fmt(l.slice(6))}</span></div>`);
    else if (l.startsWith("- [ ] ")) out.push(`<div class="li"><span class="box">▢</span><span>${fmt(l.slice(6))}</span></div>`);
    else if (l.startsWith("- ")) out.push(`<div class="li"><span class="box">•</span><span>${fmt(l.slice(2))}</span></div>`);
    else if (/^\d+\. /.test(l)) out.push(`<div class="li"><span class="box">${esc(l.slice(0, l.indexOf(".")))}</span><span>${fmt(l.slice(l.indexOf(".") + 2))}</span></div>`);
    else if (l.startsWith("> ")) out.push(`<div class="quote">${fmt(l.slice(2))}</div>`);
    else if (l.trim() !== "") out.push(`<div>${fmt(l)}</div>`);
  }
  return `<div class="md" part="plane-body">${out.join("")}</div>`;
}

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
.arrow { position: absolute; right: 14px; top: 12px; font-size: 11px; letter-spacing: .16em; color: var(--three-md-faint); z-index: 6; }
.hint { position: absolute; left: 14px; bottom: 10px; font-size: 11px; color: var(--three-md-faint); z-index: 6; }
.plane {
  position: absolute; left: 50%; top: 50%;
  width: min(var(--three-md-plane-width, 320px), 84%);
  margin-left: calc(min(var(--three-md-plane-width, 320px), 84%) / -2); margin-top: -104px;
  border-radius: 8px; padding: 14px 16px;
  background: var(--three-md-surface); border: 1px solid var(--three-md-accent);
  box-shadow: 0 18px 44px rgba(0,0,0,.45); cursor: pointer;
  transition: opacity .3s, box-shadow .3s, filter .3s;
}
.plane.dim { opacity: .18; filter: saturate(.5); }
.plane.hot { box-shadow: 0 0 0 2px var(--three-md-accent), 0 18px 44px rgba(0,0,0,.5); }
.ptag { font-size: 10.5px; letter-spacing: .08em; text-transform: uppercase; color: var(--three-md-accent); display: flex; justify-content: space-between; margin-bottom: 8px; }
.ptag b { color: var(--three-md-text); font-weight: 700; }
.md, .grid { font-size: 12.5px; line-height: 1.65; color: var(--three-md-muted); }
.md h4 { font-family: var(--three-md-display, inherit); font-size: 16px; margin: 2px 0 8px; color: var(--three-md-text); }
.md h5 { font-size: 13px; margin: 6px 0 6px; color: var(--three-md-text); }
.md .li { display: flex; gap: 8px; }
.md .box { color: var(--three-md-accent); }
.md .done { color: var(--three-md-faint); text-decoration: line-through; }
.md .quote { border-left: 2px solid var(--three-md-hairline); padding-left: 10px; color: var(--three-md-faint); font-style: italic; }
.md strong { color: var(--three-md-text); font-weight: 700; }
.md em { font-style: italic; }
.md code { font-family: inherit; background: var(--three-md-hairline); padding: 1px 5px; border-radius: 3px; color: var(--three-md-text); }
.grid { font-size: 16px; line-height: 1.25; letter-spacing: 3px; color: var(--three-md-faint); white-space: pre; }
.grid .dot { color: var(--three-md-accent); }
.controls { display: flex; align-items: center; gap: 10px; margin-top: 12px; flex-wrap: wrap; }
.navbtn { font: inherit; font-size: 14px; color: var(--three-md-text); background: var(--three-md-surface); border: 1px solid var(--three-md-hairline); width: 38px; height: 34px; border-radius: 4px; cursor: pointer; }
.navbtn:hover { border-color: var(--three-md-accent); color: var(--three-md-accent); }
input[type=range] { flex: 1; min-width: 120px; accent-color: var(--three-md-accent); cursor: pointer; }
.readout { font-size: 12.5px; color: var(--three-md-muted); }
.readout b { color: var(--three-md-accent); }
.err { padding: 16px; color: #ff8f8f; font-size: 13px; }
`;

export class ThreeMDElement extends HTMLElement {
  static get observedAttributes(): string[] {
    return ["src", "mode", "autoplay"];
  }

  private _root: ShadowRoot;
  private _scene!: HTMLDivElement;
  private _stage!: HTMLDivElement;
  private _axisEl!: HTMLDivElement;
  private _scrub!: HTMLInputElement;
  private _readout!: HTMLDivElement;
  private _wrap!: HTMLDivElement;

  private _doc: Document | null = null;
  private _planes: readonly Plane[] = [];
  private _els: HTMLDivElement[] = [];
  private _mode: Mode = "stack";

  private _focus = 0;
  private _target = 0;
  private _dragRX = 0;
  private _dragRY = 0;
  private _mx = 0;
  private _my = 0;

  private _dragging = false;
  private _lastX = 0;
  private _lastY = 0;
  private _dragStartX = 0;
  private _dragStartY = 0;
  private _dragStartTarget = 0;
  private _dragAxis: "x" | "y" | null = null;
  private _pointerId: number | null = null;
  private _lastEmitted = -1;
  private _loadToken = 0;
  private _playBtn!: HTMLButtonElement;
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
      this._applyMode();
      this.render();
    } else if (name === "autoplay") {
      if (value !== null) this._startPlay(); else this._stopPlay();
    }
  }

  // MARK: - Public API

  /** The parsed document, or null before content has loaded. */
  get document(): Document | null {
    return this._doc;
  }

  /** The index of the currently focused plane. */
  get currentIndex(): number {
    return Math.round(this._focus);
  }

  /** The active render mode. */
  get mode(): Mode {
    return this._mode;
  }

  /** Focus a plane by index, clamped to range. */
  goTo(index: number): void {
    this._setTarget(index);
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
      this._showError("No 3md source provided.");
      return;
    }
    let doc: Document;
    try {
      doc = parse(trimmed);
    } catch (error) {
      this._showError(`Invalid 3md: ${(error as Error).message}`);
      return;
    }
    this._doc = doc;
    this._planes = doc.planes;
    this._applyMode();
    this._stopPlay();
    // Reset all accumulated view state so each document starts fresh. Without
    // this, orbit/parallax drift piles up across loads and the stage gets more
    // and more skewed the longer the element is used.
    this._focus = 0;
    this._target = 0;
    this._dragRX = 0;
    this._dragRY = 0;
    this._mx = 0;
    this._my = 0;
    this._dragAxis = null;
    this._dragging = false;
    this._lastEmitted = -1;
    this._buildPlanes();
    this.render();
    if (this.hasAttribute("autoplay")) this._startPlay();
  }

  private _applyMode(): void {
    const override = (this.getAttribute("mode") || "").toLowerCase() as Mode;
    if (override && AXIS_MODE[override]) {
      this._mode = AXIS_MODE[override];
    } else if (override && (["stack", "play", "layers", "scene", "parallax", "present", "elevator"] as const).includes(override as Mode)) {
      this._mode = override as Mode;
    } else if (this._doc) {
      this._mode = AXIS_MODE[this._doc.axis] || "stack";
    } else {
      this._mode = "stack";
    }
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
        <div class="arrow" part="arrow">Z ↑</div>
        <div class="scene" part="scene"></div>
        <div class="hint" part="hint">drag ↕ to move through Z, ↔ to orbit</div>
      </div>
      <div class="controls" part="controls">
        <button class="navbtn" part="prev" type="button" aria-label="previous plane">←</button>
        <input type="range" part="scrubber" min="0" max="0" step="0.001" value="0" aria-label="scrub the Z axis" />
        <button class="navbtn" part="next" type="button" aria-label="next plane">→</button>
        <button class="navbtn" part="play" type="button" aria-label="play">▶</button>
        <div class="readout" part="readout"></div>
      </div>`;
    this._root.appendChild(this._wrap);

    this._axisEl = this._wrap.querySelector(".axis")!;
    this._stage = this._wrap.querySelector(".stage")!;
    this._scene = this._wrap.querySelector(".scene")!;
    this._scrub = this._wrap.querySelector("input")!;
    this._readout = this._wrap.querySelector(".readout")!;
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
    this.tabIndex = this.tabIndex < 0 ? 0 : this.tabIndex;
    this.addEventListener("keydown", (e) => this._onKey(e));

    // Unified pointer handling: one path for mouse, touch, and pen.
    this._stage.addEventListener("pointerdown", (e) => this._onPointerDown(e));
    this._stage.addEventListener("pointermove", (e) => this._onPointerMove(e));
    this._stage.addEventListener("pointerup", (e) => this._onPointerUp(e));
    this._stage.addEventListener("pointercancel", (e) => this._onPointerUp(e));
  }

  private _showError(message: string): void {
    if (!this._wrap) this._build();
    this._scene.innerHTML = "";
    this._els = [];
    const box = document.createElement("div");
    box.className = "err";
    box.setAttribute("part", "error");
    box.textContent = message;
    this._scene.appendChild(box);
  }

  private _buildPlanes(): void {
    this._scene.innerHTML = "";
    this._els = [];
    this._axisEl.textContent = this._doc ? `axis = ${this._doc.axis}` : "";
    this._planes.forEach((plane, idx) => {
      const el = document.createElement("div");
      el.className = "plane";
      el.setAttribute("part", "plane");
      const tag = plane.label ? plane.label : `z ${plane.z}`;
      el.innerHTML = `<div class="ptag"><span>z = ${plane.z}</span><b>${esc(tag)}</b></div>${renderMarkdown(plane.body)}`;
      el.addEventListener("click", () => this._setTarget(idx));
      this._scene.appendChild(el);
      this._els.push(el);
    });
    this._scrub.max = String(Math.max(0, this._planes.length - 1));
    this._scrub.value = "0";
    this._updateReadout();
  }

  // MARK: - Playback

  /** Advance one plane, wrapping. Used by the autoplay timer only. */
  private _step(): void {
    const n = this._planes.length;
    if (n <= 1) return;
    this._target = (Math.round(this._target) + 1) % n;
    this._focus = this._target;
    this._scrub.value = String(this._target);
    this.render();
  }

  private _startPlay(): void {
    if (this._playing || this._planes.length <= 1) return;
    this._playing = true;
    if (this._playBtn) { this._playBtn.textContent = "⏸"; this._playBtn.setAttribute("aria-label", "pause"); }
    // Honor the document's fps metadata; clamp so playback stays watchable.
    // setInterval (not rAF) keeps animations running under iOS Low Power Mode.
    const fps = this._doc ? parseInt(this._doc.metadata?.fps ?? "", 10) : NaN;
    const delay = fps > 0 ? Math.min(1000, Math.max(80, 1000 / fps)) : 600;
    this._playTimer = setInterval(() => this._step(), delay);
  }

  private _stopPlay(): void {
    this._playing = false;
    if (this._playTimer) { clearInterval(this._playTimer); this._playTimer = null; }
    if (this._playBtn) { this._playBtn.textContent = "▶"; this._playBtn.setAttribute("aria-label", "play"); }
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
    if (e.key === "ArrowRight" || e.key === "ArrowUp") { this._setTarget(Math.round(this._target) + 1); e.preventDefault(); }
    else if (e.key === "ArrowLeft" || e.key === "ArrowDown") { this._setTarget(Math.round(this._target) - 1); e.preventDefault(); }
  }

  private _onPointerDown(e: PointerEvent): void {
    this._stopPlay(); // dragging takes over from playback
    this._dragging = true;
    this._pointerId = e.pointerId;
    this._lastX = e.clientX;
    this._lastY = e.clientY;
    this._dragStartX = e.clientX;
    this._dragStartY = e.clientY;
    this._dragStartTarget = this._target;
    this._dragAxis = null;
    try { this._stage.setPointerCapture(e.pointerId); } catch { /* not all envs support capture */ }
  }

  private _onPointerMove(e: PointerEvent): void {
    const rect = this._stage.getBoundingClientRect();
    this._mx = (e.clientX - rect.left) / rect.width - 0.5;
    this._my = (e.clientY - rect.top) / rect.height - 0.5;
    if (!this._dragging || (this._pointerId !== null && e.pointerId !== this._pointerId)) return;
    // Lock to the dominant axis once the finger clearly moves (>8px) so a drag is
    // EITHER orbit OR Z-travel, never a jittery mix. Sideways orbits; up/down
    // travels along Z (about 64px per plane). Movement under the threshold stays
    // a tap, so clicking a plane still selects it.
    const totX = e.clientX - this._dragStartX;
    const totY = e.clientY - this._dragStartY;
    if (!this._dragAxis && Math.hypot(totX, totY) > 8) {
      this._dragAxis = Math.abs(totX) > Math.abs(totY) ? "x" : "y";
    }
    if (this._dragAxis === "x") {
      this._dragRY += (e.clientX - this._lastX) * 0.4;
    } else if (this._dragAxis === "y") {
      const max = this._planes.length - 1;
      // Drag up = forward into the stack (higher Z).
      this._target = Math.max(0, Math.min(max, this._dragStartTarget + (this._dragStartY - e.clientY) / 64));
      this._focus = this._target;
      this._scrub.value = String(this._target);
    }
    this._lastX = e.clientX;
    this._lastY = e.clientY;
    this.render(); // synchronous: works while rAF is paused
  }

  private _onPointerUp(e: PointerEvent): void {
    // If the drag travelled the Z axis, snap to the nearest plane on release.
    if (this._dragging && this._dragAxis === "y") this._setTarget(Math.round(this._target));
    this._dragging = false;
    this._dragAxis = null;
    this._pointerId = null;
    try { this._stage.releasePointerCapture(e.pointerId); } catch { /* ignore */ }
    this.render(); // hold the correct final frame without relying on rAF
  }

  // MARK: - Rendering

  /**
   * Apply the current state to the DOM synchronously. Safe to call at any time,
   * with or without requestAnimationFrame running. This is the single source of
   * truth for what the stage looks like.
   */
  render(): void {
    if (!this._els.length) return;
    const n = this._els.length;
    const focus = this._focus;
    const fr = Math.round(focus);
    const m = this._mode;

    this._els.forEach((el, idx) => {
      let x = 0, y = 0, z = 0, s = 1, o = 1, hot = false, dim = false;
      const d = idx - focus;
      if (m === "stack") {
        z = -Math.abs(d) * 160; y = d * 26; x = d * 30;
        if (idx === fr) { s = 1.05; hot = true; }
      } else if (m === "play") {
        z = -Math.abs(d) * 160; y = d * 26; x = d * 30;
        if (idx === fr) { s = 1.06; hot = true; } else dim = true;
      } else if (m === "layers") {
        z = -Math.abs(d) * 120; y = d * 30; x = d * 34;
        if (idx === fr) { s = 1.04; hot = true; }
      } else if (m === "scene") {
        const p = this._planes[idx];
        x = (p.x || 0) * 4.2; y = -(p.y || 0) * 4.2; z = -p.z * 150;
        if (idx === fr) { hot = true; s = 1.05; }
      } else if (m === "parallax") {
        z = -idx * 175; const near = n - idx;
        x = -this._mx * near * 48; y = -this._my * near * 26;
        s = 1 + (n - 1 - idx) * 0.07;
        if (idx === fr) hot = true;
      } else if (m === "present") {
        if (Math.abs(d) < 0.5) { x = 0; y = 0; z = 120; s = 1.18; o = 1; hot = true; }
        else { x = d * 70; z = -180 - Math.abs(d) * 50; s = 0.6; o = 0.22; dim = true; }
      } else if (m === "elevator") {
        y = d * 150; z = -Math.abs(d) * 120; s = Math.abs(d) < 0.5 ? 1.06 : 0.82;
        o = Math.max(0.12, 1 - Math.abs(d) * 0.45);
        if (Math.abs(d) < 0.5) hot = true; else dim = true;
      }
      el.style.transform = `translate3d(${x}px,${y}px,${z}px) scale(${s.toFixed(3)})`;
      el.style.opacity = String(o);
      el.style.zIndex = idx === fr ? "300" : String(120 - Math.abs(fr - idx));
      el.classList.toggle("hot", hot);
      el.classList.toggle("dim", dim);
    });

    let st: string;
    if (m === "parallax" || m === "present") {
      st = "translateZ(-110px)";
    } else if (m === "elevator") {
      st = `translateZ(-150px) rotateY(${(-6 + this._dragRY).toFixed(2)}deg)`;
    } else {
      const ry = -22 + this._mx * 10 + this._dragRY;
      const rx = 8 - this._my * 8 + this._dragRX;
      st = `translateZ(-160px) rotateX(${rx.toFixed(2)}deg) rotateY(${ry.toFixed(2)}deg)`;
    }
    this._scene.style.transform = st;

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
