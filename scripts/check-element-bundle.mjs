import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { $ } from "bun";

const root = new URL("../", import.meta.url);
const source = new URL("element/src/three-md.ts", root);
const distBundle = new URL("element/dist/three-md.js", root);
const webBundle = new URL("web/assets/three-md.js", root);
const tempDir = await mkdtemp(join(tmpdir(), "three-md-bundle-"));
// The element imports only `parse`. Storage, the structured payload (ThreeMD 2.1 payload kind 2) and the checksum
// must tree-shake away completely (docs/design/threemd-2.1/test-plan.md, section 9): each marker below appears only in
// that code, and the minified bundle stays within the byte budget (2.0.0: 48,816 bytes).
const storageMarkers = [
  "TextDecoder", "Int32Array", "Float32Array", "DocumentStorageError", "Scalar fields cannot contain",
  "structured payload", "getBigUint64",
];
const maximumBundleBytes = 50_000;
const builtBundle = join(tempDir, "three-md.js");

try {
  await $`bun build ${source.pathname} --outfile ${builtBundle} --format esm --target browser --minify`;

  const built = await Bun.file(builtBundle).text();
  const web = await Bun.file(webBundle).text();

  let failed = false;
  const leaked = storageMarkers.filter((marker) => built.includes(marker));
  if (leaked.length > 0) {
    console.error(`element bundle contains storage code (markers: ${leaked.join(", ")}). Keep storage.ts, ` +
      "structured.ts and checksum.ts free of top-level side effects and out of the parser's imports.");
    failed = true;
  }
  const bundleBytes = (await Bun.file(builtBundle).arrayBuffer()).byteLength;
  if (bundleBytes > maximumBundleBytes) {
    console.error(`element bundle is ${bundleBytes} bytes, over the ${maximumBundleBytes}-byte budget.`);
    failed = true;
  }
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

  console.log(`element bundle is current (${bundleBytes} bytes, no storage code)`);
} finally {
  await rm(tempDir, { recursive: true, force: true });
}
