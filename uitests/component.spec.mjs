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
      for (const m of ["layers", "parallax", "elevator", "scene"]) { lab.setAttribute("mode", m); aliases[m] = lab._mode; }
      return { changed: t0 !== t1, aliases };
    });
    expect(r.changed).toBe(true);
    expect(r.aliases).toEqual({ layers: "stack", parallax: "stack", elevator: "stack", scene: "map" });
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
    await page.waitForTimeout(450); // let the opacity transition settle
    const op = await page.evaluate(() =>
      [...document.getElementById("inline").shadowRoot.querySelectorAll(".plane")].map((p) => Number(getComputedStyle(p).opacity)));
    // Only plane index 1 is visible; the others are faded out. Use a tolerance
    // because opacity animates via a CSS transition and may not land on an exact
    // 0 at the moment we sample it.
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
      for (const m of ["present", "single", "stack", "blend"]) { el.setAttribute("mode", m); out[m] = el.getAttribute("data-mode"); }
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
      const link = lab.shadowRoot.querySelector(".xlink");
      const text = link?.textContent;
      link.click();
      return { hasLink: !!link, text, indexAfter: lab.currentIndex };
    });
    expect(r.hasLink).toBe(true);
    expect(r.text).toBe("the vault");
    expect(r.indexAfter).toBe(2);
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
});
