import { test, expect } from "@playwright/test";

// The lab demo (web/index.html) now drives the canonical <three-md> component
// for its 3D stage, so the demo and the shipped renderer are the same code.
// These tests cover the integration: tabs load documents, the component renders,
// the source panel stays synced, and the focused plane stays frontmost. The
// renderer invariants themselves are also covered directly in component.spec.mjs.

// Reads each plane's true Z (matrix3d m43) from inside the #lab component's
// shadow DOM after scrubbing to `value`, with a hard cap so it never hangs.
const LAB_Z = (value) => {
  const sr = document.getElementById("lab").shadowRoot;
  const scrub = sr.querySelector("input[type=range]");
  scrub.value = String(value);
  scrub.dispatchEvent(new Event("input", { bubbles: true }));
  const read = () => [...sr.querySelectorAll(".plane")]
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

const FOCUS_MODES = ["stack", "play", "layers", "present", "elevator"];

function trackErrors(page) {
  const errors = [];
  page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
  page.on("pageerror", (e) => errors.push(String(e)));
  return errors;
}

async function labReady(page) {
  await page.waitForFunction(() => {
    const el = document.getElementById("lab");
    return el && el.shadowRoot && el.shadowRoot.querySelectorAll(".plane").length > 0;
  });
}

async function expectScrubHealthy(page) {
  const mode = await page.evaluate(() => document.getElementById("lab").mode);
  const max = await page.evaluate(() => Number(document.getElementById("lab").shadowRoot.querySelector("input[type=range]").max));
  expect(max).toBeGreaterThan(0);
  for (const value of [0, Math.round(max / 2), max]) {
    const zs = await page.evaluate(LAB_Z, value);
    expect(zs.length, `planes for scrub=${value}`).toBeGreaterThan(1);
    if (FOCUS_MODES.includes(mode)) {
      expect(zs[value], `mode=${mode} focused plane ${value} frontmost (zs=${zs})`).toBe(Math.max(...zs));
    }
  }
}

test.describe("lab demo (index.html, backed by <three-md>)", () => {
  test("renders via the component with no console errors", async ({ page }) => {
    const errors = trackErrors(page);
    await page.goto("/index.html");
    await labReady(page);
    const planes = await page.evaluate(() => document.getElementById("lab").shadowRoot.querySelectorAll(".plane").length);
    expect(planes).toBeGreaterThan(1);
    expect(await page.locator(".tab").count()).toBeGreaterThan(1);
    expect(errors, errors.join("\n")).toEqual([]);
  });

  test("focused plane is frontmost across the scrubber", async ({ page }) => {
    await page.goto("/index.html");
    await labReady(page);
    await expectScrubHealthy(page);
  });

  test("every axis tab loads, scrubs cleanly, and syncs the source panel", async ({ page }) => {
    const errors = trackErrors(page);
    await page.goto("/index.html");
    await labReady(page);
    const tabCount = await page.locator(".tab").count();
    expect(tabCount).toBeGreaterThan(1);
    for (let i = 0; i < tabCount; i++) {
      await page.locator(".tab").nth(i).click();
      await labReady(page);
      // The synced source panel must show the document.
      const srcBlocks = await page.locator("#src .srcblock").count();
      expect(srcBlocks, `tab ${i} source panel synced`).toBeGreaterThan(0);
      await expectScrubHealthy(page);
    }
    expect(errors, errors.join("\n")).toEqual([]);
  });

  test("no horizontal overflow from 320px to 1440px", async ({ page }) => {
    for (const width of [320, 390, 768, 1280, 1440]) {
      await page.setViewportSize({ width, height: 900 });
      await page.goto("/index.html");
      await labReady(page);
      const overflow = await page.evaluate(() => ({ doc: document.documentElement.scrollWidth, win: window.innerWidth }));
      expect(overflow.doc, `no horizontal overflow at ${width}px (doc=${overflow.doc} win=${overflow.win})`).toBeLessThanOrEqual(overflow.win + 1);
    }
  });

  test("stepping the component highlights the synced source", async ({ page }) => {
    await page.goto("/index.html");
    await labReady(page);
    await page.evaluate(() => document.getElementById("lab").shadowRoot.querySelector('[part="next"]').click());
    await page.waitForTimeout(300);
    const activeIndex = await page.evaluate(() => {
      const active = document.querySelector("#src .srcblock.active");
      return active ? Number(active.dataset.p) : -1;
    });
    expect(activeIndex).toBe(1);
  });
});
