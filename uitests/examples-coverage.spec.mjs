import { test, expect } from "@playwright/test";

// The guarantee that the canonical renderer works for ANY example: load every
// document in the gallery (gallery-data.json) through the <three-md> component,
// in both the default view and the blend (3D object) view, and assert each one
// parses, renders planes, and produces no console errors.

test("the component renders every gallery example cleanly", async ({ page }) => {
  const consoleErrors = [];
  page.on("console", (m) => { if (m.type() === "error") consoleErrors.push(m.text()); });
  page.on("pageerror", (e) => consoleErrors.push(String(e)));

  await page.goto("/embed-example.html");
  await page.waitForFunction(() => document.getElementById("inline")?.shadowRoot?.querySelectorAll(".plane").length > 0);

  const data = await page.evaluate(async () => {
    const res = await fetch("gallery-data.json");
    return res.json();
  });
  expect(data.length).toBeGreaterThan(100);

  const failures = await page.evaluate((examples) => {
    const lab = document.getElementById("inline");
    const bad = [];
    for (const ex of examples) {
      lab.removeAttribute("mode");
      lab.setSource(ex.src);
      if (lab.error) { bad.push(`${ex.slug}: parse ${lab.error}`); continue; }
      if (lab.shadowRoot.querySelectorAll(".plane").length < 1) { bad.push(`${ex.slug}: no planes`); continue; }
      // also exercise the blend (voxel) path
      lab.setAttribute("mode", "blend");
      lab.setSource(ex.src);
      if (lab.error) bad.push(`${ex.slug}: blend ${lab.error}`);
    }
    return bad;
  }, data);

  expect(failures, `examples that failed to render:\n${failures.join("\n")}`).toEqual([]);
  expect(consoleErrors, consoleErrors.join("\n")).toEqual([]);
});
