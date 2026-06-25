import { test, expect } from "@playwright/test";

// Tests for the canonical <three-md> web component (web/assets/three-md.js),
// exercised through web/embed-example.html. These run in both Chromium and
// WebKit and guard the invariants that have actually broken before:
//   1. the focused plane is frontmost in true Z while scrubbing,
//   2. it works with requestAnimationFrame paused (iOS Low Power Mode),
//   3. it does not overflow horizontally at phone widths.

// Reads each plane's true Z (matrix3d m43) from inside the component's shadow
// DOM after scrubbing to `value`, with a hard cap so it never hangs.
const PLANE_Z = (value) => {
  const host = document.getElementById("inline");
  const scrub = host.shadowRoot.querySelector("input[type=range]");
  scrub.value = String(value);
  scrub.dispatchEvent(new Event("input", { bubbles: true }));
  const read = () => [...host.shadowRoot.querySelectorAll(".plane")]
    .map((p) => Math.round(new DOMMatrix(getComputedStyle(p).transform).m43));
  return new Promise((resolve) => {
    let frames = 0;
    const cap = setTimeout(() => resolve(read()), 2000);
    const tick = () => {
      if (typeof requestAnimationFrame === "function" && ++frames < 30) requestAnimationFrame(tick);
      else { clearTimeout(cap); resolve(read()); }
    };
    tick();
  });
};

async function planeCount(page) {
  return page.evaluate(() => document.getElementById("inline").shadowRoot.querySelectorAll(".plane").length);
}

