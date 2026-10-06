import { describe, expect, test } from "bun:test";
import { existsSync } from "node:fs";
import { DocumentStorageCodec, type Document } from "../src/index.ts";

// Runs the built development adapter exactly as the interchange gate does. The js lane builds dist first.
const directory = new URL("..", import.meta.url).pathname;
function adapterReplies(payloads: readonly unknown[]): readonly { ok: boolean; error?: string }[] {
  if (!existsSync(`${directory}dist/index.js`)) throw new Error("Run `bun run build` before the adapter tests.");
  const lines = payloads.map((payload) => JSON.stringify({ schema: "3md-interchange-1", kind: "files",
    bytesHex: Buffer.from(typeof payload === "string" ? payload : JSON.stringify(payload)).toString("hex") }));
  const run = Bun.spawnSync({ cmd: ["node", "scripts/interchange.mjs"], cwd: directory,
    stdin: Buffer.from(`${lines.join("\n")}\n`), stdout: "pipe", stderr: "pipe" });
  expect(run.exitCode).toBe(0);
  return run.stdout.toString().trim().split("\n").map((line) => JSON.parse(line) as { ok: boolean; error?: string });
}

describe("development files adapter limits", () => {
  test("limit literals are judged by their correctly rounded IEEE double, like Swift and Rust", () => {
    const leaf: Document = { version: "1.1", axis: "space", title: null, preamble: null, metadata: {},
      planes: [{ z: 0, x: null, y: null, label: null, attributes: {}, body: "Leaf" }] };
    const leafHex = Buffer.from(DocumentStorageCodec.encode(leaf)).toString("hex");
    const request = (literal: string) =>
      `{"files":[{"bytesHex":"${leafHex}","path":"root.3md"}],"limits":{"maximumDepth":${literal}},"rootPath":"root.3md"}`;
    const replies = adapterReplies([request("999999.0000000001"), request("9007199254740991.4"), request("6.4e1"),
      request("9007199254740992"), request("-0")]);
    expect(replies.map((reply) => reply.ok ? "ok" : reply.error)).toEqual(
      ["adapterFailure", "invalidLimits", "ok", "adapterFailure", "invalidLimits"]);
  });
});
