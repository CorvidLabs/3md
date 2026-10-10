import { test, expect } from "@playwright/test";
import { mkdtemp, mkdir, writeFile, rm, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

const draftDocument = (title, body = "Original marker") => `---\n3md: 1.0\naxis: layer\ntitle: ${title}\n---\n@plane z=0 label="First"\n${body}\n@plane z=1 label="Second"\nSecond marker\n`;
async function openCollection(page, files) {
  const directory = await mkdtemp(join(tmpdir(), "3md-viewer-drafts-"));
  try {
    for (const [path, text] of Object.entries(files)) {
      const target = join(directory, path);
      await mkdir(join(target, ".."), { recursive: true });
      await writeFile(target, text);
    }
    await page.locator("#folderInput").setInputFiles(directory);
    await expect(page.locator("#fileList button")).toHaveCount(Object.keys(files).length);
  } finally { await rm(directory, { recursive: true, force: true }); }
}
const openedFile = (page, name) => page.locator("#fileList button").filter({ has: page.locator(".file-name", { hasText: name }) });

// The official viewer/editor (web/viewer.html): live-edit any 3md and see it
// render in the <three-md> component, with shareable links.

async function viewerReady(page) {
  await page.waitForFunction(() => document.getElementById("lab")?.shadowRoot?.querySelectorAll(".plane").length > 0);
}

async function showEditor(page) {
  if (await page.locator("#editor").isVisible()) return;
  await page.click("#editTab");
}

test.describe("viewer & editor (viewer.html)", () => {
  test("opening the page shows lit cubes in the window", async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.goto("/viewer.html");
    await viewerReady(page);
    await page.waitForFunction(() => {
      const canvas = document.getElementById("cubeCanvas");
      return canvas.dataset.renderer === "webgl2" && Number(canvas.dataset.cubes) > 8;
    });
    const seen = await page.evaluate(() => {
      const canvas = document.getElementById("cubeCanvas");
      canvas.dispatchEvent(new Event("threemd-cubes"));
      const rect = canvas.getBoundingClientRect();
      const gl = canvas.__cubeGl;
      const lost = !gl || gl.isContextLost();
      let lit = 0;
      if (!lost) {
        const ratio = canvas.width / Math.max(rect.width, 1);
        const row = Math.max(0, Math.min(canvas.height - 1, Math.floor((rect.height / 2) * ratio)));
        const pixels = new Uint8Array(canvas.width * 4);
        gl.readPixels(0, row, canvas.width, 1, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
        for (let i = 0; i < pixels.length; i += 4) {
          if (pixels[i] + pixels[i + 1] + pixels[i + 2] > 140) lit++;
        }
      }
      return {
        show: document.getElementById("stage").dataset.show,
        top: rect.top,
        bottom: rect.bottom,
        height: rect.height,
        lit,
        lost,
        cubes: Number(canvas.dataset.cubes),
        viewH: window.innerHeight,
      };
    });
    expect(seen.show).toBe("cubes");
    expect(seen.lost).toBe(false);
    expect(seen.height).toBeGreaterThan(80);
    expect(seen.top).toBeGreaterThanOrEqual(0);
    expect(seen.bottom).toBeLessThanOrEqual(seen.viewH + 1);
    expect(seen.cubes).toBeGreaterThan(8);
    expect(seen.lit).toBeGreaterThan(30);
  });

  test("one cell has filled faces from every side, with gold edges and glyph fill", async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.goto("/viewer.html");
    await viewerReady(page);
    await page.evaluate(() => window.threeMd.set("---\n3md: 1.0\naxis: space\n---\n@plane z=0\n```\n#\n```\n@plane z=1\n```\n.\n```\n"));
    const views = await page.evaluate(() => {
      const canvas = document.getElementById("cubeCanvas"), gl = canvas.__cubeGl;
      function pixels() {
        canvas.dispatchEvent(new Event("threemd-cubes"));
        const bytes = new Uint8Array(canvas.width * canvas.height * 4);
        gl.readPixels(0, 0, canvas.width, canvas.height, gl.RGBA, gl.UNSIGNED_BYTE, bytes);
        let gold = 0, teal = 0, holes = 0;
        let left = canvas.width, right = 0, top = canvas.height, bottom = 0;
        for (let y = 0; y < canvas.height; y++) {
          let first = -1, last = -1;
          for (let x = 0; x < canvas.width; x++) {
            const at = (y * canvas.width + x) * 4;
            const r = bytes[at], g = bytes[at + 1], b = bytes[at + 2];
            if (r > g * 1.12 && g > b * 1.2 && r > 70) gold++;
            if (g > r * 1.5 && b > r * 1.4 && g > 55) teal++;
            if (r + g + b > 100) {
              if (first < 0) first = x;
              last = x;
              left = Math.min(left, x); right = Math.max(right, x);
              top = Math.min(top, y); bottom = Math.max(bottom, y);
            }
          }
          // An open face leaves background inside the silhouette, even with bright edges.
          for (let x = first + 2; first >= 0 && x < last - 2; x++) {
            const at = (y * canvas.width + x) * 4;
            if (bytes[at] + bytes[at + 1] + bytes[at + 2] < 85) holes++;
          }
        }
        return { gold, teal, holes, left, right, top, bottom, width: canvas.width, height: canvas.height, bytes };
      }
      const selected = pixels();
      document.getElementById("lab").goTo(1);
      const unselected = pixels();
      let changedFill = 0;
      for (let at = 0; at < selected.bytes.length; at += 4) {
        // Compare the teal face interiors, excluding antialiased edges.
        if (selected.bytes[at + 1] > selected.bytes[at] * 1.5 && selected.bytes[at + 2] > selected.bytes[at] * 1.4) {
          if (Math.abs(selected.bytes[at] - unselected.bytes[at]) > 2 ||
              Math.abs(selected.bytes[at + 1] - unselected.bytes[at + 1]) > 2) changedFill++;
        }
      }
      document.getElementById("lab").goTo(0);
      const sides = [];
      let yaw = 0.6, pitch = 0.35;
      for (const [nextYaw, nextPitch] of [[0.6, 0.35], [2.2, 0.35], [3.8, 0.35], [5.3, 0.35], [0.6, 1.2], [0.6, -1.2]]) {
        canvas.dispatchEvent(new PointerEvent("pointerdown", { clientX: 0, clientY: 0, pointerId: 1 }));
        canvas.dispatchEvent(new PointerEvent("pointermove", { clientX: (nextYaw - yaw) / 0.01, clientY: (nextPitch - pitch) / 0.01, pointerId: 1 }));
        canvas.dispatchEvent(new PointerEvent("pointercancel", { pointerId: 1 }));
        const { bytes, ...seen } = pixels();
        sides.push(seen);
        yaw = nextYaw; pitch = nextPitch;
      }
      return { selected: { gold: selected.gold, teal: selected.teal }, unselected: { gold: unselected.gold }, changedFill, sides, lost: gl.isContextLost() };
    });
    expect(views.lost).toBe(false);
    expect(views.selected.gold).toBeGreaterThan(50);
    expect(views.selected.teal).toBeGreaterThan(1000);
    expect(views.unselected.gold).toBe(0);
    expect(views.changedFill).toBeLessThan(views.selected.teal * 0.03); // Allow only antialiased edge pixels.
    for (const side of views.sides) {
      expect(side.teal).toBeGreaterThan(1000);
      expect(side.holes).toBeLessThan(10);
      expect(side.left).toBeGreaterThan(0);
      expect(side.right).toBeLessThan(side.width - 1);
      expect(side.top).toBeGreaterThan(0);
      expect(side.bottom).toBeLessThan(side.height - 1);
    }
  });

  test("clicking a visible cube picks its Z slice and blank stage does not", async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.goto("/viewer.html");
    await viewerReady(page);
    await page.evaluate(() => window.threeMd.set("---\n3md: 1.0\naxis: space\n---\n@plane z=0\n```\n...\n...\n...\n```\n@plane z=1\n```\n...\n.#.\n...\n```\n@plane z=2\n```\n...\n...\n...\n```\n"));
    const box = await page.locator("#cubeCanvas").boundingBox();
    await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
    expect(await page.evaluate(() => document.getElementById("lab").currentIndex)).toBe(1);
    await page.click("#outline .ochip:first-child");
    await page.mouse.click(box.x + 5, box.y + 5);
    expect(await page.evaluate(() => document.getElementById("lab").currentIndex)).toBe(0);
  });

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
    await showEditor(page);
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
    await showEditor(page);
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
    await showEditor(page);
    await page.evaluate(() => {
      window.threeMd.set("---\n3md: 1.0\naxis: time\ntitle: Monday\n---\n@plane z=0\nSee [[z=1|Tuesday]]\n");
    });
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
    await showEditor(page);
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
    await page.click("#previewTab");
    await page.waitForFunction(() => document.querySelectorAll("#outline .ochip").length >= 2);
    await page.click("#outline .ochip:nth-child(2)");
    await page.waitForTimeout(200);
    const idx = await page.evaluate(() => document.getElementById("lab").currentIndex);
    expect(idx).toBe(1);
  });

  test("the highlight backdrop scrolls with the textarea (tall document)", async ({ page }) => {
    await page.goto("/viewer.html");
    await page.waitForFunction(() => document.getElementById("lab")?.shadowRoot?.querySelectorAll(".plane").length > 0);
    await showEditor(page);
    const r = await page.evaluate(async () => {
      const ed = document.getElementById("editor"), hl = document.getElementById("hl");
      ed.focus(); ed.select();
      document.execCommand("insertText", false, Array.from({ length: 200 }, (_, i) => "line " + i).join("\n"));
      ed.scrollTop = 1500; ed.dispatchEvent(new Event("scroll"));
      await new Promise((res) => requestAnimationFrame(() => requestAnimationFrame(res)));
      const m = new DOMMatrix(getComputedStyle(hl).transform);
      return { ty: Math.round(m.f), scrollTop: ed.scrollTop };
    });
    // The highlight layer is translated up by the scroll amount (no-op scrollTop is gone).
    expect(r.ty).toBe(-r.scrollTop);
  });

  test("smart-key edits are undoable and never corrupt the buffer", async ({ page }) => {
    await page.goto("/viewer.html");
    await page.waitForFunction(() => document.getElementById("lab")?.shadowRoot?.querySelectorAll(".plane").length > 0);
    await showEditor(page);
    const starter = await page.evaluate(() => document.getElementById("editor").value);
    await page.click("#editor");
    await page.evaluate(() => { const ed = document.getElementById("editor"); ed.setSelectionRange(ed.value.length, ed.value.length); });
    await page.keyboard.type("\nZZZ");
    await page.evaluate(() => { const ed = document.getElementById("editor"); const p = ed.value.indexOf("ZZZ"); ed.setSelectionRange(p, p); });
    await page.keyboard.press("Tab");
    await page.waitForTimeout(40);
    const afterTab = await page.evaluate(() => document.getElementById("editor").value);
    expect(afterTab).toContain("  ZZZ"); // Tab indented
    await page.keyboard.press(process.platform === "darwin" ? "Meta+z" : "Control+z");
    await page.waitForTimeout(40);
    const afterUndo = await page.evaluate(() => document.getElementById("editor").value);
    // Undo must land on a clean prior state, never a merged/duplicated buffer.
    const cleanStates = [starter, starter + "\nZZZ", starter + "\n  ZZZ"];
    expect(cleanStates).toContain(afterUndo);
  });

  test("validity state is machine-readable via data attributes", async ({ page }) => {
    await page.goto("/viewer.html");
    await page.waitForFunction(() => document.getElementById("lab")?.shadowRoot?.querySelectorAll(".plane").length > 0);
    const ok = await page.evaluate(() => ({
      valid: document.getElementById("validBadge").dataset.valid,
      planes: document.getElementById("validBadge").dataset.planes,
      bodyValid: document.body.dataset.threeMdValid,
      live: document.getElementById("status").getAttribute("aria-live"),
    }));
    expect(ok.valid).toBe("true");
    expect(Number(ok.planes)).toBeGreaterThan(0);
    expect(ok.bodyValid).toBe("true");
    expect(ok.live).toBe("polite");
    await showEditor(page);
    await page.fill("#editor", "axis: time\nbroken");
    await page.waitForTimeout(250);
    const bad = await page.evaluate(() => ({
      valid: document.getElementById("validBadge").dataset.valid,
      bodyValid: document.body.dataset.threeMdValid,
      stale: document.getElementById("lab").document, // must be null on error, not stale
    }));
    expect(bad.valid).toBe("false");
    expect(bad.bodyValid).toBe("false");
    expect(bad.stale).toBeNull();
  });

  test("Tab does not trap keyboard focus (Esc then Tab leaves the editor)", async ({ page }) => {
    await page.goto("/viewer.html");
    await page.waitForFunction(() => document.getElementById("lab")?.shadowRoot?.querySelectorAll(".plane").length > 0);
    await showEditor(page);
    await page.click("#editor");
    // Plain Tab indents and keeps focus in the editor.
    await page.keyboard.press("Tab");
    expect(await page.evaluate(() => document.activeElement.id)).toBe("editor");
    // Esc arms the escape; the next Tab moves focus OUT of the editor.
    await page.keyboard.press("Escape");
    await page.keyboard.press("Tab");
    expect(await page.evaluate(() => document.activeElement.id)).not.toBe("editor");
  });

  test("agent API validates and reports structured state", async ({ page }) => {
    await page.goto("/viewer.html");
    await page.waitForFunction(() => document.getElementById("lab")?.shadowRoot?.querySelectorAll(".plane").length > 0);
    const r = await page.evaluate(() => {
      const good = window.threeMd.set('---\n3md: 1.0\naxis: space\n---\n@plane z=0\nA\n@plane z=1\nB\n');
      const bad = window.threeMd.validate('axis: time\nno version key');
      return { good, bad };
    });
    expect(r.good).toMatchObject({ valid: true, axis: "space", planes: 2 });
    expect(r.bad.valid).toBe(false);
    expect(r.bad.message).toBeTruthy();
  });

  test("validate(src) is side-effect-free and reports the error code", async ({ page }) => {
    await page.goto("/viewer.html");
    await page.waitForFunction(() => document.getElementById("lab")?.shadowRoot?.querySelectorAll(".plane").length > 0);
    const r = await page.evaluate(() => {
      const liveBefore = window.threeMd.validate(); // current editor doc
      const bad = window.threeMd.validate("axis: time\nno version");
      const liveAfter = window.threeMd.validate(); // must be unchanged by the probe
      return { liveBefore, bad, liveAfter, badgeValid: document.getElementById("validBadge").dataset.valid };
    });
    expect(r.liveBefore.valid).toBe(true);
    expect(r.bad.valid).toBe(false);
    expect(r.bad.errorCode).toBeTruthy(); // stable code, not just prose
    expect(r.liveAfter.valid).toBe(true); // probe did not poison live state
    expect(r.badgeValid).toBe("true");
  });

  test("repository search opens the 24-generation Conway document", async ({ page }) => {
    await page.goto("/viewer.html");
    await viewerReady(page);
    await page.waitForFunction(() => window.threeMdCatalogCount > 200);
    await page.fill("#findExample", "game-of-life.3md");
    await page.locator("#findList button", { hasText: "· game-of-life.3md" }).click();
    await page.waitForTimeout(400);
    const info = await page.evaluate(() => ({
      planes: document.getElementById("lab").document.planes.length,
      title: document.getElementById("lab").document.title,
    }));
    expect(info.planes).toBe(24);
    expect(info.title).toContain("Conway");
  });

  test("kind 2 canopy opens as text in the element", async ({ page }) => {
    await page.goto("/viewer.html");
    await viewerReady(page);
    await page.waitForFunction(() => window.threeMdCatalogCount > 200);
    await page.fill("#findExample", "canopy.structured.3mdb");
    await page.locator("#findList button", { hasText: "canopy.structured.3mdb" }).click();
    await page.waitForTimeout(400);
    const info = await page.evaluate(() => ({
      title: document.getElementById("lab").document.title,
      status: document.getElementById("status").textContent,
      planes: document.getElementById("lab").document.planes.length,
    }));
    expect(info.title).toBe("Reusable canopy");
    expect(info.planes).toBe(2);
    expect(info.status).toContain("kind 2");
  });

  test("linked village search resolves the folder", async ({ page }) => {
    await page.goto("/viewer.html");
    await viewerReady(page);
    await page.waitForFunction(() => window.threeMdCatalogCount > 200);
    await page.fill("#findExample", "folder · LinkedVillage");
    await page.locator("#findList button", { hasText: "folder · LinkedVillage" }).click();
    await page.waitForTimeout(400);
    const title = await page.evaluate(() => document.getElementById("lab").document.title);
    expect(title).toBe("Linked village");
    const labels = await page.locator("#piece option").allTextContents();
    expect(labels.some((label) => label.endsWith("models/house.3md"))).toBe(true);
    expect(labels.some((label) => label.endsWith("models/tree.3md"))).toBe(true);
  });

  test("a composition profile shows the root and can switch entries", async ({ page }) => {
    await page.goto("/viewer.html");
    await viewerReady(page);
    await page.waitForFunction(() => window.threeMdCatalogCount > 200);
    await page.fill("#findExample", "Extensions/shared-grove.3md");
    await page.locator("#findList button", { hasText: "layer · Extensions/shared-grove.3md" }).click();
    await page.waitForTimeout(400);
    const root = await page.evaluate(() => document.getElementById("lab").document.title);
    expect(root).toBe("Shared grove");
    await page.selectOption("#piece", "canopy");
    await page.waitForTimeout(200);
    const canopy = await page.evaluate(() => document.getElementById("lab").document.title);
    expect(canopy).toBe("Reusable canopy");
  });

  test("markdown headings become planes and a plane search opens one", async ({ page }) => {
    await page.goto("/viewer.html");
    await viewerReady(page);
    await showEditor(page);
    await page.fill("#editor", "# Project\n\nThe opening.\n\n## Install\n\nRun bun.\n");
    await page.click("#documentMenu summary");
    await page.click("#sectionsBtn");
    await page.waitForTimeout(400);
    const labels = await page.evaluate(() => document.getElementById("lab").document.planes.map((plane) => plane.label));
    expect(labels).toEqual(["Project", "Install"]);
    await page.fill("#findExample", "Install");
    await page.locator("#findList button", { hasText: "plane · z=1" }).click();
    await page.waitForTimeout(200);
    const index = await page.evaluate(() => document.getElementById("lab").currentIndex);
    expect(index).toBe(1);
  });

  test("desktop layout keeps files beside a panel that switches Edit and Preview", async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await page.goto("/viewer.html");
    await viewerReady(page);
    const vis = await page.evaluate(() => ({
      files: getComputedStyle(document.querySelector(".filesPane")).display,
      editor: getComputedStyle(document.querySelector(".editor")).display,
      viewer: getComputedStyle(document.querySelector(".viewer")).display,
      editmeta: getComputedStyle(document.querySelector(".editmeta")).display,
      previewmeta: getComputedStyle(document.querySelector(".previewmeta")).display,
      fileswitch: getComputedStyle(document.querySelector(".fileswitch")).display,
      cubes: getComputedStyle(document.querySelector(".cubes")).display,
      show: document.getElementById("stage").dataset.show,
      point: document.getElementById("pointInput").getAttribute("aria-label"),
    }));
    expect(vis.files).not.toBe("none");
    expect(vis.editor).toBe("none");
    expect(vis.viewer).toBe("none");
    expect(vis.cubes).not.toBe("none");
    expect(vis.fileswitch).toBe("none");
    expect(vis.show).toBe("cubes");
    expect(vis.point).toContain("GitHub");
    await page.click("#editTab");
    const editing = await page.evaluate(() => ({
      editor: getComputedStyle(document.querySelector(".editor")).display,
      cubes: getComputedStyle(document.querySelector(".cubes")).display,
    }));
    expect(editing.editor).not.toBe("none");
    expect(editing.cubes).toBe("none");
    await page.click("#previewTab");
    await page.waitForTimeout(150);
    const preview = await page.evaluate(() => ({
      files: getComputedStyle(document.querySelector(".filesPane")).display,
      editor: getComputedStyle(document.querySelector(".editor")).display,
      viewer: getComputedStyle(document.querySelector(".viewer")).display,
      editmeta: getComputedStyle(document.querySelector(".editmeta")).display,
      previewmeta: getComputedStyle(document.querySelector(".previewmeta")).display,
      planes: document.getElementById("lab").shadowRoot.querySelectorAll(".plane").length,
      show: document.getElementById("stage").dataset.show,
    }));
    expect(preview.files).not.toBe("none");
    expect(preview.editor).toBe("none");
    expect(preview.viewer).not.toBe("none");
    expect(preview.editmeta).toBe("none");
    expect(preview.previewmeta).not.toBe("none");
    expect(preview.planes).toBeGreaterThan(0);
    expect(preview.show).toBe("preview");
    await page.click("#editTab");
    const back = await page.evaluate(() => ({
      editor: getComputedStyle(document.querySelector(".editor")).display,
      viewer: getComputedStyle(document.querySelector(".viewer")).display,
    }));
    expect(back.editor).not.toBe("none");
    expect(back.viewer).toBe("none");
  });

  test("cubes tab draws a fenced grid as translucent cubes", async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await page.goto("/viewer.html");
    await viewerReady(page);
    await showEditor(page);
    const sculpture = [
      "---", "3md: 1.0", "axis: layer", "title: Small sculpture", "---", "",
      "@plane z=0 label=\"floor\"", "```", "####", "####", "####", "####", "```", "",
      "@plane z=1 label=\"top\"", "```", "....", ".##.", ".##.", "....", "```", "",
    ].join("\n");
    await page.fill("#editor", sculpture);
    await page.waitForTimeout(300);
    await page.click("#cubesTab");
    await page.waitForTimeout(200);
    const view = await page.evaluate(() => ({
      show: document.getElementById("stage").dataset.show,
      editor: getComputedStyle(document.querySelector(".editor")).display,
      viewer: getComputedStyle(document.querySelector(".viewer")).display,
      cubes: getComputedStyle(document.querySelector(".cubes")).display,
      count: Number(document.getElementById("cubeCanvas").dataset.cubes),
      renderer: document.getElementById("cubeCanvas").dataset.renderer,
      bar: document.getElementById("ideDoc").textContent,
    }));
    expect(view.show).toBe("cubes");
    expect(view.editor).toBe("none");
    expect(view.viewer).toBe("none");
    expect(view.cubes).not.toBe("none");
    expect(view.count).toBeGreaterThan(8);
    expect(view.renderer).toBe("webgl2");
    expect(view.bar).toContain("layer");
  });

  test("orbiting about 1400 gpu cubes stays interactive", async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await page.goto("/viewer.html");
    await viewerReady(page);
    const row = "####################";
    const grid = Array.from({ length: 20 }, () => row).join("\n");
    const planes = [0, 1, 2, 3].map((z) => `@plane z=${z}\n\`\`\`\n${grid}\n\`\`\``).join("\n\n");
    const doc = `---\n3md: 1.0\naxis: layer\n---\n\n${planes}\n`;
    await page.evaluate((source) => window.threeMd.set(source), doc);
    await page.click("#cubesTab");
    await page.waitForFunction(() => document.getElementById("cubeCanvas").dataset.renderer === "webgl2");
    const timed = await page.evaluate(() => {
      const canvas = document.getElementById("cubeCanvas");
      const gl = canvas.__cubeGl;
      let uploads = 0, draws = 0;
      const upload = gl.bufferSubData.bind(gl), draw = gl.drawArraysInstanced.bind(gl);
      gl.bufferSubData = (...args) => { uploads++; return upload(...args); };
      gl.drawArraysInstanced = (...args) => { draws++; return draw(...args); };
      const start = performance.now();
      for (let i = 0; i < 20; i++) {
        canvas.dispatchEvent(new PointerEvent("pointerdown", { clientX: 400, clientY: 300, pointerId: 1, bubbles: true }));
        canvas.dispatchEvent(new PointerEvent("pointermove", { clientX: 400 + i * 6, clientY: 300 + i, pointerId: 1, bubbles: true }));
        canvas.dispatchEvent(new PointerEvent("pointerup", { clientX: 460, clientY: 320, pointerId: 1, bubbles: true }));
      }
      canvas.dispatchEvent(new WheelEvent("wheel", { deltaY: -20, cancelable: true }));
      document.getElementById("lab").goTo(2);
      const ms = performance.now() - start;
      gl.bufferSubData = upload;
      gl.drawArraysInstanced = draw;
      return {
        uploads, draws,
        lost: gl.isContextLost(),
        ms,
        count: Number(canvas.dataset.cubes),
        renderer: canvas.dataset.renderer,
      };
    });
    expect(timed.renderer).toBe("webgl2");
    expect(timed.count).toBeGreaterThan(1400);
    expect(timed.ms).toBeLessThan(800);
    expect(timed.uploads).toBe(0);
    expect(timed.draws).toBe(22); // One draw per pointer update, zoom, or selection.
    expect(timed.lost).toBe(false);
  });

  test("narrow layout switches Files and the document, and Edit and Preview still switch", async ({ page }) => {
    await page.setViewportSize({ width: 800, height: 760 });
    await page.goto("/viewer.html");
    await page.waitForFunction(() => document.getElementById("lab")?.shadowRoot !== undefined);
    const start = await page.evaluate(() => ({
      fileswitch: getComputedStyle(document.querySelector(".fileswitch")).display,
      files: getComputedStyle(document.querySelector(".filesPane")).display,
      stage: getComputedStyle(document.querySelector(".stage")).display,
      editor: getComputedStyle(document.querySelector(".editor")).display,
      viewer: getComputedStyle(document.querySelector(".viewer")).display,
    }));
    expect(start.fileswitch).not.toBe("none");
    expect(start.files).toBe("none");
    expect(start.stage).not.toBe("none");
    expect(start.editor).toBe("none");
    expect(start.viewer).toBe("none");
    await page.click("#editTab");
    const editing = await page.evaluate(() => getComputedStyle(document.querySelector(".editor")).display);
    expect(editing).not.toBe("none");
    await page.click("#previewTab");
    await page.waitForTimeout(150);
    const preview = await page.evaluate(() => ({
      viewer: getComputedStyle(document.querySelector(".viewer")).display,
      editor: getComputedStyle(document.querySelector(".editor")).display,
    }));
    expect(preview.viewer).not.toBe("none");
    expect(preview.editor).toBe("none");
    await page.click('.fileswitch .pstab[data-pane="files"]');
    const files = await page.evaluate(() => ({
      stage: getComputedStyle(document.querySelector(".stage")).display,
      files: getComputedStyle(document.querySelector(".filesPane")).display,
    }));
    expect(files.stage).toBe("none");
    expect(files.files).not.toBe("none");
  });

  test("an empty document reads as a neutral prompt, not a red error", async ({ page }) => {
    await page.goto("/viewer.html");
    await page.waitForFunction(() => document.getElementById("lab")?.shadowRoot?.querySelectorAll(".plane").length > 0);
    await showEditor(page);
    await page.fill("#editor", "");
    await page.waitForTimeout(250);
    const r = await page.evaluate(() => ({
      badgeClass: document.getElementById("validBadge").className,
      empty: document.getElementById("validBadge").dataset.empty,
      statusClass: document.getElementById("status").className,
      errlines: document.querySelectorAll("#hl .line.errline").length,
    }));
    expect(r.badgeClass).not.toContain("err"); // neutral, not red
    expect(r.empty).toBe("true");
    expect(r.statusClass).not.toContain("err");
    expect(r.errlines).toBe(0); // no hard-error band
  });

  test("axis lint warns on a TYPO but not on a valid free-string semantic axis", async ({ page }) => {
    await page.goto("/viewer.html");
    await page.waitForFunction(() => document.getElementById("lab")?.shadowRoot?.querySelectorAll(".plane").length > 0);
    // A typo of a real mode ("stak" -> "stack") should warn with a suggestion.
    const typo = await page.evaluate(() => {
      const snap = window.threeMd.set('---\n3md: 1.0\naxis: stak\n---\n@plane z=0\nA\n');
      return { snap, typo: document.getElementById("validBadge").dataset.axisTypo, warnings: document.getElementById("validBadge").dataset.warnings, status: document.getElementById("status").textContent };
    });
    expect(typo.snap.axisKnown).toBe(false);
    expect(typo.typo).toBe("stack");
    expect(typo.warnings).toBe("1");
    expect(typo.status.toLowerCase()).toContain("typo");
    // A genuine semantic axis ("status") is valid usage: flagged for agents but NOT warned.
    const semantic = await page.evaluate(() => {
      const snap = window.threeMd.set('---\n3md: 1.0\naxis: status\n---\n@plane z=0\nA\n');
      return { snap, axisKnown: document.getElementById("validBadge").dataset.axisKnown, warnings: document.getElementById("validBadge").dataset.warnings };
    });
    expect(semantic.snap.axisKnown).toBe(false); // exposed for agents
    expect(semantic.snap.mode).toBeTruthy();      // resolved render mode exposed
    expect(semantic.warnings).toBeUndefined();    // but no human warning
    // A known axis is clean.
    const ok = await page.evaluate(() => window.threeMd.set('---\n3md: 1.0\naxis: time\n---\n@plane z=0\nA\n'));
    expect(ok.axisKnown).toBe(true);
    expect(ok.mode).toBe("single");
  });

  test("the page has no render-mode switch and does not autoplay", async ({ page }) => {
    await page.goto("/viewer.html");
    await page.waitForFunction(() => document.getElementById("lab")?.shadowRoot !== undefined);
    const frame = await page.evaluate(() => {
      window.threeMd.set('---\n3md: 1.0\naxis: frame\n---\n@plane z=0\nA\n@plane z=1\nB\n');
      const lab = document.getElementById("lab");
      return {
        modeSwitch: document.getElementById("modeSel"),
        play: document.getElementById("playBtn"),
        playing: lab.playing,
        mode: lab.mode,
        autoplay: lab.hasAttribute("autoplay"),
      };
    });
    expect(frame.modeSwitch).toBeNull();
    expect(frame.play).toBeNull();
    expect(frame.playing).toBe(false);
    expect(frame.mode).toBe("single");
    expect(frame.autoplay).toBe(false);
  });

  test("the agent schema lists error codes and the axis-to-mode map", async ({ page }) => {
    await page.goto("/viewer.html");
    const s = await page.evaluate(() => JSON.parse(document.getElementById("threemd-schema").textContent));
    expect(Array.isArray(s.errorCodes)).toBe(true);
    expect(s.errorCodes).toContain("duplicatePlane");
    expect(s.axisModes.time).toBe("stack");
    expect(s.axisModes.frame).toBe("play");
    expect(s.agentApi).toBeTruthy();
  });

  test("dangling cross-plane links are flagged as a non-fatal warning", async ({ page }) => {
    await page.goto("/viewer.html");
    await page.waitForFunction(() => document.getElementById("lab")?.shadowRoot?.querySelectorAll(".plane").length > 0);
    await showEditor(page);
    await page.fill("#editor", '---\n3md: 1.0\naxis: depth\n---\n@plane z=0\nSee [[z=9|nope]]\n@plane z=1\nB\n');
    await page.waitForTimeout(250);
    const ds = await page.evaluate(() => ({ ...document.getElementById("validBadge").dataset }));
    expect(ds.valid).toBe("true"); // still valid, just warned
    expect(ds.warnings).toBe("1");
  });

  test("a corrupt share hash signals a decode error (not a silent starter)", async ({ page }) => {
    await page.goto("/viewer.html#not%20valid%20base64!!!");
    await page.waitForFunction(() => document.getElementById("lab")?.shadowRoot !== undefined);
    await page.waitForTimeout(250);
    const r = await page.evaluate(() => ({ loadError: document.body.dataset.loadError, status: document.getElementById("status").textContent }));
    expect(r.loadError).toBe("true");
    expect(r.status.toLowerCase()).toContain("could not");
  });

  test("the embedded agent schema marks axis optional, only 3md required", async ({ page }) => {
    await page.goto("/viewer.html");
    const schema = await page.evaluate(() => JSON.parse(document.getElementById("threemd-schema").textContent));
    expect(Object.keys(schema.frontmatter.required)).toEqual(["3md"]);
    expect(schema.frontmatter.optional.axis).toBeTruthy();
  });

  test("invalid doc clears stale plane/axis data on the badge", async ({ page }) => {
    await page.goto("/viewer.html");
    await page.waitForFunction(() => document.getElementById("lab")?.shadowRoot?.querySelectorAll(".plane").length > 0);
    // start valid (badge has data-planes), then break it
    await showEditor(page);
    await page.fill("#editor", "axis: time\nbroken no version");
    await page.waitForTimeout(250);
    const ds = await page.evaluate(() => ({ ...document.getElementById("validBadge").dataset }));
    expect(ds.valid).toBe("false");
    expect(ds.planes).toBeUndefined();
    expect(ds.axis).toBeUndefined();
  });

  test("an invalid document flags the offending line and the badge", async ({ page }) => {
    await page.goto("/viewer.html");
    await viewerReady(page);
    await showEditor(page);
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

  test("camera buttons and keyboard orbit, zoom, and fit without changing the document", async ({ page }) => {
    await page.goto("/viewer.html");
    await viewerReady(page);
    await page.waitForFunction(() => document.getElementById("cubeCanvas").dataset.renderer === "webgl2");
    const source = await page.evaluate(() => window.threeMd.source);
    const matrix = () => page.evaluate(() => {
      const gl = document.getElementById("cubeCanvas").__cubeGl;
      const program = gl.getParameter(gl.CURRENT_PROGRAM);
      const mvp = gl.getUniform(program, gl.getUniformLocation(program, "uMvp"));
      // Camera direction is independent of layout shifts while the web font loads.
      return [mvp[3], mvp[7], mvp[11]];
    });
    const initial = await matrix();
    await page.locator("#cubeCanvas").press("ArrowRight");
    expect(await matrix()).not.toEqual(initial);
    await page.getByRole("button", { name: "Zoom in", exact: true }).click();
    await expect(page.locator("#cubeZoom")).toHaveText("115%");
    await page.locator("#cubeCanvas").press("-");
    await expect(page.locator("#cubeZoom")).toHaveText("100%");
    await page.locator("#cubeCanvas").press("Home");
    expect(await matrix()).toEqual(initial);
    for (let i = 0; i < 12; i++) await page.locator("#cubeCanvas").press("+");
    await expect(page.locator("#cubeZoom")).toHaveText("200%");
    await expect(page.locator("#cubeZoomIn")).toBeDisabled();
    await page.getByRole("button", { name: "Fit", exact: true }).click();
    expect(await matrix()).toEqual(initial);
    expect(await page.evaluate(() => window.threeMd.source)).toBe(source);
  });

  test("full camera turns cross both poles continuously and retain geometry", async ({ page }) => {
    await page.goto("/viewer.html");
    await viewerReady(page);
    await page.waitForFunction(() => document.getElementById("cubeCanvas").dataset.renderer === "webgl2");
    await page.evaluate(() => {
      const canvas = document.getElementById("cubeCanvas");
      const gl = canvas.__cubeGl;
      canvas.__uploads = 0;
      const upload = gl.bufferSubData.bind(gl);
      gl.bufferSubData = (...args) => { canvas.__uploads++; return upload(...args); };
    });
    const source = await page.evaluate(() => window.threeMd.source);
    // Pointer delivery uses the real event handler, including capture cancellation.
    const drag = async (dx, dy) => page.dispatchEvent("#cubeCanvas", "pointerdown", {
      pointerId: 91, pointerType: "mouse", button: 0, clientX: 150, clientY: 150,
    }).then(() => page.dispatchEvent("#cubeCanvas", "pointermove", {
      pointerId: 91, pointerType: "mouse", buttons: 1, clientX: 150 + dx, clientY: 150 + dy,
    })).then(() => page.dispatchEvent("#cubeCanvas", "pointerup", {
      pointerId: 91, pointerType: "mouse", button: 0, clientX: 150 + dx, clientY: 150 + dy,
    }));
    const matrix = () => page.evaluate(() => {
      const gl = document.getElementById("cubeCanvas").__cubeGl;
      const matrix = gl.getUniform(gl.getParameter(gl.CURRENT_PROGRAM),
        gl.getUniformLocation(gl.getParameter(gl.CURRENT_PROGRAM), "uMvp"));
      return [0, 1, 3].flatMap(row => {
        const vector = [matrix[row], matrix[row + 4], matrix[row + 8]];
        const length = Math.hypot(...vector);
        return vector.map(value => value / length);
      });
    });
    const initial = await matrix();
    await drag(0, 2 * Math.PI / 0.008);
    const full = await matrix();
    full.forEach((value, i) => expect(value).toBeCloseTo(initial[i], 4));
    await drag(2 * Math.PI / 0.008, 0);
    const both = await matrix();
    both.forEach((value, i) => expect(value).toBeCloseTo(initial[i], 4));
    await drag(0, (Math.PI / 2 - 0.35 - 0.0001) / 0.008);
    const before = await matrix();
    await drag(0, 0.0002 / 0.008);
    const after = await matrix();
    expect(after.every(Number.isFinite)).toBe(true);
    expect(Math.max(...after.map((v, i) => Math.abs(v - before[i])))).toBeLessThan(0.01);
    await page.locator("#cubeCanvas").press("Home");
    expect(await page.evaluate(() => document.getElementById("cubeCanvas").__uploads)).toBe(0);
    expect(await page.evaluate(() => window.threeMd.source)).toBe(source);
  });

  test("pan tools and modified dragging move only the camera and Fit recenters", async ({ page }) => {
    await page.goto("/viewer.html");
    await viewerReady(page);
    await page.waitForFunction(() => document.getElementById("cubeCanvas").dataset.renderer === "webgl2");
    const source = await page.evaluate(() => window.threeMd.source);
    await page.locator("#outline button").nth(1).click();
    const state = () => page.evaluate(() => ({ ...document.getElementById("cubeCanvas").dataset,
      slice: document.getElementById("lab").currentIndex }));
    const initial = await state();
    for (const input of [{ button: 0, shiftKey: true }, { button: 1 }, { button: 2 }]) {
      await page.dispatchEvent("#cubeCanvas", "pointerdown", { pointerId: 92, pointerType: "mouse", clientX: 100, clientY: 100, ...input });
      await page.dispatchEvent("#cubeCanvas", "pointermove", { pointerId: 92, pointerType: "mouse", clientX: 135, clientY: 125 });
      await page.dispatchEvent("#cubeCanvas", "pointerup", { pointerId: 92, pointerType: "mouse", clientX: 135, clientY: 125, ...input });
      const current = await state();
      expect(current.yaw).toBe(initial.yaw);
      expect(current.pitch).toBe(initial.pitch);
      expect(current.slice).toBe(initial.slice);
      expect(Number(current.panX)).toBeLessThan(0);
      expect(Number(current.panY)).toBeGreaterThan(0);
      await page.locator("#cubeCanvas").press("Home");
    }
    await page.getByRole("button", { name: "Pan", exact: true }).click();
    await expect(page.locator("#cubeCanvas")).toHaveAttribute("data-tool", "pan");
    await page.locator("#cubeCanvas").press("Shift+ArrowRight");
    expect(Number((await state()).panX)).toBeLessThan(0);
    await page.locator("#cubeCanvas").press("Home");
    expect(Number((await state()).panX)).toBe(0);
    expect(Number((await state()).panY)).toBe(0);
    expect(await page.evaluate(() => window.threeMd.source)).toBe(source);
  });

  test("two fingers pan and pinch and a cancelled gesture cannot select a slice", async ({ page }) => {
    await page.goto("/viewer.html");
    await viewerReady(page);
    await page.waitForFunction(() => document.getElementById("cubeCanvas").dataset.renderer === "webgl2");
    const state = () => page.evaluate(() => ({ ...document.getElementById("cubeCanvas").dataset,
      slice: document.getElementById("lab").currentIndex, zoom: document.getElementById("cubeZoom").textContent }));
    const initial = await state();
    for (const [pointerId, clientX] of [[101, 100], [102, 200]]) {
      await page.dispatchEvent("#cubeCanvas", "pointerdown", { pointerId, clientX, clientY: 150, pointerType: "touch", button: 0 });
    }
    await page.dispatchEvent("#cubeCanvas", "pointermove", { pointerId: 102, clientX: 250, clientY: 180, pointerType: "touch" });
    const moved = await state();
    expect(moved.zoom).not.toBe(initial.zoom);
    expect(moved.panX).not.toBe(initial.panX);
    expect(moved.yaw).toBe(initial.yaw);
    expect(moved.pitch).toBe(initial.pitch);
    await page.dispatchEvent("#cubeCanvas", "pointercancel", { pointerId: 102, pointerType: "touch" });
    await page.dispatchEvent("#cubeCanvas", "pointerup", { pointerId: 101, clientX: 100, clientY: 150, pointerType: "touch" });
    expect((await state()).slice).toBe(initial.slice);
    await page.locator("#cubeCanvas").press("Home");
    await expect(page.locator("#cubeZoom")).toHaveText("100%");
  });

  test("browser camera projects and picks the shared native parity fixture", async ({ page }) => {
    const { readFile } = await import("node:fs/promises");
    const fixture = JSON.parse(await readFile(new URL("../docs/evidence/viewer-camera/camera-parity.json", import.meta.url), "utf8"));
    const [w, h, depth] = fixture.dimensions;
    const planes = Array.from({ length: depth }, (_, z) => {
      const rows = Array.from({ length: h }, (_, y) => Array.from({ length: w }, (_, x) =>
        fixture.cells.find(cell => cell.x === x && cell.y === y && cell.z === z)?.glyph || ".").join(""));
      return `@plane z=${z}\n\`\`\`\n${rows.join("\n")}\n\`\`\`\n`;
    }).join("\n");
    await page.goto("/viewer.html");
    await viewerReady(page);
    await showEditor(page);
    await page.fill("#editor", `---\n3md: 1.0\naxis: layer\ntitle: Camera parity\n---\n${planes}`);
    await page.waitForTimeout(220);
    await page.locator("#cubesTab").click();
    await page.evaluate(() => {
      const canvas = document.getElementById("cubeCanvas");
      canvas.style.width = "400px";
      canvas.style.height = "320px";
      canvas.style.flex = "none";
      window.dispatchEvent(new Event("resize"));
    });
    await page.waitForFunction(() => document.getElementById("cubeCanvas").dataset.cubes === "3");
    const drag = async (dx, dy) => {
      await page.dispatchEvent("#cubeCanvas", "pointerdown", { pointerId: 93, pointerType: "mouse", button: 0, clientX: 100, clientY: 100 });
      await page.dispatchEvent("#cubeCanvas", "pointermove", { pointerId: 93, pointerType: "mouse", clientX: 100 + dx, clientY: 100 + dy });
      await page.dispatchEvent("#cubeCanvas", "pointerup", { pointerId: 93, pointerType: "mouse", button: 0, clientX: 100 + dx, clientY: 100 + dy });
    };
    for (const pose of fixture.cases) {
      await page.locator("#cubeFit").click();
      await page.locator("#cubeOrbit").click();
      await drag((0.6 + pose.yaw) / 0.008, (pose.pitch - 0.35) / 0.008);
      await page.dispatchEvent("#cubeCanvas", "wheel", { deltaY: -Math.log(pose.zoom) / 0.002 });
      if (pose.rotations) {
        await page.locator("#cameraPrecision summary").click();
        for (const [axis, degrees] of pose.rotations) {
          await page.locator(`#axisButtons [data-axis="${axis}"]`).click();
          await page.locator("#rotationStep").fill(String(Math.abs(degrees)));
          await page.locator(degrees < 0 ? "#axisMinus" : "#axisPlus").click();
        }
        await page.locator('#axisButtons [data-axis="free"]').click();
        await page.locator("#cameraPrecision summary").click();
      }
      await page.locator("#cubePan").click();
      const pixelsPerCell = pose.scale;
      await drag(-pose.panX * pixelsPerCell, pose.panY * pixelsPerCell);
      const projected = await page.evaluate(cells => {
        const canvas = document.getElementById("cubeCanvas");
        const gl = canvas.__cubeGl;
        const program = gl.getParameter(gl.CURRENT_PROGRAM);
        const m = gl.getUniform(program, gl.getUniformLocation(program, "uMvp"));
        return cells.map(cell => {
          const point = [cell.x - 4, 3 - cell.y, cell.z - 2, 1];
          const clip = [0, 1, 2, 3].map(row => point.reduce((sum, value, column) => sum + value * m[column * 4 + row], 0));
          return [(clip[0] / clip[3] + 1) * 200, (1 - clip[1] / clip[3]) * 160];
        });
      }, fixture.cells);
      for (const [i, coordinates] of projected.entries()) {
        coordinates.forEach((value, axis) => expect(value, pose.name).toBeCloseTo(pose.projected[i][axis], 2));
      }
      await page.locator("#cubeOrbit").click();
      for (const [i, coordinates] of projected.entries()) {
        await page.locator("#cubeCanvas").click({ position: { x: coordinates[0], y: coordinates[1] } });
        expect(await page.evaluate(() => document.getElementById("lab").currentIndex), pose.name).toBe(fixture.cells[i].z);
      }
    }
  });

  test("phone layout leaves room for cubes and keeps controls outside the drawing", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto("/viewer.html");
    await viewerReady(page);
    for (const size of [{ width: 390, height: 844 }, { width: 320, height: 740 }]) {
      await page.setViewportSize(size);
      const geometry = await page.evaluate(() => {
        const canvas = document.getElementById("cubeCanvas").getBoundingClientRect();
        const tools = document.getElementById("cubeTools").getBoundingClientRect();
        return { height: canvas.height, bottom: canvas.bottom, toolsTop: tools.top, toolsBottom: tools.bottom,
          width: document.body.scrollWidth, viewWidth: innerWidth, viewHeight: innerHeight };
      });
      expect(geometry.height).toBeGreaterThan(180);
      expect(geometry.toolsTop).toBeGreaterThanOrEqual(geometry.bottom - 1);
      expect(geometry.toolsBottom).toBeLessThan(geometry.viewHeight);
      expect(geometry.width).toBeLessThanOrEqual(geometry.viewWidth);
      await page.click("#documentMenu summary");
      await expect(page.locator("#kind2Btn")).toBeVisible();
      await page.locator("#documentMenu summary").press("Escape");
    }
  });

  test("Document disclosure dismisses with Escape and both downloads preserve the document", async ({ page }) => {
    await page.goto("/viewer.html");
    await viewerReady(page);
    const original = await page.evaluate(() => window.threeMd.source);
    const originalDoc = await page.evaluate(() => window.threeMd.document);
    await page.locator("#documentMenu summary").press("Enter");
    await expect(page.locator("#dlBtn")).toBeVisible();
    await page.locator("#dlBtn").press("Escape");
    await expect(page.locator("#dlBtn")).toBeHidden();
    await expect(page.locator("#documentMenu summary")).toBeFocused();
    const { readFile } = await import("node:fs/promises");
    for (const [button, filename] of [["#dlBtn", "small-sculpture.3md"], ["#kind2Btn", "small-sculpture.3mdb"]]) {
      await page.click("#documentMenu summary");
      const downloadEvent = page.waitForEvent("download");
      await page.click(button);
      const download = await downloadEvent;
      expect(download.suggestedFilename()).toBe(filename);
      const bytes = await readFile(await download.path());
      const source = button === "#dlBtn" ? bytes.toString("utf8") : await page.evaluate(
        (data) => window.threeMdOpen.openBytes(new Uint8Array(data)).text, Array.from(bytes));
      if (button === "#dlBtn") expect(source).toBe(original);
      else {
        // Binary decoding returns canonical text; compare parsed fields and plane bodies.
        const decoded = await page.evaluate((text) => { window.threeMd.set(text); return window.threeMd.document; }, source);
        expect(decoded).toEqual(originalDoc);
        await page.evaluate((text) => window.threeMd.set(text), original);
      }
      await expect(page.locator("#documentMenu")).not.toHaveAttribute("open", "");
    }
    await showEditor(page);
    await page.locator("#editor").focus();
    const saved = page.waitForEvent("download");
    await page.keyboard.press(process.platform === "darwin" ? "Meta+s" : "Control+s");
    await saved;
    await expect(page.locator("#editor")).toBeFocused();
  });

  test("a prose document offers Preview without replacing its source", async ({ page }) => {
    await page.goto("/viewer.html");
    await viewerReady(page);
    const source = "---\n3md: 1.0\naxis: time\ntitle: Reading notes\n---\n@plane z=0\n# A useful note\nLong-form text is readable here.\n";
    await page.evaluate((value) => window.threeMd.set(value), source);
    await expect(page.locator("#cubesEmpty")).toBeVisible();
    await expect(page.locator("#cubeTools")).toBeHidden();
    await page.click("#cubePreview");
    await expect(page.locator("#stage")).toHaveAttribute("data-show", "preview");
    expect(await page.evaluate(() => window.threeMd.source)).toBe(source);
    await page.locator("#previewTab").press("End");
    await expect(page.locator("#cubesTab")).toBeFocused();
    await page.click("#cubeSample");
    await expect(page.locator("#documentTitle")).toHaveText("Small sculpture");
    await expect(page.locator("#cubesEmpty")).toBeHidden();
    await expect(page.locator("#cubeZoom")).toHaveText("100%");
  });

  test("slice navigation keeps the selected plane in a single scrolling row", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto("/viewer.html");
    await viewerReady(page);
    const planes = Array.from({ length: 30 }, (_, i) => `@plane z=${i} label="Slice ${i}"\n\`\`\`\n#\n\`\`\``).join("\n");
    await page.evaluate((source) => window.threeMd.set(source), `---\n3md: 1.0\naxis: layer\n---\n${planes}`);
    await page.locator("#outline .ochip").first().press("End");
    expect(await page.evaluate(() => document.getElementById("lab").currentIndex)).toBe(29);
    const outline = await page.evaluate(() => {
      const row = document.getElementById("outline"), selected = row.querySelector('[aria-current="true"]');
      const bounds = row.getBoundingClientRect(), chip = selected.getBoundingClientRect();
      return { left: chip.left, right: chip.right, rowLeft: bounds.left, rowRight: bounds.right,
        tabStops: [...row.children].filter((button) => button.tabIndex === 0).length, height: bounds.height };
    });
    expect(outline.left).toBeGreaterThanOrEqual(outline.rowLeft);
    expect(outline.right).toBeLessThanOrEqual(outline.rowRight);
    expect(outline.tabStops).toBe(1);
    expect(outline.height).toBeLessThan(60);
    await page.locator("#outline .ochip").last().press("Home");
    expect(await page.evaluate(() => document.getElementById("lab").currentIndex)).toBe(0);
  });

  test("a GitHub load shows busy state and recovers after a rate limit", async ({ page }) => {
    let release;
    const response = new Promise((resolve) => { release = resolve; });
    await page.route("https://api.github.com/**", async (route) => {
      await response;
      await route.fulfill({ status: 429, contentType: "application/json", body: '{"message":"rate limit"}' });
    });
    await page.goto("/viewer.html");
    await viewerReady(page);
    await page.fill("#pointInput", "CorvidLabs/3md");
    await page.click("#pointForm button");
    await expect(page.locator("#pointForm")).toHaveAttribute("aria-busy", "true");
    await expect(page.locator("#pointForm button")).toBeDisabled();
    release();
    await expect(page.locator("#status")).toContainText(/rate.limit/i);
    await expect(page.locator("#pointForm")).toHaveAttribute("aria-busy", "false");
    await expect(page.locator("#pointForm button")).toBeEnabled();
    await expect(page.locator("#pointInput")).toBeEditable();
  });

  test("GPU unavailability explains how to keep reading in Preview", async ({ page }) => {
    await page.addInitScript(() => {
      const context = HTMLCanvasElement.prototype.getContext;
      HTMLCanvasElement.prototype.getContext = function (type, ...args) {
        return type === "webgl2" ? null : context.call(this, type, ...args);
      };
    });
    await page.goto("/viewer.html");
    await viewerReady(page);
    await expect(page.locator("#cubeEmptyText")).toContainText("WebGL2");
    await expect(page.locator("#cubeSample")).toBeHidden();
    await page.click("#cubePreview");
    await expect(page.locator("#stage")).toHaveAttribute("data-show", "preview");
    expect(await page.evaluate(() => document.getElementById("lab").document.title)).toBe("Small sculpture");
  });

  test("file switches preserve edited, invalid, and empty drafts with caret and slice", async ({ page }) => {
    await page.goto("/viewer.html");
    await viewerReady(page);
    await openCollection(page, { "a.3md": draftDocument("A"), "nested/b.3md": draftDocument("B") });
    await openedFile(page, "a.3md").click();
    await showEditor(page);
    const original = await page.locator("#editor").inputValue();
    const changed = draftDocument("A edited", "Unique draft text");
    await page.fill("#editor", changed);
    await page.evaluate(() => {
      document.getElementById("editor").setSelectionRange(20, 25);
      document.getElementById("lab").goTo(1);
    });
    // Cross the 160ms editor debounce before navigation: refreshing source must
    // retain the chosen slice, including on slower Linux WebKit runners.
    await page.waitForTimeout(220);
    expect(await page.evaluate(() => document.getElementById("lab").currentIndex)).toBe(1);
    await openedFile(page, "b.3md").click();
    await openedFile(page, "a.3md").click();
    await expect(page.locator("#editor")).toHaveValue(changed);
    expect(await page.evaluate(() => {
      const ed = document.getElementById("editor");
      return { start: ed.selectionStart, end: ed.selectionEnd, plane: document.getElementById("lab").currentIndex };
    })).toEqual({ start: 20, end: 25, plane: 1 });
    await expect(page.locator("#draftState")).toBeVisible();
    await expect(openedFile(page, "a.3md")).toHaveAttribute("data-edited", "true");
    await page.click("#documentMenu summary");
    const downloadEvent = page.waitForEvent("download");
    await page.click("#dlBtn");
    const download = await downloadEvent;
    expect(await readFile(await download.path(), "utf8")).toBe(changed);
    await expect(page.locator("#draftState")).toBeVisible();
    for (const draft of ["invalid draft kept verbatim", ""]) {
      await page.fill("#editor", draft);
      await openedFile(page, "b.3md").click();
      await openedFile(page, "a.3md").click();
      await expect(page.locator("#editor")).toHaveValue(draft);
    }
    await page.fill("#editor", original);
    await expect(page.locator("#draftState")).toBeHidden();
    await expect(openedFile(page, "a.3md")).toHaveAttribute("data-edited", "false");
  });

  test("composition entry switches preserve each draft without copying it into another entry", async ({ page }) => {
    await page.goto("/viewer.html");
    await viewerReady(page);
    await page.waitForFunction(() => window.threeMdCatalogCount > 200);
    await page.fill("#findExample", "Extensions/shared-grove.3md");
    await page.locator("#findList button", { hasText: "layer · Extensions/shared-grove.3md" }).click();
    await showEditor(page);
    const rootId = await page.locator("#piece").inputValue();
    const rootSource = await page.locator("#editor").inputValue();
    const changedRoot = rootSource + "\nRoot draft marker\n";
    await page.fill("#editor", changedRoot);
    await page.locator("#piece").focus();
    await page.selectOption("#piece", "canopy");
    await expect(page.locator("#piece")).toBeFocused();
    const canopySource = await page.locator("#editor").inputValue();
    expect(canopySource).not.toContain("Root draft marker");
    const changedCanopy = canopySource + "\nCanopy draft marker\n";
    await page.fill("#editor", changedCanopy);
    await page.selectOption("#piece", rootId);
    await expect(page.locator("#editor")).toHaveValue(changedRoot);
    await page.selectOption("#piece", "canopy");
    await expect(page.locator("#editor")).toHaveValue(changedCanopy);
    await page.click("#cubesTab");
    await expect(page.locator("#draftState")).toBeVisible();
    await expect(page.locator("#sourceName")).toBeVisible();
  });

  test("linked entries and file navigation share the same draft", async ({ page }) => {
    await page.goto("/viewer.html");
    await viewerReady(page);
    const files = {};
    for (const path of ["scene.3md", "models/house.3md", "models/tree.3md", "models/tower.3md"]) {
      files[path] = await readFile(new URL(`../Examples/LinkedVillage/${path}`, import.meta.url), "utf8");
    }
    await openCollection(page, files);
    await showEditor(page);
    const rootId = await page.locator("#piece").inputValue();
    const houseId = await page.locator("#piece option").evaluateAll((options) => options.find((option) => option.textContent.endsWith("models/house.3md")).value);
    await page.selectOption("#piece", houseId);
    const changed = (await page.locator("#editor").inputValue()) + "\nLinked house draft\n";
    await page.fill("#editor", changed);
    await openedFile(page, "house.3md").click();
    await expect(page.locator("#editor")).toHaveValue(changed);
    const revised = changed + "From the file list\n";
    await page.fill("#editor", revised);
    await openedFile(page, "scene.3md").click();
    await page.selectOption("#piece", rootId);
    await page.selectOption("#piece", houseId);
    await expect(page.locator("#editor")).toHaveValue(revised);
    await expect(openedFile(page, "house.3md")).toHaveAttribute("data-edited", "true");
  });

  test("search and packing use drafts rather than original file text", async ({ page }) => {
    await page.goto("/viewer.html");
    await viewerReady(page);
    await openCollection(page, { "a.3md": draftDocument("A"), "b.3md": draftDocument("B") });
    await openedFile(page, "a.3md").click();
    await showEditor(page);
    const changed = draftDocument("A", "DraftOnlyNeedle9381");
    await page.fill("#editor", changed);
    await openedFile(page, "b.3md").click();
    await page.fill("#findExample", "DraftOnlyNeedle9381");
    await page.locator("#findList button", { hasText: "DraftOnlyNeedle9381" }).click();
    await expect(page.locator("#editor")).toHaveValue(changed);
    await page.click("#documentMenu summary");
    await page.click("#packBtn");
    expect(await page.locator("#editor").inputValue()).toContain("DraftOnlyNeedle9381");
  });

  test("file filtering, keyboard selection, and phone opens reveal the document", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto("/viewer.html");
    await viewerReady(page);
    await page.getByRole("tab", { name: "Files", exact: true }).click();
    await openCollection(page, { "a.3md": draftDocument("A"), "nested/b.3md": draftDocument("B") });
    await expect(page.locator("#grid")).toHaveAttribute("data-show", "document");
    await page.getByRole("tab", { name: "Files", exact: true }).click();
    await page.fill("#fileFilter", "not-here");
    await expect(page.locator("#fileList")).toContainText("No files match");
    await page.locator("#fileFilter").press("Escape");
    await expect(page.locator("#fileList button")).toHaveCount(2);
    await expect(page.locator("#fileList .file-name")).toHaveText(["a.3md", "b.3md"]);
    await page.locator("#fileFilter").press("ArrowDown");
    await page.keyboard.press("End");
    await expect(openedFile(page, "b.3md")).toBeFocused();
    await page.keyboard.press("Enter");
    await expect(page.locator("#grid")).toHaveAttribute("data-show", "document");
    await expect(page.locator("#sourceName")).toHaveText("b.3md");
    await expect(page.locator("#cubeCanvas")).toBeFocused();
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
    await page.getByRole("tab", { name: "Files", exact: true }).click();
    await page.fill("#findExample", "Second marker");
    await page.locator("#findList button").filter({ hasText: "Second marker" }).first().click();
    await expect(page.locator("#grid")).toHaveAttribute("data-show", "document");
    expect(await page.evaluate(() => document.getElementById("lab").currentIndex)).toBe(1);
  });

  test("a failed local open preserves the collection and current draft", async ({ page }) => {
    await page.goto("/viewer.html");
    await viewerReady(page);
    await openCollection(page, { "a.3md": draftDocument("A"), "b.3md": draftDocument("B") });
    await openedFile(page, "a.3md").click();
    await showEditor(page);
    const changed = draftDocument("A", "Keep after failed open");
    await page.fill("#editor", changed);
    await page.locator("#fileInput").setInputFiles({ name: "broken.3md", mimeType: "text/plain", buffer: Buffer.from("invalid document") });
    await expect(page.locator("#status")).toHaveClass(/err/);
    await page.waitForTimeout(350); // A pending editor render must not clear the open error.
    await expect(page.locator("#status")).toHaveClass(/err/);
    await expect(page.locator("#fileList button")).toHaveCount(2);
    await expect(page.locator("#editor")).toHaveValue(changed);
    await openedFile(page, "b.3md").click();
    await openedFile(page, "a.3md").click();
    await expect(page.locator("#editor")).toHaveValue(changed);
  });

  test("explicit document navigation removes stale source queries and reloads the chosen source", async ({ page }) => {
    const old = draftDocument("Old source");
    await page.route("**/original-document.3md", (route) => route.fulfill({ status: 200, contentType: "text/plain", body: old }));
    await page.goto("/viewer.html?src=original-document.3md&theme=dark");
    await viewerReady(page);
    await expect(page.locator("#documentTitle")).toHaveText("Old source");
    await page.click("#cubeSample");
    expect(new URL(page.url()).searchParams.has("src")).toBe(false);
    expect(new URL(page.url()).searchParams.get("theme")).toBe("dark");
    await page.reload();
    await viewerReady(page);
    await expect(page.locator("#documentTitle")).toHaveText("Small sculpture");
    await openCollection(page, { "a.3md": draftDocument("A"), "b.3md": draftDocument("B") });
    await openedFile(page, "b.3md").click();
    await page.reload();
    await viewerReady(page);
    await expect(page.locator("#documentTitle")).toHaveText("B");
  });

});