test.describe("<three-md> component", () => {
  test("upgrades, renders planes, no console errors", async ({ page }) => {
    const errors = [];
    page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
    page.on("pageerror", (e) => errors.push(String(e)));
    await page.goto("/embed-example.html");
    await page.waitForFunction(() => {
      const el = document.getElementById("inline");
      return el && el.shadowRoot && el.shadowRoot.querySelectorAll(".plane").length > 0;
    });
    expect(await planeCount(page)).toBe(3);
    // The src= variant must also load and render.
    await page.waitForFunction(() => {
      const el = document.getElementById("remote");
      return el && el.shadowRoot && el.shadowRoot.querySelectorAll(".plane").length > 0;
    });
    expect(errors, errors.join("\n")).toEqual([]);
  });

  test("focused plane is frontmost across the scrubber", async ({ page }) => {
    await page.goto("/embed-example.html");
    await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot?.querySelectorAll(".plane").length === 3);
    for (const value of [0, 1, 2]) {
      const zs = await page.evaluate(PLANE_Z, value);
      expect(zs.length).toBe(3);
      expect(zs[value], `focused plane ${value} frontmost (zs=${zs})`).toBe(Math.max(...zs));
    }
  });

  test("works with requestAnimationFrame paused (Low Power Mode)", async ({ page }) => {
    // Neutralize rAF before any script runs, simulating iOS Low Power throttling
    // that never fires the callback. The component must still be correct.
    await page.addInitScript(() => {
      window.requestAnimationFrame = () => 0;
      window.cancelAnimationFrame = () => {};
    });
    await page.goto("/embed-example.html");
    await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot?.querySelectorAll(".plane").length === 3);
    for (const value of [0, 1, 2]) {
      const zs = await page.evaluate(PLANE_Z, value);
      expect(zs[value], `(rAF paused) focused plane ${value} frontmost (zs=${zs})`).toBe(Math.max(...zs));
    }
  });

  test("no horizontal overflow from 320px to 1440px", async ({ page }) => {
    for (const width of [320, 390, 768, 1024, 1440]) {
      await page.setViewportSize({ width, height: 900 });
      await page.goto("/embed-example.html");
      await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot?.querySelectorAll(".plane").length === 3);
      const overflow = await page.evaluate(() => ({
        doc: document.documentElement.scrollWidth,
        win: window.innerWidth,
      }));
      // Allow 1px for sub-pixel rounding.
      expect(overflow.doc, `no horizontal overflow at ${width}px (doc=${overflow.doc} win=${overflow.win})`).toBeLessThanOrEqual(overflow.win + 1);
    }
  });

  test("playback advances and pauses (animations)", async ({ page }) => {
    await page.goto("/embed-example.html");
    await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot?.querySelectorAll(".plane").length === 3);
    const before = await page.evaluate(() => document.getElementById("inline").currentIndex);
    await page.evaluate(() => document.getElementById("inline").play());
    await page.waitForTimeout(1400); // longer than one ~600ms step
    const playing = await page.evaluate(() => document.getElementById("inline").currentIndex);
    expect(playing, "index advanced during playback").not.toBe(before);
    // Pause and confirm it stops advancing.
    await page.evaluate(() => document.getElementById("inline").pause());
    const at = await page.evaluate(() => document.getElementById("inline").currentIndex);
    await page.waitForTimeout(900);
    const after = await page.evaluate(() => document.getElementById("inline").currentIndex);
    expect(after, "index frozen after pause").toBe(at);
  });

  test("frame animations render as a flipbook (one frame, no deck) and autoplay", async ({ page }) => {
    await page.goto("/embed-example.html");
    await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot?.querySelectorAll(".plane").length === 3);
    const r = await page.evaluate(() => {
      const lab = document.getElementById("inline");
      lab.removeAttribute("mode");
      lab.setSource('---\n3md: 1.0\naxis: frame\nfps: 8\n---\n@plane z=0\nframe a\n@plane z=1\nframe b\n@plane z=2\nframe c\n');
      const planes = [...lab.shadowRoot.querySelectorAll(".plane")];
      const frameCards = lab.shadowRoot.querySelectorAll(".plane.frame").length;
      const op = planes.map((p) => Number(getComputedStyle(p).opacity));
      const visible = op.filter((o) => o > 0.5).length;
      return { mode: lab._mode, playing: lab.playing, frameCards, visible, planes: planes.length };
    });
    // Animation auto-runs as a flipbook: exactly one frame shown, the rest hidden.
    expect(r.mode).toBe("play");
    expect(r.playing).toBe(true);
    expect(r.frameCards).toBe(1);
    expect(r.visible).toBe(1);
    await page.evaluate(() => document.getElementById("inline").pause());
  });

  test("does not auto-convert characters; an optional legend maps them", async ({ page }) => {
    await page.goto("/embed-example.html");
    await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot?.querySelectorAll(".plane").length === 3);
    const r = await page.evaluate(() => {
      const lab = document.getElementById("inline");
      const read = () => lab.shadowRoot.querySelector(".md").textContent;
      // No legend: the letter o must stay an o everywhere (prose and grid).
      lab.removeAttribute("mode");
      lab.setSource('---\n3md: 1.0\naxis: time\n---\n@plane z=0\nFroggy boots\n```\noo.\n.oo\n```\n');
      const plain = read();
      // With a legend, only fenced content is remapped; prose is untouched.
      lab.setSource('---\n3md: 1.0\naxis: time\nlegend: o=#\n---\n@plane z=0\nFroggy boots\n```\noo.\n.oo\n```\n');
      const mapped = read();
      return { plain, mapped };
    });
    // The old renderer force-replaced every o with a dot glyph; it must not now.
    expect(r.plain).toContain("Froggy boots");
    expect(r.plain).toContain("oo.");
    expect(r.plain).not.toContain("●");
    // Legend remaps only the grid: prose "Froggy boots" stays literal.
    expect(r.mapped).toContain("Froggy boots");
    expect(r.mapped).toContain("##.");
  });

  test("camera: WASD/wheel/orbit move the scene; retired modes alias", async ({ page }) => {
    await page.goto("/embed-example.html");
    await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot?.querySelectorAll(".plane").length === 3);
    const r = await page.evaluate(() => {
      const lab = document.getElementById("inline");
      lab.setAttribute("mode", "stack");
      lab.setSource('---\n3md: 1.0\naxis: time\n---\n@plane z=0\nA\n@plane z=1\nB\n@plane z=2\nC\n');
      const scene = lab.shadowRoot.querySelector(".scene");
      const t0 = scene.style.transform;
      lab.dispatchEvent(new KeyboardEvent("keydown", { key: "d" }));   // pan
      lab.dispatchEvent(new KeyboardEvent("keydown", { key: "q" }));   // orbit
      lab.shadowRoot.querySelector(".stage").dispatchEvent(new WheelEvent("wheel", { deltaY: -120, cancelable: true })); // zoom
      const t1 = scene.style.transform;
      // Retired mode names still resolve to a surviving view.
      const aliases = {};
      for (const m of ["parallax", "scene", "deck"]) { lab.setAttribute("mode", m); aliases[m] = lab._mode; }
      // layers and elevator are real modes again, not aliases.
      const real = {};
      for (const m of ["layers", "elevator", "map"]) { lab.setAttribute("mode", m); real[m] = lab._mode; }
      return { changed: t0 !== t1, aliases, real };
    });
    expect(r.changed).toBe(true);
    expect(r.aliases).toEqual({ parallax: "stack", scene: "map", deck: "present" });
    expect(r.real).toEqual({ layers: "layers", elevator: "elevator", map: "map" });
  });

  test("map mode lays planes out by x/y", async ({ page }) => {
    await page.goto("/embed-example.html");
    await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot?.querySelectorAll(".plane").length === 3);
    const xs = await page.evaluate(() => {
      const lab = document.getElementById("inline");
      lab.setAttribute("mode", "map");
      lab.setSource('---\n3md: 1.0\naxis: space\n---\n@plane z=0 x=-4 y=0\nleft\n@plane z=1 x=4 y=0\nright\n');
      return [...lab.shadowRoot.querySelectorAll(".plane")].map((p) => new DOMMatrix(getComputedStyle(p).transform).m41);
    });
    // The two planes sit at different x positions (a real spatial layout).
    expect(xs[0]).not.toBe(xs[1]);
  });

  test("renders Markdown tables (not raw pipes)", async ({ page }) => {
    await page.goto("/embed-example.html");
    await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot?.querySelectorAll(".plane").length === 3);
    const r = await page.evaluate(() => {
      const lab = document.getElementById("inline");
      lab.setAttribute("mode", "single");
      lab.setSource('---\n3md: 1.0\naxis: time\n---\n@plane z=0\n| Item | Cost |\n| --- | --- |\n| Potion | 6 |\n| Scroll | 3 |\n');
      const t = lab.shadowRoot.querySelector(".md table.tbl");
      return { hasTable: !!t, headers: t ? [...t.querySelectorAll("th")].map((x) => x.textContent) : [], rows: t ? t.querySelectorAll("tbody tr").length : 0, rawPipe: /\| Item \| Cost \|/.test(lab.shadowRoot.querySelector(".md").textContent) };
    });
    expect(r.hasTable).toBe(true);
    expect(r.headers).toEqual(["Item", "Cost"]);
    expect(r.rows).toBe(2);
    expect(r.rawPipe).toBe(false);
  });

  test("layers shows aligned overlays at once, with toggle chips", async ({ page }) => {
    await page.goto("/embed-example.html");
    await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot?.querySelectorAll(".plane").length === 3);
    const r = await page.evaluate(() => {
      const lab = document.getElementById("inline");
      lab.setAttribute("mode", "layers");
      lab.setSource('---\n3md: 1.0\naxis: layer\n---\n@plane z=0 label="source"\nA\n@plane z=1 label="plain"\nB\n@plane z=2 label="legal"\nC\n');
      const sr = lab.shadowRoot;
      const planes = [...sr.querySelectorAll(".plane")];
      const visible = planes.filter((p) => Number(getComputedStyle(p).opacity) > 0.1).length; // all overlays visible together
      const aligned = new Set(planes.map((p) => Math.round(new DOMMatrix(getComputedStyle(p).transform).m41))).size === 1; // same x
      const chips = sr.querySelectorAll(".layerchip").length;
      // toggle the first layer off
      sr.querySelector(".layerchip").click();
      return { visible, aligned, chips, hiddenAfterToggle: lab._hiddenLayers.has(0) };
    });
    expect(r.visible).toBe(3);          // overlays seen together, not one-at-a-time
    expect(r.aligned).toBe(true);       // stacked aligned (a deck would fan them in x)
    expect(r.chips).toBe(3);
    expect(r.hiddenAfterToggle).toBe(true);
  });

  test("blend mode renders content as 3D voxels", async ({ page }) => {
    const errors = [];
    page.on("pageerror", (e) => errors.push(String(e)));
    await page.goto("/embed-example.html");
    await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot?.querySelectorAll(".plane").length === 3);
    const result = await page.evaluate(() => {
      const lab = document.getElementById("inline");
      lab.setAttribute("mode", "blend");
      lab.setSource("---\n3md: 1.0\naxis: frame\n---\n@plane z=0\n```\noo\n.o\n```\n@plane z=1\n```\no.\noo\n```\n");
      return {
        voxels: lab.shadowRoot.querySelectorAll(".voxel").length,
        cards: lab.shadowRoot.querySelectorAll(".plane").length,
      };
    });
    // 3 lit cells per plane (oo/.o and o./oo) = 6 voxels, and no plane cards.
    expect(result.voxels).toBe(6);
    expect(result.cards).toBe(0);
    expect(errors).toEqual([]);
  });

  test("single-card mode shows only the focused plane", async ({ page }) => {
    await page.goto("/embed-example.html");
    await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot?.querySelectorAll(".plane").length === 3);
    await page.evaluate(() => {
      const lab = document.getElementById("inline");
      lab.setAttribute("mode", "single");
      const s = lab.shadowRoot.querySelector("input[type=range]"); s.value = "1"; s.dispatchEvent(new Event("input", { bubbles: true }));
    });
    // Wait until the opacity transition has actually settled, rather than a fixed
    // timeout (which was flaky on slower CI/WebKit, sampling mid-fade).
    await page.waitForFunction(() => {
      const op = [...document.getElementById("inline").shadowRoot.querySelectorAll(".plane")].map((p) => Number(getComputedStyle(p).opacity));
      return op[1] > 0.95 && op[0] < 0.02 && op[2] < 0.02;
    }, { timeout: 4000 });
    const op = await page.evaluate(() =>
      [...document.getElementById("inline").shadowRoot.querySelectorAll(".plane")].map((p) => Number(getComputedStyle(p).opacity)));
    // Only plane index 1 is visible; the others are fully faded out once settled.
    expect(op[1]).toBeGreaterThan(0.95);
    expect(op[0]).toBeLessThan(0.05);
    expect(op[2]).toBeLessThan(0.05);
  });

  test("single-card mode scrolls a long plane (reader)", async ({ page }) => {
    await page.goto("/embed-example.html");
    await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot?.querySelectorAll(".plane").length === 3);
    const long = "---\n3md: 1.0\naxis: doc\nview: single\n---\n@plane z=0 label=\"Long\"\n# Long\n\n" +
      Array.from({ length: 150 }, (_, i) => `Paragraph ${i + 1}. Lorem ipsum dolor sit amet.`).join("\n\n") +
      "\n@plane z=1 label=\"Short\"\n# Short\n\nLittle.\n";
    const r = await page.evaluate((src) => {
      const el = document.getElementById("inline");
      el.setSource(src);
      const reader = el.shadowRoot.querySelector(".plane.reader");
      const overflowY = getComputedStyle(reader).overflowY;
      const overflows = reader.scrollHeight > reader.clientHeight + 10;
      reader.scrollTop = 500;
      return { hasReader: !!reader, overflowY, overflows, scrolled: reader.scrollTop > 0 };
    }, long);
    // The focused plane is a real scroll container, so a 150-paragraph plane is
    // fully readable instead of being clipped by the stage.
    expect(r.hasReader).toBe(true);
    expect(r.overflowY).toBe("auto");
    expect(r.overflows).toBe(true);
    expect(r.scrolled).toBe(true);
  });

  test("reflects the resolved mode as data-mode (for fullscreen styling)", async ({ page }) => {
    await page.goto("/embed-example.html");
    await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot?.querySelectorAll(".plane").length === 3);
    const modes = await page.evaluate(() => {
      const el = document.getElementById("inline");
      const out = {};
      for (const m of ["present", "single", "stack"]) { el.setAttribute("mode", m); out[m] = el.getAttribute("data-mode"); }
      // blend only resolves to blend for a doc with voxelizable ASCII art; a text
      // doc falls back to the deck, so load real grid art before checking blend.
      el.setAttribute("mode", "blend");
      el.setSource('---\n3md: 1.0\naxis: depth\n---\n@plane z=0\n```\n##\n##\n```\n@plane z=1\n```\n.#\n#.\n```\n');
      out.blend = el.getAttribute("data-mode");
      return out;
    });
    expect(modes).toEqual({ present: "present", single: "single", stack: "stack", blend: "blend" });
  });

  test("space and PageDown advance like a slideshow (not in reader)", async ({ page }) => {
    await page.goto("/embed-example.html");
    await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot?.querySelectorAll(".plane").length === 3);
    const r = await page.evaluate(() => {
      const el = document.getElementById("inline");
      el.setAttribute("mode", "present");
      el.focus();
      const fire = (key) => el.dispatchEvent(new KeyboardEvent("keydown", { key, bubbles: true }));
      const start = el.currentIndex;
      fire("PageDown"); const afterPage = el.currentIndex;
      fire(" "); const afterSpace = el.currentIndex;
      fire("PageUp"); const afterUp = el.currentIndex;
      // In reader (single) mode, space must NOT advance (it scrolls the body).
      el.setAttribute("mode", "single"); el.focus();
      const sBefore = el.currentIndex; fire(" "); const sAfter = el.currentIndex;
      return { start, afterPage, afterSpace, afterUp, spaceInReaderMoved: sAfter !== sBefore };
    });
    expect(r.afterPage).toBe(r.start + 1);
    expect(r.afterSpace).toBe(r.start + 2);
    expect(r.afterUp).toBe(r.start + 1);
    expect(r.spaceInReaderMoved).toBe(false);
  });

  test("cross-plane links [[z=N|text]] are clickable and navigate", async ({ page }) => {
    await page.goto("/embed-example.html");
    await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot?.querySelectorAll(".plane").length === 3);
    const r = await page.evaluate(() => {
      const lab = document.getElementById("inline");
      lab.removeAttribute("mode");
      lab.setSource('---\n3md: 1.0\naxis: space\n---\n@plane z=0\nGo to [[z=2|the vault]].\n@plane z=1\nmid\n@plane z=2\nback to [[z=0|start]]\n');
      const link = lab.shadowRoot.querySelector('.xlink[data-z="2"]');
      const text = link?.textContent;
      link.click();
      return { hasLink: !!link, text, indexAfter: lab.currentIndex };
    });
    expect(r.hasLink).toBe(true);
    expect(r.text).toBe("the vault");
    expect(r.indexAfter).toBe(2);
  });

  test("a tap (pointer, no drag) on a cross-plane link navigates", async ({ page }) => {
    await page.goto("/embed-example.html");
    await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot?.querySelectorAll(".plane").length === 3);
    const idx = await page.evaluate(() => {
      const lab = document.getElementById("inline");
      lab.setAttribute("mode", "stack"); // a camera mode: orbit must not eat the tap
      lab.setSource('---\n3md: 1.0\naxis: space\n---\n@plane z=0\n[[z=2|the vault]]\n@plane z=1\nmid\n@plane z=2\nvault\n');
      const link = lab.shadowRoot.querySelector(".xlink");
      const r = link.getBoundingClientRect();
      const o = { bubbles: true, clientX: r.x + 2, clientY: r.y + 2, pointerId: 1 };
      // A real tap: down then up at the same spot (no movement), then click.
      link.dispatchEvent(new PointerEvent("pointerdown", o));
      link.dispatchEvent(new PointerEvent("pointerup", o));
      link.dispatchEvent(new MouseEvent("click", o));
      return lab.currentIndex;
    });
    expect(idx).toBe(2);
  });

  test("flipbook frames are a fixed size (no resize between frames)", async ({ page }) => {
    await page.goto("/embed-example.html");
    await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot?.querySelectorAll(".plane").length === 3);
    const r = await page.evaluate(() => {
      const lab = document.getElementById("inline");
      lab.setAttribute("mode", "play");
      // Two frames of very different content length.
      lab.setSource('---\n3md: 1.0\naxis: frame\n---\n@plane z=0\nx\n@plane z=1\n# Big\n\nlots and lots of text here that is much longer than the first frame body\n');
      lab.pause();
      const box = () => { const f = lab.shadowRoot.querySelector(".plane.frame").getBoundingClientRect(); return [Math.round(f.width), Math.round(f.height)]; };
      const a = box();
      const s = lab.shadowRoot.querySelector("input[type=range]"); s.value = "1"; s.dispatchEvent(new Event("input", { bubbles: true }));
      const b = box();
      return { a, b };
    });
    expect(r.a).toEqual(r.b);
  });

  test("loop toggle controls whether playback wraps", async ({ page }) => {
    await page.goto("/embed-example.html");
    await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot?.querySelectorAll(".plane").length === 3);
    const r = await page.evaluate(() => {
      const lab = document.getElementById("inline");
      const btn = lab.shadowRoot.querySelector('[part="loop"]');
      const start = btn.getAttribute("aria-pressed");
      btn.click();
      // The button row must not contain the (variable-width) readout, so it never
      // reflows and shifts the play button under the cursor.
      const controls = lab.shadowRoot.querySelector(".controls");
      return { start, toggled: btn.getAttribute("aria-pressed"), readoutInRow: !!controls.querySelector(".readout") };
    });
    expect(r.start).toBe("true");
    expect(r.toggled).toBe("false");
    expect(r.readoutInRow).toBe(false);
  });

  test("emits planechange when stepping", async ({ page }) => {
    await page.goto("/embed-example.html");
    await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot?.querySelectorAll(".plane").length === 3);
    const got = await page.evaluate(() => new Promise((resolve) => {
      const host = document.getElementById("inline");
      host.addEventListener("planechange", (e) => resolve(e.detail), { once: true });
      host.shadowRoot.querySelector('[part="next"]').click();
    }));
    expect(got.index).toBe(1);
    expect(got.z).toBe(1);
  });

  test("legend values cannot inject HTML (XSS sink is escaped)", async ({ page }) => {
    const errors = [];
    page.on("pageerror", (e) => errors.push(String(e)));
    await page.goto("/embed-example.html");
    await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot?.querySelectorAll(".plane").length === 3);
    const r = await page.evaluate(async () => {
      const lab = document.getElementById("inline");
      window.__xss = 0;
      // Three independent code/markup-injection vectors through the legend value.
      const vectors = [
        "g=<details/open/ontoggle=window.__xss=1>",
        "g=<iframe/src=javascript:window.__xss=1>",
        "g=<img/src=x/onerror=window.__xss=1>",
      ];
      const out = [];
      for (const leg of vectors) {
        lab.removeAttribute("mode");
        lab.setSource(`---\n3md: 1.0\naxis: time\nlegend: ${leg}\n---\n@plane z=0\n\`\`\`\nggg\n\`\`\`\n`);
        await new Promise((res) => setTimeout(res, 60));
        const html = lab.shadowRoot.querySelector(".md")?.innerHTML || "";
        out.push({ hasIframe: /<iframe/i.test(html), hasImg: /<img/i.test(html), hasDetails: /<details/i.test(html) });
      }
      return { out, xss: window.__xss, iframes: lab.shadowRoot.querySelectorAll("iframe").length };
    });
    // No vector created a live element or fired script.
    expect(r.xss).toBe(0);
    expect(r.iframes).toBe(0);
    for (const v of r.out) {
      expect(v.hasIframe).toBe(false);
      expect(v.hasImg).toBe(false);
      expect(v.hasDetails).toBe(false);
    }
    expect(errors).toEqual([]);
  });

  test("cross-plane links work for decimal z (not just integers)", async ({ page }) => {
    await page.goto("/embed-example.html");
    await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot?.querySelectorAll(".plane").length === 3);
    const r = await page.evaluate(() => {
      const lab = document.getElementById("inline");
      lab.setAttribute("mode", "stack");
      lab.setSource('---\n3md: 1.0\naxis: depth\n---\n@plane z=0\nGo [[z=1.5|to mid]] now.\n@plane z=1.5\nMid plane.\n@plane z=3\nDeep.\n');
      const sr = lab.shadowRoot;
      const link = sr.querySelector('.xlink[data-z="1.5"]');
      const rawLeaks = /\[\[z=1\.5/.test(sr.querySelector(".md").textContent);
      if (link) link.dispatchEvent(new MouseEvent("click", { bubbles: true }));
      return { hasLink: !!link, rawLeaks, idx: lab.currentIndex };
    });
    expect(r.hasLink).toBe(true);     // decimal z rendered as a clickable link
    expect(r.rawLeaks).toBe(false);   // not left as literal [[z=1.5|...]] text
    expect(r.idx).toBe(1);            // clicking jumped to the z=1.5 plane (index 1)
  });

  test("switching into blend after load builds voxels (no empty stage)", async ({ page }) => {
    await page.goto("/embed-example.html");
    await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot?.querySelectorAll(".plane").length === 3);
    const r = await page.evaluate(async () => {
      const lab = document.getElementById("inline");
      lab.removeAttribute("mode"); // load in a card mode first
      lab.setSource('---\n3md: 1.0\naxis: depth\n---\n@plane z=0\n```\n##\n##\n```\n@plane z=1\n```\n..\n##\n```\n');
      await new Promise((res) => setTimeout(res, 60));
      lab.setAttribute("mode", "blend"); // dynamic switch AFTER source is loaded
      await new Promise((res) => setTimeout(res, 120));
      return { voxels: lab.shadowRoot.querySelectorAll(".voxel").length };
    });
    expect(r.voxels).toBeGreaterThan(0);
  });

  test("blend voxels are the legend-mapped character glyphs, and billboard faces the camera", async ({ page }) => {
    await page.goto("/embed-example.html");
    await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot);
    const r = await page.evaluate(() => {
      const lab = document.getElementById("inline");
      lab.setAttribute("mode", "blend");
      lab.setSource('---\n3md: 1.0\naxis: depth\nlegend: "#"=🧱 o=🟦\nbillboard: true\n---\n@plane z=0\n```\n#o#\n#o#\n```\n');
      const vox = [...lab.shadowRoot.querySelectorAll(".voxel")];
      return {
        glyphs: [...new Set(vox.map((v) => v.textContent))].sort(),
        billboard: vox.length > 0 && vox.every((v) => /rotateY/.test(v.style.transform)),
        noGreenDots: vox.every((v) => getComputedStyle(v).borderRadius !== "50%"),
      };
    });
    expect(r.glyphs).toEqual(["🟦", "🧱"]); // legend overrode the raw # and o
    expect(r.billboard).toBe(true);
    expect(r.noGreenDots).toBe(true);
  });

  test("without a legend, blend voxels show the raw characters", async ({ page }) => {
    await page.goto("/embed-example.html");
    await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot);
    const glyphs = await page.evaluate(() => {
      const lab = document.getElementById("inline");
      lab.setAttribute("mode", "blend");
      lab.setSource('---\n3md: 1.0\naxis: depth\n---\n@plane z=0\n```\nAB\nBA\n```\n');
      return [...new Set([...lab.shadowRoot.querySelectorAll(".voxel")].map((v) => v.textContent))].sort();
    });
    expect(glyphs).toEqual(["A", "B"]); // raw chars, no legend
  });

  test("map and layers keep every tile inside the stage on all edges (many tiles)", async ({ page }) => {
    await page.goto("/embed-example.html");
    await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot?.querySelectorAll(".plane").length === 3);
    // A document with many planes: enough to spill a fixed-size board off the sides
    // (this is the horizontal-overflow regression the vertical-only audit missed).
    const planes = Array.from({ length: 16 }, (_, i) => `@plane z=${i}\nFrame ${i}\n\`\`\`\n#### ####\n## ## ##\n\`\`\`\n`).join("\n");
    const doc = `---\n3md: 1.0\naxis: space\n---\n${planes}`;
    for (const mode of ["map", "layers"]) {
      const worst = await page.evaluate(({ doc, mode }) => {
        const lab = document.getElementById("inline");
        lab.setAttribute("mode", mode);
        lab.setSource(doc);
        const sr = lab.shadowRoot;
        const stage = sr.querySelector(".stage").getBoundingClientRect();
        let max = 0;
        for (const el of sr.querySelectorAll(".plane")) {
          if (Number(getComputedStyle(el).opacity) < 0.05) continue; // skip hidden layers
          const r = el.getBoundingClientRect();
          max = Math.max(max, stage.top - r.top, r.bottom - stage.bottom, stage.left - r.left, r.right - stage.right);
        }
        return Math.round(max);
      }, { doc, mode });
      // A small tolerance for sub-pixel/shadow; the regression was 60-100px spills.
      expect(worst, `${mode} worst overflow ${worst}px`).toBeLessThanOrEqual(12);
    }
  });

  test("map orbit is clamped so an extreme pose never spills a tile off the stage", async ({ page }) => {
    await page.goto("/embed-example.html");
    await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot?.querySelectorAll(".plane").length === 3);
    const r = await page.evaluate(() => {
      const lab = document.getElementById("inline");
      const planes = Array.from({ length: 12 }, (_, i) => `@plane z=${i} x=${(i % 6) * 180} y=${Math.floor(i / 6) * 120}\nTile ${i}\n\`\`\`\n#### ####\n\`\`\`\n`).join("\n");
      lab.setAttribute("mode", "map");
      lab.setSource(`---\n3md: 1.0\naxis: space\n---\n${planes}`);
      lab._yaw = 85; lab._pitch = 88; lab.render(); // force an extreme pose
      const sr = lab.shadowRoot;
      const stage = sr.querySelector(".stage").getBoundingClientRect();
      let max = 0;
      // Board tiles only; the focused card is an intentional centered read overlay.
      for (const el of sr.querySelectorAll(".plane:not(.hot)")) {
        if (Number(getComputedStyle(el).opacity) < 0.05) continue;
        const h = el.getBoundingClientRect();
        max = Math.max(max, stage.top - h.top, h.bottom - stage.bottom, stage.left - h.left, h.right - stage.right);
      }
      return { yaw: lab._yaw, pitch: lab._pitch, worst: Math.round(max) };
    });
    expect(Math.abs(r.yaw)).toBeLessThanOrEqual(30); // orbit clamped on render
    expect(r.pitch).toBeLessThanOrEqual(52);
    expect(r.worst, `worst overflow ${r.worst}px at extreme pose`).toBeLessThanOrEqual(12);
  });

  test("map snaps coordinates to a non-overlapping grid (same x = column, same y = row)", async ({ page }) => {
    await page.goto("/embed-example.html");
    await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot?.querySelectorAll(".plane").length === 3);
    const r = await page.evaluate(() => {
      const lab = document.getElementById("inline");
      lab.setAttribute("mode", "map");
      // 4 planes on a 2x2 coordinate grid.
      lab.setSource('---\n3md: 1.0\naxis: space\n---\n@plane z=0 x=1 y=1\nA\n@plane z=1 x=1 y=2\nB\n@plane z=2 x=2 y=1\nC\n@plane z=3 x=2 y=2\nD\n');
      // Map opens on the full-board overview: all 4 tiles laid out, none popped.
      const rects = [...lab.shadowRoot.querySelectorAll(".plane")].map((e) => e.getBoundingClientRect());
      const m = (e) => ({ x: Math.round(e.x + e.width / 2), y: Math.round(e.y + e.height / 2) });
      const c = rects.map(m);
      // no overlap
      let overlap = 0;
      for (let i = 0; i < rects.length; i++) for (let j = i + 1; j < rects.length; j++) {
        const a = rects[i], b = rects[j];
        const ox = Math.min(a.right, b.right) - Math.max(a.left, b.left);
        const oy = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top);
        if (ox > 0 && oy > 0) overlap = Math.max(overlap, Math.min(ox, oy));
      }
      // idx0=x1y1, idx1=x1y2, idx2=x2y1, idx3=x2y2.
      // idx0 & idx1 share column x=1; idx0 & idx2 share row y=1.
      return { overlap: Math.round(overlap), sameColX: Math.abs(c[0].x - c[1].x) < 6, sameRowY: Math.abs(c[0].y - c[2].y) < 6 };
    });
    expect(r.overlap).toBe(0);       // cells never overlap
    expect(r.sameColX).toBe(true);   // same x => same column (same screen x)
    expect(r.sameRowY).toBe(true);   // same y => same row (same screen y)
  });

  test("map: no-coordinate planes lay out in a clean non-overlapping grid", async ({ page }) => {
    await page.goto("/embed-example.html");
    await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot?.querySelectorAll(".plane").length === 3);
    const overlap = await page.evaluate(() => {
      const lab = document.getElementById("inline");
      lab.setAttribute("mode", "map");
      lab.setSource('---\n3md: 1.0\naxis: space\n---\n' + Array.from({ length: 9 }, (_, i) => `@plane z=${i}\nCard ${i}`).join("\n"));
      const rects = [...lab.shadowRoot.querySelectorAll(".plane:not(.hot)")].map((e) => e.getBoundingClientRect());
      let worst = 0;
      for (let i = 0; i < rects.length; i++) for (let j = i + 1; j < rects.length; j++) {
        const a = rects[i], b = rects[j];
        const ox = Math.min(a.right, b.right) - Math.max(a.left, b.left);
        const oy = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top);
        if (ox > 0 && oy > 0) worst = Math.max(worst, Math.min(ox, oy));
      }
      return Math.round(worst);
    });
    expect(overlap).toBe(0);
  });

  test("map: the focused card pops to a larger readable size than the board tiles", async ({ page }) => {
    await page.goto("/embed-example.html");
    await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot?.querySelectorAll(".plane").length === 3);
    const r = await page.evaluate(() => {
      const lab = document.getElementById("inline");
      lab.setAttribute("mode", "map");
      lab.setSource('---\n3md: 1.0\naxis: space\n---\n@plane z=0 x=1 y=1\n# Table A\nSeat 1: Ana\nSeat 2: Ben\n@plane z=1 x=2 y=1\n# Table B\nSeat 1: Cal\n@plane z=2 x=1 y=2\n# Table C\nSeat 1: Dee\n');
      lab._mapOverview = false; lab.goTo(0); lab.render(); // open a card (as a click does)
      const sr = lab.shadowRoot;
      const hot = sr.querySelector(".plane.hot").getBoundingClientRect();
      const tile = sr.querySelector(".plane:not(.hot)").getBoundingClientRect();
      return { hotW: Math.round(hot.width), tileW: Math.round(tile.width) };
    });
    // The focused (read) card is clearly larger than a board tile.
    expect(r.hotW).toBeGreaterThan(r.tileW * 1.2);
  });

  test("map opens on a full-board overview (nothing forced open) until a tile is opened", async ({ page }) => {
    await page.goto("/embed-example.html");
    await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot?.querySelectorAll(".plane").length === 3);
    const r = await page.evaluate(() => {
      const lab = document.getElementById("inline");
      lab.setAttribute("mode", "map");
      lab.setSource('---\n3md: 1.0\naxis: space\n---\n@plane z=0 x=1 y=1\n# A\nhi\n@plane z=1 x=2 y=1\n# B\nyo\n@plane z=2 x=1 y=2\n# C\nyo\n');
      const sr = lab.shadowRoot;
      const overview = { popped: sr.querySelectorAll(".detail .plane").length, dimmed: [...sr.querySelectorAll(".scene .plane")].filter((p) => Number(getComputedStyle(p).opacity) < 0.9).length, attr: lab.getAttribute("data-map-overview") };
      lab._mapOverview = false; lab.goTo(0); lab.render(); // open a tile
      const opened = sr.querySelectorAll(".detail .plane.hot").length;
      lab._mapOverview = true; lab.render(); // Esc / tap empty -> back to board
      const closed = sr.querySelectorAll(".detail .plane").length;
      return { overview, opened, closed };
    });
    expect(r.overview.attr).toBe("true");
    expect(r.overview.popped).toBe(0);   // nothing popped by default
    expect(r.overview.dimmed).toBe(0);   // no tile dimmed (all equal on the board)
    expect(r.opened).toBe(1);            // opening a tile pops it
    expect(r.closed).toBe(0);            // returning clears the overlay
  });

  test("map: partially-positioned planes (only x or only y) do not pile up", async ({ page }) => {
    await page.goto("/embed-example.html");
    await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot?.querySelectorAll(".plane").length === 3);
    const pts = await page.evaluate(() => {
      const lab = document.getElementById("inline");
      lab.setAttribute("mode", "map");
      // Two planes with ONLY x set (y omitted) plus one with only y: the missing
      // axis must come from the grid, not collapse to the board centre.
      lab.setSource('---\n3md: 1.0\naxis: space\n---\n@plane z=0 x=2\nonly x a\n@plane z=1 x=8\nonly x b\n@plane z=2 y=4\nonly y\n');
      return [...lab.shadowRoot.querySelectorAll(".plane")].map((p) => {
        const m = new DOMMatrix(getComputedStyle(p).transform);
        return Math.round(m.m41) + "," + Math.round(m.m42);
      });
    });
    expect(new Set(pts).size).toBe(3); // all three at distinct positions
  });

  test("map: unpositioned planes do not collapse onto explicit (0,0)", async ({ page }) => {
    await page.goto("/embed-example.html");
    await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot?.querySelectorAll(".plane").length === 3);
    const pts = await page.evaluate(() => {
      const lab = document.getElementById("inline");
      lab.setAttribute("mode", "map");
      // One plane explicitly at the origin, two with no coordinates at all.
      lab.setSource('---\n3md: 1.0\naxis: space\n---\n@plane z=0 x=0 y=0\norigin\n@plane z=1\nfloating one\n@plane z=2\nfloating two\n');
      return [...lab.shadowRoot.querySelectorAll(".plane")].map((p) => {
        const m = new DOMMatrix(getComputedStyle(p).transform);
        return [Math.round(m.m41), Math.round(m.m42)];
      });
    });
    // All three planes land at distinct board positions (none piled on the origin).
    const uniq = new Set(pts.map((p) => p.join(","))).size;
    expect(uniq).toBe(3);
  });
});
