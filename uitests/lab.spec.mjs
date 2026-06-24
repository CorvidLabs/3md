import { test, expect } from "@playwright/test";

// Reads each rendered plane's true Z translation (matrix3d m43) after scrubbing
// to `value` and letting the requestAnimationFrame smoothing settle.
const PLANE_Z = (value) => {
  const scrub = document.getElementById("scrub");
  scrub.value = String(value);
  scrub.dispatchEvent(new Event("input", { bubbles: true }));
  return new Promise((resolve) => {
    let frames = 0;
    (function tick() {
      if (++frames < 90) {
        requestAnimationFrame(tick);
      } else {
        const planes = [...document.querySelectorAll("#scene > .plane")];
        resolve(planes.map((p) => Math.round(new DOMMatrix(getComputedStyle(p).transform).m43)));
      }
    })();
  });
};

// Collects console errors and uncaught exceptions for a page.
function trackErrors(page) {
  const errors = [];
  page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
  page.on("pageerror", (e) => errors.push(String(e)));
  return errors;
}

// Modes that present a single focused plane the reader scrubs to. The spatial
// modes (parallax, scene) lay planes out by their own coordinates and are not
// focus carousels, so the frontmost invariant does not apply to them.
const FOCUS_MODES = ["stack", "play", "layers", "present", "elevator"];

// Scrubbing must stay healthy: planes render at every position, and in a
// focus-navigation mode the focused plane is the frontmost plane in true Z
// (greatest m43) so it renders on top in every engine, not only ones that
// honor z-index. This is the invariant the Safari regression broke.
async function expectScrubHealthy(page) {
  const mode = await page.evaluate(() => { try { return cur && cur.mode; } catch { return null; } });
  // The animation (play) examples auto-start; pause so focus settles where we scrub.
  await page.evaluate(() => {
    try {
      if (typeof playTimer !== "undefined" && playTimer) { clearInterval(playTimer); playTimer = null; }
      if (typeof playing !== "undefined") playing = false;
    } catch { /* not all pages expose these */ }
  });
  const max = await page.evaluate(() => Number(document.getElementById("scrub").max));
  expect(max).toBeGreaterThan(0);
  for (const value of [0, Math.round(max / 2), max]) {
    const zs = await page.evaluate(PLANE_Z, value);
    expect(zs.length, `planes rendered for scrub=${value}`).toBeGreaterThan(1);
    if (FOCUS_MODES.includes(mode)) {
      const focused = Math.round(value);
      expect(zs[focused], `mode=${mode} focused plane ${focused} frontmost (zs=${zs})`).toBe(Math.max(...zs));
    }
  }
}

test.describe("lab demo (index.html)", () => {
  test("renders planes with no console errors", async ({ page }) => {
    const errors = trackErrors(page);
    await page.goto("/index.html");
    await page.waitForTimeout(700);
    const planes = await page.locator("#scene > .plane").count();
    expect(planes).toBeGreaterThan(1);
    expect(errors, errors.join("\n")).toEqual([]);
  });

  test("focused plane is frontmost across the scrubber", async ({ page }) => {
    await page.goto("/index.html");
    await page.waitForTimeout(700);
    await expectScrubHealthy(page);
  });

  test("every axis tab loads and scrubs cleanly", async ({ page }) => {
    const errors = trackErrors(page);
    await page.goto("/index.html");
    await page.waitForTimeout(700);
    const tabCount = await page.locator(".tab").count();
    expect(tabCount).toBeGreaterThan(1);
    for (let i = 0; i < tabCount; i++) {
      await page.locator(".tab").nth(i).click();
      await page.waitForTimeout(700);
      const planes = await page.locator("#scene > .plane").count();
      expect(planes, `tab ${i} renders planes`).toBeGreaterThan(0);
      await expectScrubHealthy(page);
    }
    expect(errors, errors.join("\n")).toEqual([]);
  });
});

test.describe("gallery viewer (gallery.html)", () => {
  test("loads 100 entries and renders an example with no console errors", async ({ page }) => {
    const errors = trackErrors(page);
    await page.goto("/gallery.html");
    await page.waitForSelector(".entry");
    const entries = await page.locator(".entry").count();
    expect(entries).toBe(100);
    const planes = await page.locator("#scene > .plane").count();
    expect(planes).toBeGreaterThan(0);
    expect(errors, errors.join("\n")).toEqual([]);
  });

  test("sampled entries render and scrub cleanly", async ({ page }) => {
    const errors = trackErrors(page);
    await page.goto("/gallery.html");
    await page.waitForSelector(".entry");
    const total = await page.locator(".entry").count();
    // Sample across the (axis-grouped) list so several focus-mode examples are hit.
    for (const i of [3, 24, 47, 71, 95].filter((n) => n < total)) {
      await page.locator(".entry").nth(i).click();
      await page.waitForTimeout(700);
      const planes = await page.locator("#scene > .plane").count();
      expect(planes, `entry ${i} renders planes`).toBeGreaterThan(0);
      await expectScrubHealthy(page);
    }
    expect(errors, errors.join("\n")).toEqual([]);
  });
});
