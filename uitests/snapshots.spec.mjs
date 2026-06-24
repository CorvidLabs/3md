import { test, expect } from "@playwright/test";

// Visual snapshot regression for the lab stage across modes. The component is
// fully event-driven (no idle animation), so a settled frame is deterministic.
//
// Pixel snapshots are OS-sensitive (font anti-aliasing differs macOS vs Linux),
// so these run locally as a developer regression check and are skipped in CI,
// where the functional (lab/component) and robustness suites do the gating.
test.skip(!!process.env.CI, "snapshots compared locally; CI gates on functional + robustness suites");

async function labReady(page) {
  await page.waitForFunction(() => {
    const el = document.getElementById("lab");
    return el && el.shadowRoot && el.shadowRoot.querySelectorAll(".plane").length > 0;
  });
}

// Settle the stage at a fixed plane with playback paused, for a stable frame.
async function settle(page, value) {
  await page.evaluate((v) => {
    const lab = document.getElementById("lab");
    lab.pause();
    const s = lab.shadowRoot.querySelector("input[type=range]");
    s.value = String(v); s.dispatchEvent(new Event("input", { bubbles: true }));
  }, value);
  await page.waitForTimeout(250);
}

const CASES = [
  { tab: /time/i, value: 2, name: "stack" },
  { tab: /layer/i, value: 0, name: "layers" },
  { tab: /space/i, value: 0, name: "scene" },
  { tab: /slides/i, value: 1, name: "present" },
];

for (const c of CASES) {
  test(`stage snapshot: ${c.name}`, async ({ page }) => {
    await page.goto("/index.html?theme=dark");
    await labReady(page);
    await page.locator(".tab", { hasText: c.tab }).first().click();
    await labReady(page);
    await settle(page, c.value);
    await expect(page.locator("#lab")).toHaveScreenshot(`lab-${c.name}.png`, { maxDiffPixelRatio: 0.02 });
  });
}
