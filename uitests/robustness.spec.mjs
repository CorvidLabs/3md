import { test, expect } from "@playwright/test";

// "It got worse the more I used it." These tests hammer the lab and assert it
// does NOT degrade: no animation-loop accumulation, no DOM growth, the renderer
// stays correct, and the console stays clean - no matter how much you use it.

async function labReady(page) {
  await page.waitForFunction(() => {
    const el = document.getElementById("lab");
    return el && el.shadowRoot && el.shadowRoot.querySelectorAll(".plane").length > 0;
  });
}

// Count requestAnimationFrame callbacks fired in a window, to detect whether
// more than one render loop is running (the classic "gets worse with use" bug).
async function rafRate(page, ms = 500) {
  const a = await page.evaluate(() => window.__rafCount());
  await page.waitForTimeout(ms);
  const b = await page.evaluate(() => window.__rafCount());
  return b - a;
}

async function shadowNodeCount(page) {
  return page.evaluate(() => document.getElementById("lab").shadowRoot.querySelectorAll("*").length);
}

test.describe("robustness (no degradation under heavy use)", () => {
  test.beforeEach(async ({ page }) => {
    await page.addInitScript(() => {
      let c = 0;
      const orig = window.requestAnimationFrame.bind(window);
      window.requestAnimationFrame = (cb) => orig((t) => { c++; return cb(t); });
      window.__rafCount = () => c;
    });
  });

  test("no rAF-loop accumulation after switching tabs many times", async ({ page }) => {
    const errors = [];
    page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
    page.on("pageerror", (e) => errors.push(String(e)));

    await page.goto("/index.html");
    await labReady(page);
    const baseRate = await rafRate(page);

    // Hammer: cycle through every axis tab several times, scrubbing each.
    const tabs = await page.locator(".tab").count();
    for (let round = 0; round < 6; round++) {
      for (let i = 0; i < tabs; i++) {
        await page.locator(".tab").nth(i).click();
        await page.waitForTimeout(30);
        await page.evaluate(() => {
          const s = document.getElementById("lab").shadowRoot.querySelector("input[type=range]");
          s.value = s.max; s.dispatchEvent(new Event("input", { bubbles: true }));
        });
      }
    }

    const afterRate = await rafRate(page);
    // One loop -> afterRate ~ baseRate. Accumulated loops -> a multiple of it.
    expect(afterRate, `rAF rate stayed bounded (base=${baseRate} after=${afterRate})`).toBeLessThan(baseRate * 1.8 + 8);
    expect(errors, errors.join("\n")).toEqual([]);
  });

  test("DOM does not grow and the renderer stays correct after heavy use", async ({ page }) => {
    await page.goto("/index.html");
    await labReady(page);
    const baseNodes = await shadowNodeCount(page);

    const tabs = await page.locator(".tab").count();
    for (let round = 0; round < 8; round++) {
      for (let i = 0; i < tabs; i++) {
        await page.locator(".tab").nth(i).click();
        await page.waitForTimeout(25);
      }
    }
    // Return to the first (stack) tab and let it settle.
    await page.locator(".tab").nth(0).click();
    await page.waitForTimeout(200);

    const afterNodes = await shadowNodeCount(page);
    // Node count is a function of the current document, not history. Allow a
    // little slack but it must not balloon with use.
    expect(afterNodes, `shadow DOM bounded (base=${baseNodes} after=${afterNodes})`).toBeLessThan(baseNodes + 40);

    // The focused plane must still be frontmost after all that use.
    const zs = await page.evaluate(() => {
      const sr = document.getElementById("lab").shadowRoot;
      const s = sr.querySelector("input[type=range]"); s.value = "0"; s.dispatchEvent(new Event("input", { bubbles: true }));
      return [...sr.querySelectorAll(".plane")].map((p) => Math.round(new DOMMatrix(getComputedStyle(p).transform).m43));
    });
    expect(zs[0], `focused plane still frontmost after heavy use (zs=${zs})`).toBe(Math.max(...zs));
  });

  test("rapid play/pause and scrub leave no timers or errors", async ({ page }) => {
    const errors = [];
    page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
    page.on("pageerror", (e) => errors.push(String(e)));
    await page.goto("/index.html");
    await labReady(page);
    // Switch to the animation tab (autoplays) and thrash play/pause + scrub.
    await page.locator(".tab", { hasText: /frame/i }).first().click();
    await labReady(page);
    for (let i = 0; i < 30; i++) {
      await page.evaluate((n) => {
        const lab = document.getElementById("lab");
        if (n % 2) lab.play(); else lab.pause();
        const s = lab.shadowRoot.querySelector("input[type=range]");
        s.value = String(n % 4); s.dispatchEvent(new Event("input", { bubbles: true }));
      }, i);
      await page.waitForTimeout(20);
    }
    await page.evaluate(() => document.getElementById("lab").pause());
    // After pausing, the index must be frozen (no stray interval still ticking).
    const a = await page.evaluate(() => document.getElementById("lab").currentIndex);
    await page.waitForTimeout(800);
    const b = await page.evaluate(() => document.getElementById("lab").currentIndex);
    expect(b, "no stray autoplay timer after pause").toBe(a);
    expect(errors, errors.join("\n")).toEqual([]);
  });
});