const sliceSource = grids => `---\n3md: 1.0\naxis: layer\ntitle: Slice parity\n---\n\n${grids.map((rows,z) => `@plane z=${z} label="Slice ${z+1}"\n\`\`\`\n${rows.join("\n")}\n\`\`\`\n`).join("\n")}`;
async function openSlice(page, source) {
  await page.goto("/viewer.html"); await viewerReady(page);
  await page.evaluate(text => window.threeMd.set(text), source);
  await page.locator("#sliceTab").click();
  await expect(page.locator("#sliceGrid")).toBeVisible();
}
async function sliceStroke(page, points, end = "pointerup") {
  const rect = await page.locator("#sliceGrid").boundingBox();
  const dimensions = await page.locator("#sliceDimensions").textContent();
  const [w,h] = dimensions.match(/\d+/g).map(Number);
  const at = ([x,y]) => ({pointerId:77,pointerType:"mouse",button:0,isPrimary:true,clientX:rect.x+(x+.5)*rect.width/w,clientY:rect.y+(y+.5)*rect.height/h});
  await page.dispatchEvent("#sliceGrid","pointerdown",at(points[0]));
  for (const point of points.slice(1)) await page.dispatchEvent("#sliceGrid","pointermove",at(point));
  await page.dispatchEvent("#sliceGrid",end,at(points.at(-1)));
}

test.describe("Sculpt Slice parity", () => {
  test("shared native strokes, clipped brushes, four-neighbor fill and no-op undo", async ({page}) => {
    const fixture = JSON.parse(await readFile(new URL("../docs/evidence/viewer-slice/slice-parity.json",import.meta.url),"utf8"));
    for (const item of fixture.cases) {
      await openSlice(page,sliceSource(item.initial));
      if(item.z) await page.getByRole("button",{name:`Slice ${item.z+1}`,exact:true}).click();
      await page.locator(`#sliceTool [data-tool="${item.tool}"]`).click();
      if(item.tool!=="erase") await page.getByRole("button",{name:`Paint ${item.glyph}`,exact:true}).click();
      if(item.tool!=="fill") await page.locator(`#sliceSize [data-size="${item.size}"]`).click();
      await sliceStroke(page,item.path);
      expect(await page.evaluate(()=>window.threeMd.source),item.name).toBe(sliceSource(item.expected));
      if(JSON.stringify(item.initial)===JSON.stringify(item.expected)) await expect(page.locator("#sliceUndo")).toBeDisabled();
      else {
        await page.locator("#sliceUndo").click(); expect(await page.evaluate(()=>window.threeMd.source)).toBe(sliceSource(item.initial));
        await expect(page.locator("#sliceUndo")).toBeDisabled(); await page.locator("#sliceRedo").click();
        expect(await page.evaluate(()=>window.threeMd.source)).toBe(sliceSource(item.expected));
      }
    }
  });
  test("grid edits preserve CRLF, labels, prose and downloads exactly",async({page})=>{
    const original=sliceSource([["...","..."],["...","..."]]).replace("@plane z=1", "@plane z=7.5").replace('```\n','Intro **kept**\n```ascii\n')+'\nAfter the grid.\n';
    const raw=original.replace(/\n/g,"\r\n"), expected=raw.replace('...\r\n...','.#.\r\n...');
    await openSlice(page,raw); await sliceStroke(page,[[1,0]],"pointercancel");
    expect(await page.evaluate(()=>window.threeMd.source)).toBe(expected);
    await expect(page.locator("#draftState")).toBeVisible();
    await page.locator("#documentMenu summary").click();
    const download=page.waitForEvent("download"); await page.locator("#dlBtn").click();
    expect(await readFile(await (await download).path(),"utf8")).toBe(expected);
    await page.locator("#documentMenu summary").press("Escape");
    await page.locator("#sliceUndo").click(); expect(await page.evaluate(()=>window.threeMd.source)).toBe(raw);
  });
  test("keyboard cells, grid zoom, previous overlay and shared WebGL reference",async({page})=>{
    await openSlice(page,sliceSource([["#..","..."],["...","..."]]));
    const initial=await page.evaluate(()=>{const c=document.getElementById("cubeCanvas");window.sliceContext=c.getContext("webgl2");return window.threeMd.source;});
    await page.getByRole("button",{name:"Slice 2",exact:true}).click(); await page.locator("#slicePrevious").check();
    expect(await page.evaluate(()=>window.threeMd.source)).toBe(initial);
    await page.locator("#sliceGrid").press("ArrowRight"); await page.locator("#sliceGrid").press("ArrowDown"); await page.locator("#sliceGrid").press("Space");
    expect(await page.evaluate(()=>window.threeMd.source)).toBe(sliceSource([["#..","..."],["...",".#."]]));
    await page.locator('#sliceZoom [data-zoom="4"]').click();
    expect(await page.evaluate(()=>document.getElementById("sliceScroll").scrollWidth > document.getElementById("sliceScroll").clientWidth)).toBe(true);
    await page.locator("#sliceExpand").click(); await expect(page.locator("#cubesPane > #cubeCanvas")).toBeVisible();
    expect(await page.evaluate(()=>document.getElementById("cubeCanvas").getContext("webgl2")===window.sliceContext)).toBe(true);
    expect(await page.evaluate(()=>document.getElementById("lab").currentIndex)).toBe(1);
  });
  test("source typing and Slice share undo and retain it across file navigation",async({page})=>{
    await page.goto("/viewer.html");await viewerReady(page);
    const one=sliceSource([["...","..."]]),two=sliceSource([["@@@","..."]]);
    await openCollection(page,{"one.3md":one,"two.3md":two});await openedFile(page,"one.3md").click();
    await page.locator("#sliceTab").click();await sliceStroke(page,[[0,0]]);
    await openedFile(page,"two.3md").click();await openedFile(page,"one.3md").click();
    expect(await page.evaluate(()=>window.threeMd.source)).toBe(one.replace('...\n...','#..\n...'));
    await showEditor(page);await page.locator("#editor").press("ControlOrMeta+End");await page.locator("#editor").pressSequentially("prose");
    await page.locator("#editor").press("ControlOrMeta+z");expect(await page.evaluate(()=>window.threeMd.source)).toBe(one.replace('...\n...','#..\n...'));
    await page.locator("#editor").press("ControlOrMeta+z");expect(await page.evaluate(()=>window.threeMd.source)).toBe(one);
    await page.locator("#editor").press("ControlOrMeta+Shift+z");expect(await page.evaluate(()=>window.threeMd.source)).toBe(one.replace('...\n...','#..\n...'));
  });
  test("unsupported grids stay readable and budget rejection restores the full stroke",async({page})=>{
    await page.goto("/viewer.html");await viewerReady(page);await page.evaluate(text=>window.threeMd.set(text),sliceSource([["xx","x"]]));await page.locator("#sliceTab").click();
    await expect(page.locator("#sliceUnavailable")).toContainText("rectangular");await expect(page.locator("#sliceWorkspace")).toBeHidden();
    const rows=Array.from({length:64},(_,y)=>y<62?'#'.repeat(64):'.'.repeat(64));
    const original=sliceSource([rows]);await page.evaluate(text=>window.threeMd.set(text),original);
    await page.locator('#sliceSize [data-size="5"]').click();await sliceStroke(page,[[0,63],[63,63]]);
    expect(await page.evaluate(()=>window.threeMd.source)).toBe(original);await expect(page.locator("#sliceUndo")).toBeDisabled();await expect(page.locator("#sliceMessage")).toContainText("restored");
  });
  test("phone Slice tools and axis controls stay usable without horizontal page overflow",async({page})=>{
    await openSlice(page,sliceSource([["...","..."],["...","..."]]));
    for(const size of [{width:390,height:844},{width:320,height:740}]){
      await page.setViewportSize(size);await expect(page.locator("#sliceGrid")).toBeVisible();await sliceStroke(page,[[1,1]]);
      expect(await page.evaluate(()=>document.body.scrollWidth<=innerWidth)).toBe(true);
    }
    await page.locator("#sliceExpand").click();await page.locator('#axisButtons [data-axis="2"]').click();await page.locator("#cameraPrecision summary").click();
    await page.locator("#axisPlus").click();expect(await page.evaluate(()=>document.body.scrollWidth<=innerWidth)).toBe(true);
  });
  test("2D editing works with an unavailable WebGL reference",async({page})=>{
    await page.addInitScript(()=>{const get=HTMLCanvasElement.prototype.getContext;HTMLCanvasElement.prototype.getContext=function(type,...args){return type==='webgl2'?null:get.call(this,type,...args);};});
    await openSlice(page,sliceSource([["...","..."]]));await sliceStroke(page,[[2,1]]);
    expect(await page.evaluate(()=>window.threeMd.source)).toBe(sliceSource([["...","..#"]]));await expect(page.locator("#sliceReferenceNote")).toContainText("WebGL2");
  });
  test("axis inverse, finite inputs, pan steps and Fit leave source and geometry intact",async({page})=>{
    await page.goto("/viewer.html");await viewerReady(page);const source=await page.evaluate(()=>window.threeMd.source);
    await page.locator("#cameraPrecision summary").click();await page.locator('#axisButtons [data-axis="2"]').click();
    await page.locator("#axisPlus").click();const turned=await page.locator("#cubeCanvas").getAttribute("data-rotation");
    expect(JSON.parse(turned)[2]).not.toBe(0);await page.locator("#axisMinus").click();expect(JSON.parse(await page.locator("#cubeCanvas").getAttribute("data-rotation"))[2]).toBeCloseTo(0,12);
    await page.locator("#rotationStep").fill("0");await page.locator("#axisPlus").click();await expect(page.locator("#rotationStep")).toHaveAttribute("aria-invalid","true");
    await page.getByRole("button",{name:"Pan right",exact:true}).click();await expect(page.locator("#cubeCanvas")).toHaveAttribute("data-pan-x","-0.25");
    await page.locator("#panStep").fill("-1");await page.getByRole("button",{name:"Pan right",exact:true}).click();await expect(page.locator("#cubeCanvas")).toHaveAttribute("data-pan-x","-0.25");
    await page.locator("#cubeFit").click();await expect(page.locator("#cubeCanvas")).toHaveAttribute("data-rotation","[0,0,0,1]");await expect(page.locator("#cubeCanvas")).toHaveAttribute("data-pan-x","0");
    expect(await page.evaluate(()=>window.threeMd.source)).toBe(source);
  });
});


