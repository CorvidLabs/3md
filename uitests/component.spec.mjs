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
    // Only plane index 1 is visible; the others are faded out.
    expect(op[1]).toBe(1);
    expect(op[0]).toBe(0);
    expect(op[2]).toBe(0);
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
