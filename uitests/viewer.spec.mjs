import { test, expect } from "@playwright/test";

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
      const start = performance.now();
      for (let i = 0; i < 20; i++) {
        canvas.dispatchEvent(new PointerEvent("pointerdown", { clientX: 400, clientY: 300, pointerId: 1, bubbles: true }));
        canvas.dispatchEvent(new PointerEvent("pointermove", { clientX: 400 + i * 6, clientY: 300 + i, pointerId: 1, bubbles: true }));
        canvas.dispatchEvent(new PointerEvent("pointerup", { clientX: 460, clientY: 320, pointerId: 1, bubbles: true }));
      }
      return {
        ms: performance.now() - start,
        count: Number(canvas.dataset.cubes),
        renderer: canvas.dataset.renderer,
      };
    });
    expect(timed.renderer).toBe("webgl2");
    expect(timed.count).toBeGreaterThan(1400);
    expect(timed.ms).toBeLessThan(800);
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
});