test("Slice history drops only old snapshots at the per-draft and collection budgets", async ({page}) => {
  await openSlice(page,sliceSource([["...","..."]]));
  for (let index=0;index<104;index++) {
    await page.locator(`#sliceTool [data-tool="${index%2 ? "erase" : "draw"}"]`).click();
    await page.locator("#sliceGrid").press("Space");
  }
  for(let index=0;index<100;index++) await page.locator("#sliceUndo").click();
  await expect(page.locator("#sliceUndo")).toBeDisabled();
  expect(await page.evaluate(()=>window.threeMd.source)).toBe(sliceSource([["...","..."]]));
  const large=sliceSource([["...","..."]])+"\n"+"a".repeat(800000)+"\n";
  await openCollection(page,{"a.3md":large,"b.3md":large,"c.3md":large,"d.3md":large});
  for(const name of ["a.3md","b.3md","c.3md","d.3md"]){
    await openedFile(page,name).click(); await page.locator("#sliceTab").click();
    await page.locator('#sliceTool [data-tool="draw"]').click(); await page.locator("#sliceGrid").press("Space");
    await page.locator("#sliceGrid").press("ArrowRight"); await page.locator("#sliceGrid").press("Space");
  }
  await openedFile(page,"a.3md").click();await expect(page.locator("#sliceUndo")).toBeDisabled();
  expect((await page.evaluate(()=>window.threeMd.source)).includes("##." )).toBe(true);
  await openedFile(page,"d.3md").click();await page.locator("#sliceUndo").click();await page.locator("#sliceUndo").click();
  expect(await page.evaluate(()=>window.threeMd.source)).toBe(large);
});

