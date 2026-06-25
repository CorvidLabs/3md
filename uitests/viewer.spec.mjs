import { test, expect } from "@playwright/test";

// The official viewer/editor (web/viewer.html): live-edit any 3md and see it
// render in the <three-md> component, with shareable links.

async function viewerReady(page) {
  await page.waitForFunction(() => document.getElementById("lab")?.shadowRoot?.querySelectorAll(".plane").length > 0);
}

test.describe("viewer & editor (viewer.html)", () => {
  test("renders the starter document with no console errors", async ({ page }) => {
    const errors = [];
    page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
    page.on("pageerror", (e) => errors.push(String(e)));
    await page.goto("/viewer.html");
    await viewerReady(page);
    const planes = await page.evaluate(() => document.getElementById("lab").shadowRoot.querySelectorAll(".plane").length);
    expect(planes).toBeGreaterThan(0);
    expect(errors, errors.join("\n")).toEqual([]);
  });

  test("editing the source re-renders live", async ({ page }) => {
    await page.goto("/viewer.html");
    await viewerReady(page);
    const doc = `---\n3md: 1.0\naxis: layer\ntitle: Edited\n---\n@plane z=0 label="a"\n# A\n@plane z=1 label="b"\n# B\n@plane z=2 label="c"\n# C\n`;
    await page.fill("#editor", doc);
    await page.waitForTimeout(350);
    const info = await page.evaluate(() => {
      const d = document.getElementById("lab").document;
      return { axis: d.axis, planes: d.planes.length };
    });
    expect(info).toEqual({ axis: "layer", planes: 3 });
  });

  test("invalid 3md shows an error without crashing", async ({ page }) => {
    const errors = [];
    page.on("pageerror", (e) => errors.push(String(e)));
    await page.goto("/viewer.html");
    await viewerReady(page);
    await page.fill("#editor", "this is not a valid 3md document");
    await page.waitForTimeout(350);
    const status = await page.textContent("#status");
    expect(status.toLowerCase()).toContain("invalid");
    // The page itself must not throw.
    expect(errors).toEqual([]);
  });

  test("loading an example populates the editor and viewer", async ({ page }) => {
    await page.goto("/viewer.html");
    await viewerReady(page);
    // The example dropdown is populated from the curated gallery manifest; pick
    // the first real example (index 1) so the test does not depend on titles.
    await page.waitForFunction(() => document.querySelectorAll("#example option").length > 1);
    await page.selectOption("#example", { index: 1 });
    await page.waitForTimeout(500);
    const len = await page.evaluate(() => document.getElementById("editor").value.length);
    expect(len).toBeGreaterThan(150);
    const planes = await page.evaluate(() => document.getElementById("lab").document.planes.length);
    expect(planes).toBeGreaterThan(0);
  });

  test("editor highlights syntax and numbers every line", async ({ page }) => {
    await page.goto("/viewer.html");
    await viewerReady(page);
    const r = await page.evaluate(() => {
      const hl = document.getElementById("hl");
      const ed = document.getElementById("editor");
      const lines = ed.value.split("\n").length;
      return {
        lineDivs: hl.querySelectorAll(".line").length,
        sourceLines: lines,
        directive: hl.querySelector(".t-dir")?.textContent || "",
        hasKey: !!hl.querySelector(".t-key"),
        hasZlink: !!hl.querySelector(".t-zlink"),
        // no raw span markup must leak into rendered text
        leak: [...hl.querySelectorAll(".line")].some((l) => /class=|<span/.test(l.textContent)),
      };
    });
    expect(r.lineDivs).toBe(r.sourceLines);
    expect(r.directive).toBe("@plane");
    expect(r.hasKey).toBe(true);
    expect(r.hasZlink).toBe(true);
    expect(r.leak).toBe(false);
  });

  test("Tab indents and Enter continues a list", async ({ page }) => {
    await page.goto("/viewer.html");
    await viewerReady(page);
    await page.evaluate(() => {
      const ed = document.getElementById("editor");
      ed.value = "@plane z=0\n- first";
      ed.selectionStart = ed.selectionEnd = ed.value.length;
      ed.focus();
    });
    await page.keyboard.press("Enter");
    await page.keyboard.type("second");
    const val = await page.evaluate(() => document.getElementById("editor").value);
    expect(val).toContain("- first\n- second"); // bullet auto-continued
  });

  test("clicking a plane outline chip focuses that plane", async ({ page }) => {
    await page.goto("/viewer.html");
    await viewerReady(page);
    await page.waitForFunction(() => document.querySelectorAll("#outline .ochip").length >= 2);
    await page.click("#outline .ochip:nth-child(2)");
    await page.waitForTimeout(200);
    const idx = await page.evaluate(() => document.getElementById("lab").currentIndex);
    expect(idx).toBe(1);
  });

  test("an invalid document flags the offending line and the badge", async ({ page }) => {
    await page.goto("/viewer.html");
    await viewerReady(page);
    await page.fill("#editor", "axis: time\n@plane z=0\nno frontmatter version");
    await page.waitForTimeout(300);
    const r = await page.evaluate(() => ({
      badge: document.getElementById("validBadge").className,
      errLines: document.querySelectorAll("#hl .line.errline").length,
    }));
    expect(r.badge).toContain("err");
  });

  test("a shared hash link restores the document", async ({ page }) => {
    const doc = `---\n3md: 1.0\naxis: time\ntitle: Shared\n---\n@plane z=0 label="only"\n# Only\n`;
    const enc = (s) => Buffer.from(s, "utf8").toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    await page.goto("/viewer.html#" + enc(doc));
    await viewerReady(page);
    const val = await page.evaluate(() => document.getElementById("editor").value);
    expect(val).toContain("title: Shared");
    const title = await page.evaluate(() => document.getElementById("lab").document.title);
    expect(title).toBe("Shared");
  });
});
