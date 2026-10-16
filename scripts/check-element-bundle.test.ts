import { expect, test } from "bun:test";
import { cp, mkdir, mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const checker = fileURLToPath(new URL("./check-element-bundle.mjs", import.meta.url));

type Scenario = {
  source?: string;
  web?: string;
  dist?: string;
  spaces?: boolean;
  buildError?: boolean;
};

async function check(scenario: Scenario = {}) {
  const root = await mkdtemp(join(tmpdir(), scenario.spaces ? "element check " : "element-check-"));
  try {
    for (const directory of ["scripts", "element/src", "element/dist", "web/assets", "tmp"]) {
      await mkdir(join(root, directory), { recursive: true });
    }
    await cp(checker, join(root, "scripts/check-element-bundle.mjs"));
    const source = scenario.source ?? "export const value = 42;";
    const entry = join(root, "element/src/three-md.ts");
    await writeFile(entry, source);
    const built = await Bun.build({ entrypoints: [entry], format: "esm", target: "browser", minify: true });
    const bundle = built.success ? await built.outputs[0].text() : "invalid source";
    const web = scenario.web ?? bundle;
    const dist = scenario.dist ?? bundle;
    await writeFile(join(root, "web/assets/three-md.js"), web);
    await writeFile(join(root, "element/dist/three-md.js"), dist);
    if (scenario.buildError) await writeFile(entry, "export const = ;");

    const child = Bun.spawn([process.execPath, "scripts/check-element-bundle.mjs"], {
      cwd: root,
      env: {
        ...process.env,
        PATH: `${dirname(process.execPath)}:${process.env.PATH ?? ""}`,
        TMPDIR: join(root, "tmp"),
      },
      stdout: "pipe",
      stderr: "pipe",
    });
    const [exitCode, stdout, stderr] = await Promise.all([
      child.exited,
      new Response(child.stdout).text(),
      new Response(child.stderr).text(),
    ]);
    return {
      exitCode,
      stdout,
      stderr,
      scratch: await readdir(join(root, "tmp")),
      webUnchanged: await readFile(join(root, "web/assets/three-md.js"), "utf8") === web,
      distUnchanged: await readFile(join(root, "element/dist/three-md.js"), "utf8") === dist,
    };
  } finally {
    await rm(root, { recursive: true, force: true });
  }
}

test("a matching bundle succeeds without leaving scratch output", async () => {
  const result = await check();
  expect(result.exitCode).toBe(0);
  expect(result.stdout).toContain("element bundle is current");
  expect(result.scratch).toEqual([]);
  expect(result.webUnchanged && result.distUnchanged).toBe(true);
});

for (const [name, scenario, diagnostic] of [
  ["stale web bundle", { web: "stale web" }, "web/assets/three-md.js is stale"],
  ["stale package bundle", { dist: "stale dist" }, "element/dist/three-md.js is stale"],
  ["storage code", { source: 'export const value = "DocumentStorageError";' }, "contains storage code"],
  ["oversized bundle", { source: `export const value = ${JSON.stringify("x".repeat(50_001))};` }, "over the 50000-byte budget"],
] as const) {
  test(`${name} fails without leaking scratch output or changing bundles`, async () => {
    const result = await check(scenario);
    expect(result.exitCode).toBe(1);
    expect(result.stderr).toContain(diagnostic);
    expect(result.stdout).not.toContain("element bundle is current");
    expect(result.scratch).toEqual([]);
    expect(result.webUnchanged && result.distUnchanged).toBe(true);
  });
}

test("a checkout path with spaces is built correctly", async () => {
  const result = await check({ spaces: true });
  expect(result.exitCode).toBe(0);
  expect(result.stdout).toContain("element bundle is current");
  expect(result.scratch).toEqual([]);
});

test("a build error fails and cleans up its scratch output", async () => {
  const result = await check({ buildError: true });
  expect(result.exitCode).not.toBe(0);
  expect(result.stdout).not.toContain("element bundle is current");
  expect(result.scratch).toEqual([]);
  expect(result.webUnchanged && result.distUnchanged).toBe(true);
});