test("Slice navigation finishes a touch stroke and ignores its late pointer movement",async({page})=>{
  await page.goto("/viewer.html");await viewerReady(page);
  const source=sliceSource([["...","..."]]);await openCollection(page,{"one.3md":source,"two.3md":source});
  await openedFile(page,"one.3md").click();await page.locator("#sliceTab").click();
  const rect=await page.locator("#sliceGrid").boundingBox();
  await page.dispatchEvent("#sliceGrid","pointerdown",{pointerId:83,pointerType:"touch",isPrimary:true,button:0,clientX:rect.x+rect.width/6,clientY:rect.y+rect.height/4});
  await openedFile(page,"two.3md").click();
  await page.dispatchEvent("#sliceGrid","pointermove",{pointerId:83,pointerType:"touch",clientX:rect.x+rect.width/2,clientY:rect.y+rect.height/4});
  await page.dispatchEvent("#sliceGrid","pointerup",{pointerId:83,pointerType:"touch"});
  expect(await page.evaluate(()=>window.threeMd.source)).toBe(source);
  await openedFile(page,"one.3md").click();expect(await page.evaluate(()=>window.threeMd.source)).toBe(source.replace('...\n...','#..\n...'));
  await page.locator("#sliceUndo").click();expect(await page.evaluate(()=>window.threeMd.source)).toBe(source);
});


