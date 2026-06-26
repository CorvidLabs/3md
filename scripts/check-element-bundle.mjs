import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { $ } from "bun";

const root = new URL("../", import.meta.url);
const source = new URL("element/src/three-md.ts", root);
const distBundle = new URL("element/dist/three-md.js", root);
const webBundle = new URL("web/assets/three-md.js", root);
const tempDir = await mkdtemp(join(tmpdir(), "three-md-bundle-"));
const builtBundle = join(tempDir, "three-md.js");

try {
  await $`bun build ${source.pathname} --outfile ${builtBundle} --format esm --target browser --minify`;

  const built = await Bun.file(builtBundle).text();
  const web = await Bun.file(webBundle).text();

  let failed = false;
  if (built !== web) {
    console.error("web/assets/three-md.js is stale. Run: cd element && bun run build");
    failed = true;
  }
  if (await Bun.file(distBundle).exists()) {
    const dist = await Bun.file(distBundle).text();
    if (built !== dist) {
      console.error("element/dist/three-md.js is stale. Run: cd element && bun run build");
      failed = true;
    }
  }

  if (failed) {
    process.exit(1);
  }

  console.log("element bundle is current");
} finally {
  await rm(tempDir, { recursive: true, force: true });
}