for (const density of [1, 2]) {
  test(`shared cube drawable stays sharp through view/viewport changes at ${density}x density`, async ({ browser }) => {
    const context = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: density });
    try {
      const page = await context.newPage();
      await page.addInitScript(() => {
        window.__cubeResolution = { contexts: 0, losses: 0, uploads: 0, allocations: 0 };
        const original = HTMLCanvasElement.prototype.getContext;
        HTMLCanvasElement.prototype.getContext = function(type, ...args) {
          if (this.id === "cubeCanvas" && type === "webgl2") window.__cubeResolution.contexts++;
          return original.call(this, type, ...args);
        };
        document.addEventListener("webglcontextlost", () => window.__cubeResolution.losses++, true);
        const media = window.matchMedia.bind(window);
        window.matchMedia = query => {
          const result = media(query);
          if (query.startsWith("(resolution:")) window.__cubeResolution.display = result;
          return result;
        };
      });
      await page.goto("/viewer.html"); await viewerReady(page);
      await page.waitForFunction(() => document.getElementById("cubeCanvas").dataset.renderer === "webgl2");
      await page.locator("#outline button").nth(1).click();
      await page.locator('#axisButtons [data-axis="2"]').click();
      await page.locator("#cubeCanvas").press("ArrowRight");
      const source = await page.evaluate(() => window.threeMd.source);
      const pose = await page.evaluate(() => {
        const canvas = document.getElementById("cubeCanvas"), gl = canvas.__cubeGl;
        window.__cubeResolution.gl = gl;
        window.__cubeResolution.program = gl.getParameter(gl.CURRENT_PROGRAM);
        const upload = gl.bufferSubData.bind(gl), allocate = gl.bufferData.bind(gl);
        gl.bufferSubData = (...args) => { window.__cubeResolution.uploads++; return upload(...args); };
        gl.bufferData = (...args) => { window.__cubeResolution.allocations++; return allocate(...args); };
        return [canvas.dataset.rotation, canvas.dataset.yaw, canvas.dataset.pitch, canvas.dataset.panX, canvas.dataset.panY];
      });
      const sharp = async () => {
        await expect.poll(() => page.evaluate(() => {
          const canvas = document.getElementById("cubeCanvas"), gl = canvas.__cubeGl;
          let w = Math.max(2, Math.floor(canvas.clientWidth * Math.min(devicePixelRatio, 2)));
          let h = Math.max(2, Math.floor(canvas.clientHeight * Math.min(devicePixelRatio, 2)));
          const limit = Math.min(1, 2048 / w, 2048 / h);
          w = Math.max(2, Math.floor(w * limit)); h = Math.max(2, Math.floor(h * limit));
          return canvas.width === w && canvas.height === h && gl?.drawingBufferWidth === w && gl?.drawingBufferHeight === h;
        })).toBe(true);
        const state = await page.evaluate(() => {
          const canvas = document.getElementById("cubeCanvas"), gl = canvas.__cubeGl, receipt = window.__cubeResolution;
          return { sameContext: gl === receipt.gl, sameProgram: gl?.getParameter(gl.CURRENT_PROGRAM) === receipt.program,
            contexts: receipt.contexts, losses: receipt.losses, uploads: receipt.uploads, allocations: receipt.allocations,
            pose: [canvas.dataset.rotation, canvas.dataset.yaw, canvas.dataset.pitch, canvas.dataset.panX, canvas.dataset.panY] };
        });
        expect(state).toEqual({ sameContext: true, sameProgram: true, contexts: 1, losses: 0, uploads: 0, allocations: 0, pose });
        expect(await page.evaluate(() => window.threeMd.source)).toBe(source);
        await expect(page.locator("#planeLive")).toHaveText("Plane 2 of 3: walls");
      };
      await sharp();
      for (const viewport of [{ width: 1440, height: 1000 }, { width: 3200, height: 2000 }, { width: 390, height: 844 }]) {
        await page.locator("#sliceTab").click(); await sharp();
        await page.setViewportSize(viewport); await sharp();
        await page.locator("#sliceExpand").click(); await sharp();
      }
      for (let i = 0; i < 3; i++) {
        await page.locator("#sliceTab").click(); await sharp();
        await page.locator("#cubesTab").click(); await sharp();
      }
      // A display-density change can leave the CSS size unchanged.
      await page.evaluate(value => {
        Object.defineProperty(window, "devicePixelRatio", { configurable: true, value });
        window.__cubeResolution.display.dispatchEvent(new Event("change"));
      }, density === 1 ? 2 : 1);
      await sharp();
      expect(await page.evaluate(() => window.__cubeResolution.display.media)).toBe(`(resolution: ${density === 1 ? 2 : 1}dppx)`);
      await page.evaluate(value => {
        Object.defineProperty(window, "devicePixelRatio", { configurable: true, value });
        window.dispatchEvent(new Event("resize"));
      }, density);
      await sharp();
    } finally { await context.close(); }
  });
}

test("Slice high zoom bounds its bitmap and paints the scrolled cell exactly", async ({ page }) => {
  const errors = []; page.on("pageerror", error => errors.push(error.message));
  const rows = Array.from({ length: 64 }, () => ".".repeat(64)), source = sliceSource([rows]);
  await openSlice(page, source); await page.locator('#sliceZoom [data-zoom="16"]').click();
  const unit = Number(await page.locator("#sliceGrid").getAttribute("data-cell-size"));
  await page.locator("#sliceScroll").evaluate((scroll, unit) => { scroll.scrollLeft = unit * 20; scroll.scrollTop = unit * 30; }, unit);
  await expect.poll(() => page.locator("#sliceGrid").getAttribute("data-offset-x")).toBe(String(unit * 20));
  await expect.poll(() => page.locator("#sliceGrid").getAttribute("data-offset-y")).toBe(String(unit * 30));
  const size = await page.locator("#sliceGrid").evaluate(canvas => ({
    bitmap: [canvas.width, canvas.height], visible: [canvas.clientWidth, canvas.clientHeight],
    scroll: [document.getElementById("sliceScroll").clientWidth, document.getElementById("sliceScroll").clientHeight],
    surface: [document.getElementById("sliceSurface").clientWidth, document.getElementById("sliceSurface").clientHeight],
  }));
  expect(Math.max(...size.bitmap)).toBeLessThanOrEqual(2048);
  expect(size.visible[0]).toBeLessThanOrEqual(size.scroll[0]); expect(size.visible[1]).toBeLessThanOrEqual(size.scroll[1]);
  expect(size.surface[0]).toBeGreaterThan(size.bitmap[0]);
  const box = await page.locator("#sliceGrid").boundingBox(); await page.mouse.click(box.x + unit / 2, box.y + unit / 2);
  const expected = [...rows]; expected[30] = ".".repeat(20) + "#" + ".".repeat(43);
  expect(await page.evaluate(() => window.threeMd.source)).toBe(sliceSource([expected]));
  await page.locator("#sliceUndo").click(); expect(await page.evaluate(() => window.threeMd.source)).toBe(source);
  await page.locator('#sliceZoom [data-zoom="1"]').click();
  await expect.poll(() => page.locator("#sliceGrid").getAttribute("data-offset-x")).toBe("0"); expect(errors).toEqual([]);
});

test("lost WebGL waits for restoration without resize allocations or retries", async ({ page }) => {
  await page.addInitScript(() => {
    window.__contextCalls = 0; const get = HTMLCanvasElement.prototype.getContext;
    HTMLCanvasElement.prototype.getContext = function(type, ...args) {
      if (this.id === "cubeCanvas" && type === "webgl2") window.__contextCalls++;
      return get.call(this, type, ...args);
    };
  });
  await page.goto("/viewer.html"); await viewerReady(page);
  await expect(page.locator("#cubeCanvas")).toHaveAttribute("data-renderer", "webgl2");
  await page.locator("#cubeCanvas").press("ArrowRight"); await page.locator("#outline button").nth(1).click();
  const pose = await page.locator("#cubeCanvas").evaluate(c => [c.dataset.yaw,c.dataset.pitch,c.dataset.rotation,c.dataset.panX,c.dataset.panY]);
  const source = await page.evaluate(() => window.threeMd.source);
  expect(await page.evaluate(() => {
    window.__lose = document.getElementById("cubeCanvas").__cubeGl.getExtension("WEBGL_lose_context");
    window.__lose?.loseContext(); return Boolean(window.__lose);
  })).toBe(true);
  await expect(page.locator("#cubeCanvas")).toHaveAttribute("data-renderer", "lost");
  const bitmap = await page.locator("#cubeCanvas").evaluate(c => [c.width,c.height]);
  await page.locator("#sliceTab").click(); await page.setViewportSize({width:950,height:720});
  await page.evaluate(() => { const c=document.getElementById("cubeCanvas"); for(let i=0;i<50;i++) c.dispatchEvent(new Event("threemd-cubes")); });
  expect(await page.evaluate(() => window.__contextCalls)).toBe(1);
  expect(await page.locator("#cubeCanvas").evaluate(c => [c.width,c.height])).toEqual(bitmap);
  await expect(page.locator("#sliceReferenceNote")).toContainText("recovery");
  await page.evaluate(() => window.__lose.restoreContext());
  await expect(page.locator("#cubeCanvas")).toHaveAttribute("data-renderer", "webgl2");
  expect(await page.evaluate(() => window.__contextCalls)).toBe(2);
  expect(await page.locator("#cubeCanvas").evaluate(c => [c.dataset.yaw,c.dataset.pitch,c.dataset.rotation,c.dataset.panX,c.dataset.panY])).toEqual(pose);
  expect(await page.evaluate(() => window.threeMd.source)).toBe(source);
  await expect(page.locator("#sliceHeading")).toHaveText("Slice 2 of 3");
  await page.locator("#sliceExpand").click(); await expect(page.locator("#cubeCanvas")).toHaveAttribute("data-renderer", "webgl2");
});

test("viewer opens the entire text catalog in Cubes, Slice and Preview without source loss", async ({ page }) => {
  test.setTimeout(180_000);
  const errors = []; page.on("pageerror", e => errors.push(String(e)));
  page.on("console", m => { if (m.type() === "error") errors.push(m.text()); });
  const examples = JSON.parse(await readFile(new URL("../web/all-examples.json", import.meta.url), "utf8"));
  expect(examples.length).toBeGreaterThan(290);
  await page.goto("/viewer.html"); await viewerReady(page);
  const result = await page.evaluate(async examples => {
    const failures = [], counts = { documents: 0, grids: 0, fallbacks: 0 }, axes = new Set();
    const frame = () => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    for (const ex of examples) {
      const state = window.threeMd.set(ex.src);
      if (!state.valid || !state.planes) { failures.push(`${ex.slug}: ${state.message || "no planes"}`); continue; }
      axes.add(state.axis); counts.documents++;
      for (const view of ["cubes", "slice", "preview"]) {
        document.getElementById(view + "Tab").click(); await frame();
        if (window.threeMd.source !== ex.src) failures.push(`${ex.slug}/${view}: source changed`);
        if (document.getElementById("stage").dataset.show !== view) failures.push(`${ex.slug}/${view}: wrong view`);
        if (view === "cubes") {
          const canvas = document.getElementById("cubeCanvas"), gl = canvas.__cubeGl;
          if (!gl || gl.isContextLost() || gl.getError() !== gl.NO_ERROR) failures.push(`${ex.slug}: GPU error`);
          if (Number(canvas.dataset.cubes) > 4000) failures.push(`${ex.slug}: cube limit exceeded`);
        } else if (view === "slice") {
          if (document.getElementById("sliceWorkspace").hidden) {
            counts.fallbacks++;
            if (!document.getElementById("sliceUnavailable").textContent.trim()) failures.push(`${ex.slug}: unexplained Slice refusal`);
          } else {
            counts.grids++;
            const canvas = document.getElementById("sliceGrid");
            if (Math.max(canvas.width,canvas.height) > 2048) failures.push(`${ex.slug}: oversized Slice bitmap`);
          }
        } else if (!document.getElementById("lab").shadowRoot.querySelector(".plane")) failures.push(`${ex.slug}: missing Preview`);
      }
    }
    return { failures, counts, axes: axes.size };
  }, examples);
  expect(result.failures).toEqual([]); expect(result.counts.documents).toBe(examples.length);
  expect(result.axes).toBeGreaterThan(40); expect(result.counts.grids).toBeGreaterThan(0); expect(result.counts.fallbacks).toBeGreaterThan(0);
  expect(errors).toEqual([]);
  console.log("Full viewer catalog coverage:", JSON.stringify(result));
});

test("local kind 1 and kind 2 binaries retain composition entries through every view", async ({ page }) => {
  const samples = JSON.parse(await readFile(new URL("../web/binary-samples.json", import.meta.url), "utf8"));
  const errors = []; page.on("pageerror", e => errors.push(String(e)));
  await page.goto("/viewer.html"); await viewerReady(page);
  for (const sample of samples) {
    await page.locator("#fileInput").setInputFiles({ name: sample.path.split("/").at(-1), mimeType: "application/octet-stream", buffer: Buffer.from(sample.base64,"base64") });
    await expect(page.locator("#documentTitle")).toHaveText(sample.path.includes("shared-grove") ? "Shared grove" : "Reusable canopy");
    const pieces = await page.locator("#piece option").evaluateAll(options => options.map(o => o.value));
    expect(pieces.sort()).toEqual(sample.path.includes("shared-grove") ? ["canopy","grove"] : []);
    for (const piece of pieces.length ? pieces : [null]) {
      if (piece !== null) await page.locator("#piece").selectOption(piece);
      const source = await page.evaluate(() => window.threeMd.source);
      for (const view of ["cubes","slice","preview"]) {
        await page.locator(`#${view}Tab`).click();
        expect(await page.evaluate(() => window.threeMd.source)).toBe(source);
        expect(await page.evaluate(() => window.threeMd.validate().valid)).toBe(true);
      }
    }
  }
  expect(errors).toEqual([]);
});

test("viewer size boundaries preserve readable source and explain unsupported Slice grids", async ({ page }) => {
  const errors = []; page.on("pageerror", e => errors.push(String(e)));
  await page.goto("/viewer.html"); await viewerReady(page);
  const cases = [
    { name:"single cell", grids:[["#"]], editable:true, cubes:1 },
    { name:"empty grid", grids:[["...","..."]], editable:true, cubes:0 },
    { name:"tall skinny", grids:[Array.from({length:64},()=>"#")], editable:true, cubes:64 },
    { name:"wide skinny", grids:[["#".repeat(64)]], editable:true, cubes:64 },
    { name:"4000 cells", grids:[Array.from({length:64},(_,y)=>y<62 ? "#".repeat(64) : y===62 ? "#".repeat(32)+".".repeat(32) : ".".repeat(64))], editable:true, cubes:4000 },
    { name:"4096 cells", grids:[Array.from({length:64},()=>"#".repeat(64))], editable:false, cubes:4000 },
    { name:"65 columns", grids:[["#".repeat(65)]], editable:false, cubes:0 },
    { name:"65 rows", grids:[Array.from({length:65},()=>"#")], editable:false, cubes:0 },
    { name:"256 planes", grids:Array.from({length:256},()=>["#"]), editable:true, cubes:256 },
    { name:"257 planes", grids:Array.from({length:257},()=>["#"]), editable:false, cubes:257 },
    { name:"large prose", grids:[["#"]], suffix:"\n"+"p".repeat(1.5*1024*1024), editable:false, cubes:1 },
  ];
  for (const viewport of [{width:1440,height:900},{width:390,height:844}]) {
    await page.setViewportSize(viewport);
    for (const item of cases) {
    const source = sliceSource(item.grids)+(item.suffix||"");
    await page.evaluate(source=>window.threeMd.set(source),source);
    await page.locator("#cubesTab").click();
    await expect(page.locator("#cubeCanvas")).toHaveAttribute("data-cubes",String(item.cubes));
    await page.locator("#sliceTab").click();
    if (item.editable) { await expect(page.locator("#sliceWorkspace"),item.name).toBeVisible(); }
    else { await expect(page.locator("#sliceUnavailable"),item.name).toBeVisible(); await expect(page.locator("#sliceUnavailable")).not.toHaveText(""); }
    await page.locator("#previewTab").click(); expect(await page.evaluate(()=>window.threeMd.validate().valid)).toBe(true);
    expect(await page.evaluate(()=>window.threeMd.source),item.name).toBe(source);
  }
    }
  expect(errors).toEqual([]);
});


test("a local linked folder resolves entries and preserves each edited draft", async ({ page }) => {
  const examples = JSON.parse(await readFile(new URL("../web/nested-examples.json", import.meta.url), "utf8"));
  const files = Object.fromEntries(examples.filter(ex => ex.path.startsWith("LinkedVillage/")).map(ex => [ex.path,ex.src]));
  await page.goto("/viewer.html"); await viewerReady(page); await openCollection(page,files);
  await openedFile(page,"scene.3md").click();
  await expect(page.locator("#documentTitle")).toHaveText("Linked village");
  const entries = await page.locator("#piece option").evaluateAll(options=>options.map(o=>o.value));
  expect(entries).toHaveLength(4);
  for (const id of entries) {
    await page.locator("#piece").selectOption(id);
    const original = await page.evaluate(()=>window.threeMd.source);
    await page.locator("#editTab").click(); await page.locator("#editor").fill(original+"\nFolder draft marker");
    await expect(page.locator("#draftState")).toBeVisible();
    await page.locator("#previewTab").click(); expect(await page.evaluate(()=>window.threeMd.validate().valid)).toBe(true);
    await page.locator("#piece").selectOption(entries.find(value=>value!==id));
    await page.locator("#piece").selectOption(id);
    expect(await page.evaluate(()=>window.threeMd.source)).toBe(original+"\nFolder draft marker");
  }
});

for (const startup of ["missing", "already-lost"]) {
  test(`WebGL ${startup} at startup makes one context request across repeated redraws`, async ({ page }) => {
    const errors = [];
    page.on("pageerror", error => errors.push(error.message));
    await page.addInitScript(startup => {
      window.__startupContextCalls = 0;
      const original = HTMLCanvasElement.prototype.getContext;
      HTMLCanvasElement.prototype.getContext = function(type, ...args) {
        if (this.id !== "cubeCanvas" || type !== "webgl2") return original.call(this, type, ...args);
        window.__startupContextCalls++;
        // Drivers may refuse creation or return a lost context before sending any event.
        return startup === "missing" ? null : { isContextLost: () => true };
      };
    }, startup);
    await page.goto("/viewer.html");
    await viewerReady(page);
    const source = await page.evaluate(() => window.threeMd.source);
    await page.evaluate(() => {
      const canvas = document.getElementById("cubeCanvas");
      for (let index = 0; index < 256; index++) canvas.dispatchEvent(new Event("threemd-cubes"));
    });
    await expect(page.locator("#cubeCanvas")).toHaveAttribute("data-renderer", startup === "missing" ? "none" : "lost");
    expect(await page.evaluate(() => window.__startupContextCalls)).toBe(1);
    const bitmap = await page.locator("#cubeCanvas").evaluate(canvas => [canvas.width, canvas.height]);
    await page.locator("#sliceTab").click();
    await page.setViewportSize({ width: 390, height: 844 });
    await page.locator('#sliceZoom [data-zoom="16"]').click();
    await page.locator("#sliceExpand").click();
    expect(await page.evaluate(() => window.__startupContextCalls)).toBe(1);
    expect(await page.locator("#cubeCanvas").evaluate(canvas => [canvas.width, canvas.height])).toEqual(bitmap);
    await page.locator("#previewTab").click();
    expect(await page.evaluate(() => window.threeMd.source)).toBe(source);
    expect(errors).toEqual([]);
  });
}

for (const resource of ["shader", "program", "vertex-array", "mesh-buffer", "instance-buffer"]) {
  test(`WebGL ${resource} allocation failure stops setup without invalid GPU calls`, async ({ page }) => {
    const errors = [];
    page.on("pageerror", error => errors.push(error.message));
    page.on("console", message => { if (message.type() === "error") errors.push(message.text()); });
    await page.addInitScript(resource => {
      window.__allocationContextCalls = 0;
      const original = HTMLCanvasElement.prototype.getContext;
      HTMLCanvasElement.prototype.getContext = function(type, ...args) {
        const context = original.call(this, type, ...args);
        if (this.id !== "cubeCanvas" || type !== "webgl2" || !context) return context;
        window.__allocationContextCalls++;
        const method = { shader: "createShader", program: "createProgram", "vertex-array": "createVertexArray",
          "mesh-buffer": "createBuffer", "instance-buffer": "createBuffer" }[resource];
        const create = context[method].bind(context);
        let calls = 0;
        context[method] = (...args) => ++calls === (resource === "instance-buffer" ? 2 : 1) ? null : create(...args);
        return context;
      };
    }, resource);
    await page.goto("/viewer.html");
    await viewerReady(page);
    await expect(page.locator("#cubeCanvas")).toHaveAttribute("data-renderer", "none");
    await expect(page.locator("#cubeCanvas")).toHaveAttribute("data-gl-error", /unavailable/);
    const source = await page.evaluate(() => window.threeMd.source);
    await page.evaluate(() => {
      for (let index = 0; index < 256; index++) document.getElementById("cubeCanvas").dispatchEvent(new Event("threemd-cubes"));
    });
    expect(await page.evaluate(() => window.__allocationContextCalls)).toBe(1);
    await page.locator("#sliceTab").click();
    await expect(page.locator("#sliceWorkspace")).toBeVisible();
    await page.locator("#previewTab").click();
    expect(await page.evaluate(() => window.threeMd.source)).toBe(source);
    expect(errors).toEqual([]);
  });
}

test("a genuine startup loss pauses before its event and rebuilds once after restoration", async ({ page }) => {
  const errors = [];
  page.on("pageerror", error => errors.push(error.message));
  await page.addInitScript(() => {
    window.__earlyContextCalls = 0;
    let first = true;
    const original = HTMLCanvasElement.prototype.getContext;
    HTMLCanvasElement.prototype.getContext = function(type, ...args) {
      const context = original.call(this, type, ...args);
      if (this.id !== "cubeCanvas" || type !== "webgl2" || !context) return context;
      window.__earlyContextCalls++;
      if (first) {
        first = false;
        window.__earlyLoss = context.getExtension("WEBGL_lose_context");
        // Simulate a driver that loses its context before delivering the app's event.
        this.addEventListener("webglcontextlost", event => {
          event.preventDefault();
          event.stopImmediatePropagation();
          window.__earlyLossDelivered = true;
        }, { capture: true, once: true });
        window.__earlyLoss?.loseContext();
      }
      return context;
    };
  });
  await page.goto("/viewer.html");
  await viewerReady(page);
  expect(await page.evaluate(() => Boolean(window.__earlyLoss))).toBe(true);
  await expect(page.locator("#cubeCanvas")).toHaveAttribute("data-renderer", "lost");
  await expect.poll(() => page.evaluate(() => window.__earlyLossDelivered)).toBe(true);
  const source = await page.evaluate(() => window.threeMd.source);
  await page.locator("#sliceTab").click();
  await page.locator("#sliceList button").nth(1).click();
  await page.evaluate(() => {
    for (let index = 0; index < 256; index++) document.getElementById("cubeCanvas").dispatchEvent(new Event("threemd-cubes"));
  });
  expect(await page.evaluate(() => window.__earlyContextCalls)).toBe(1);
  const pose = await page.locator("#cubeCanvas").evaluate(canvas =>
    [canvas.dataset.yaw, canvas.dataset.pitch, canvas.dataset.rotation, canvas.dataset.panX, canvas.dataset.panY]);
  await page.evaluate(() => window.__earlyLoss.restoreContext());
  await expect(page.locator("#cubeCanvas")).toHaveAttribute("data-renderer", "webgl2");
  expect(await page.evaluate(() => window.__earlyContextCalls)).toBe(2);
  expect(await page.evaluate(() => document.getElementById("cubeCanvas").__cubeGl.getError())).toBe(0);
  expect(await page.evaluate(() => window.threeMd.source)).toBe(source);
  expect(await page.locator("#cubeCanvas").evaluate(canvas =>
    [canvas.dataset.yaw, canvas.dataset.pitch, canvas.dataset.rotation, canvas.dataset.panX, canvas.dataset.panY])).toEqual(pose);
  await expect(page.locator("#sliceHeading")).toHaveText("Slice 2 of 3");
  expect(errors).toEqual([]);
});
