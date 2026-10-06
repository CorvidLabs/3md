import { describe, expect, test } from "bun:test";
import {
  DocumentComposition, DocumentCompositionCodec, DocumentCompositionError, DocumentCompositionLimits,
  DocumentDecodeLimits, DocumentFileComposition, DocumentFileCompositionError, DocumentStorageCodec,
  DocumentStorageError, DocumentStorageFormat,
  type Document, type DocumentCompositionErrorCode, type DocumentFileCompositionErrorCode, type DocumentFileSource,
} from "../src/index.ts";

function document(body = "Markdown stays local", metadata: Record<string, string> = {}): Document {
  return { version: "2.0", axis: "custom", title: "Linked model", preamble: "Host controls glyph placement.", metadata,
    planes: [{ z: 1, x: 2, y: null, label: "Section", attributes: {}, body }] };
}
function source(path: string, value = document(), binary = false): DocumentFileSource {
  return { path, data: DocumentStorageCodec.encode(value, binary ? DocumentStorageFormat.binary() : DocumentStorageFormat.text) };
}
function host(ledger: string): Document { return document("1 2\n[ordinary Markdown](not-a-file-link.3md)", { "3md-files": ledger, retained: "opaque" }); }
function rejects(code: DocumentFileCompositionErrorCode, operation: () => unknown): void {
  try { operation(); throw new Error("Expected file composition failure"); }
  catch (error) { expect(error).toBeInstanceOf(DocumentFileCompositionError); expect((error as DocumentFileCompositionError).code).toBe(code); }
}
function graphRejects(code: DocumentCompositionErrorCode, operation: () => unknown): void {
  try { operation(); throw new Error("Expected composition failure"); }
  catch (error) { expect(error).toBeInstanceOf(DocumentCompositionError); expect((error as DocumentCompositionError).code).toBe(code); }
}

describe("explicit supplied-file composition", () => {
  test("simple and repeated glyph links deduplicate files and refresh changed child bytes", () => {
    const root = host('{"2":"child.3md","1":"./child.3md"}');
    const sources = [source("root.3md", root), source("child.3md", document("Original child")),
      { path: "unreachable.3md", data: new Uint8Array([0xff]) }];
    const first = DocumentFileComposition.resolve("./root.3md", sources);
    expect(first.rootPath).toBe("root.3md");
    expect(first.resolvedPaths).toEqual(["child.3md", "root.3md"]);
    expect(first.composition.entries).toHaveLength(2);
    expect(first.fileRootIDs).toEqual({ "child.3md": "file-000000", "root.3md": "file-000001" });
    expect(first.composition.rootEntry.document).toEqual({ ...root, metadata: { retained: "opaque" } });
    expect(first.composition.rootEntry.references).toEqual([
      { targetID: "file-000000", attributes: { glyph: "1", "source-file": "child.3md" } },
      { targetID: "file-000000", attributes: { glyph: "2", "source-file": "child.3md" } },
    ]);
    const refreshed = DocumentFileComposition.resolve("root.3md", [sources[0]!, source("child.3md", document("Changed child"))]);
    expect(refreshed.composition.entry("file-000000")?.document.planes[0]?.body).toBe("Changed child");
    expect(first.composition.entry("file-000000")?.document.planes[0]?.body).toBe("Original child");
    expect(Object.isFrozen(first) && Object.isFrozen(first.fileRootIDs) && Object.isFrozen(first.resolvedPaths)).toBe(true);
  });

  test("nested parent paths and duplicate basenames resolve relative to each containing file", () => {
    const result = DocumentFileComposition.resolve("root.3md", [
      source("root.3md", host('{"1":"a/child.3md","2":"b/child.3md"}')),
      source("a/child.3md", host('{"x":"../shared/model.3md"}')),
      source("b/child.3md", document("Different child")), source("shared/model.3md", document("Shared leaf"), true),
    ]);
    expect(result.resolvedPaths).toEqual(["a/child.3md", "b/child.3md", "root.3md", "shared/model.3md"]);
    expect(result.composition.entry(result.fileRootIDs["a/child.3md"]!)?.references[0]?.targetID)
      .toBe(result.fileRootIDs["shared/model.3md"]);
    expect(result.composition.entry(result.fileRootIDs["b/child.3md"]!)?.document.planes[0]?.body).toBe("Different child");
  });

  test("binary nested bundles retain unused entries, stable identities and opaque edges before new ledger edges", () => {
    const attributes = JSON.parse('{"3md-id":"original-reference","opaque":"\\u0000\\n雪","__proto__":"kept"}') as Record<string, string>;
    const leaf = { ...document("Existing leaf", { "3md-id": "existing-document" }),
      planes: [{ ...document().planes[0]!, attributes: { "3md-id": "existing-plane" } }] };
    const nested = new DocumentComposition("zRoot", [
      { id: "zRoot", document: host('{"1":"external.3mdb"}'), references: [{ targetID: "aLeaf", attributes }] },
      { id: "aLeaf", document: leaf, references: [] },
      { id: "uUnused", document: host('{"2":"unused-child.3md"}'), references: [] },
    ]);
    const result = DocumentFileComposition.resolve("root.3mdb", [
      source("root.3mdb", DocumentCompositionCodec.document(nested), true),
      source("external.3mdb", document("Binary child"), true), source("unused-child.3md", document("Unused ledger child")),
    ]);
    expect(result.composition.entries).toHaveLength(5);
    expect(result.composition.rootID).toBe("file-000003");
    expect(result.composition.entry("file-000001")?.document).toEqual(leaf);
    expect(result.composition.rootEntry.references).toEqual([
      { targetID: "file-000001", attributes },
      { targetID: "file-000000", attributes: { glyph: "1", "source-file": "external.3mdb" } },
    ]);
    expect(result.composition.entry("file-000002")?.references[0]?.targetID).toBe("file-000004");
    expect(result.composition.rootEntry.references[1]?.attributes["3md-id"]).toBeUndefined();
    for (const entry of result.composition.entries) expect(Object.hasOwn(entry.document.metadata, "3md-files")).toBe(false);
    const portable = DocumentStorageCodec.encode(DocumentCompositionCodec.document(result.composition), DocumentStorageFormat.binary());
    expect(DocumentCompositionCodec.decode(portable)).toEqual(result.composition);
    expect(DocumentCompositionCodec.decode(DocumentCompositionCodec.encode(result.composition))).toEqual(result.composition);
  });

  test("nested profile records use the outer composition policy while embedded ordinary records retain child bounds", () => {
    const body = "x".repeat(4 * 1024 * 1024 + 256);
    const nested = new DocumentComposition("a", [
      { id: "a", document: document(body), references: [] },
      { id: "b", document: document(body), references: [] },
    ]);
    const text = DocumentCompositionCodec.encode(nested);
    expect(text.length).toBeGreaterThan(DocumentDecodeLimits.standard.maximumRecordBytes);
    const result = DocumentFileComposition.resolve("large.3md", [{ path: "large.3md", data: text }]);
    expect(result.composition.entries).toHaveLength(2);
    expect(result.composition.rootEntry.document.planes[0]?.body).toBe(body);
    expect(() => DocumentFileComposition.resolve("large.3md", [{ path: "large.3md", data: text }], undefined,
      new DocumentDecodeLimits({ maximumRecordBytes: 1024 }))).toThrow(DocumentStorageError);
  });

  test("paths use NFC and Unicode scalar ordering rather than UTF16 or locale sorting", () => {
    const result = DocumentFileComposition.resolve("root.3md", [
      source("root.3md", host('{"z":"😀.3md","a":"\\ue000.3md","e":"e\\u0301.3md"}')),
      source("😀.3md"), source("\ue000.3md"), source("é.3md"),
    ]);
    expect(result.resolvedPaths).toEqual(["root.3md", "é.3md", "\ue000.3md", "😀.3md"]);
    expect(result.composition.rootEntry.references.map((edge) => edge.attributes["source-file"]))
      .toEqual(["\ue000.3md", "é.3md", "😀.3md"]);
    expect(DocumentFileComposition.resolvePath("../e\u0301.3md", "folder/owner.3md")).toBe("é.3md");
    expect(DocumentFileComposition.resolvePath("%2e%2e/file.any", "folder/owner.3md")).toBe("folder/%2e%2e/file.any");
    expect(DocumentFileComposition.resolvePath("File", "folder/owner.3md")).not.toBe(DocumentFileComposition.resolvePath("file", "folder/owner.3md"));
  });

  test("path grammar rejects escape, absolute paths, empty segments, controls and normalized aliases", () => {
    for (const path of ["", "/root.3md", "a\\b", "a:b", "a//b", "a/", "..", "../root.3md", "a/../../b", ".", "a/..", "a\u0000b", "a\u007fb", "\ud800"]) {
      rejects("invalidPath", () => DocumentFileComposition.resolvePath(path));
    }
    rejects("invalidPath", () => DocumentFileComposition.resolvePath("child", "/owner"));
    rejects("duplicatePath", () => DocumentFileComposition.resolve("root", [source("root"), source("a/../root")]));
    rejects("duplicatePath", () => DocumentFileComposition.resolve("root", [source("root"), source("e\u0301"), source("é")]));
  });

  test("strict ledger scanner rejects duplicate escaped keys, malformed JSON and invalid glyphs before values", () => {
    expect(DocumentFileComposition.ledger(document())).toEqual([]);
    expect(DocumentFileComposition.ledger(host('{}'))).toEqual([]);
    expect(DocumentFileComposition.ledger(host('{"~":"last","!":"first"}'))).toEqual([{ glyph: "!", source: "first" }, { glyph: "~", source: "last" }]);
    for (const ledger of ['{"1":"a","\\u0031":"b"}', '[]', 'null', '{"1":true}', '{"1":2}', '{"1":{}}', '{"1":"a",}', '{"1":"a"} false', '{"1":"\\ud800"}', '{"1":"a'] ) {
      rejects("invalidLedger", () => DocumentFileComposition.ledger(host(ledger)));
    }
    for (const glyph of [" ", "é", "😀", "two", "\n"]) rejects("invalidGlyph", () => DocumentFileComposition.ledger(host(JSON.stringify({ [glyph]: "child" }))));
    rejects("invalidGlyph", () => DocumentFileComposition.ledger(host('{"é":"a","e\\u0301":"b"}')));
    rejects("invalidGlyph", () => DocumentFileComposition.ledger(host('{"é":null}')));
    rejects("invalidPath", () => DocumentFileComposition.resolve("root", [source("root", host('{"1":""}'))]));
  });

  test("missing files and malformed reachable storage retain distinct errors, unreachable storage is ignored", () => {
    rejects("missingFile", () => DocumentFileComposition.resolve("missing", []));
    rejects("missingFile", () => DocumentFileComposition.resolve("root", [source("root", host('{"1":"missing"}'))]));
    expect(() => DocumentFileComposition.resolve("bad", [{ path: "bad", data: new Uint8Array([255]) }])).toThrow(DocumentStorageError);
    expect(DocumentFileComposition.resolve("root", [source("root"), { path: "bad", data: new Uint8Array([255]) }]).resolvedPaths).toEqual(["root"]);
  });

  test("file cycles also fail when unused bundle entries form a cycle across files", () => {
    graphRejects("cycle", () => DocumentFileComposition.resolve("root", [source("root", host('{"1":"root"}'))]));
    graphRejects("cycle", () => DocumentFileComposition.resolve("a", [source("a", host('{"1":"b"}')), source("b", host('{"2":"a"}'))]));
    const graph = new DocumentComposition("main", [
      { id: "main", document: document(), references: [] },
      { id: "unused", document: host('{"1":"b"}'), references: [] },
    ]);
    graphRejects("cycle", () => DocumentFileComposition.resolve("a", [source("a", DocumentCompositionCodec.document(graph)), source("b", host('{"1":"a"}'))]));
  });

  test("supplied counts, original path bytes and reachable bytes use input limits before decoding", () => {
    rejects("inputLimit", () => DocumentFileComposition.resolve("root", [source("root"), source("unused")], new DocumentCompositionLimits({ maximumDefinitions: 1 })));
    rejects("inputLimit", () => DocumentFileComposition.resolve("root", [{ path: "root", data: new Uint8Array([255]) }], new DocumentCompositionLimits({ maximumProfileBytes: 7 })));
    const root = source("r");
    rejects("inputLimit", () => DocumentFileComposition.resolve("r", [root], new DocumentCompositionLimits({ maximumProfileBytes: root.data.length - 1 })));
    expect(DocumentFileComposition.resolve("r", [root, { path: "unreachable", data: new Uint8Array(500) }]).resolvedPaths).toEqual(["r"]);
    const bound = DocumentDecodeLimits.standard.maximumRecordBytes;
    rejects("inputLimit", () => DocumentFileComposition.resolvePath("a".repeat(bound), "b"));
    rejects("inputLimit", () => DocumentFileComposition.ledger(host(" ".repeat(bound + 1))));
  });

  test("lowered policies enforce discovery depth, imported entries, edges, conceptual traversal and final profile size", () => {
    const sources = [source("root", host('{"1":"short","2":"long"}')), source("short", host('{"1":"leaf"}')),
      source("long", host('{"1":"short"}')), source("leaf")];
    graphRejects("depthExceeded", () => DocumentFileComposition.resolve("root", sources, new DocumentCompositionLimits({ maximumDepth: 3 })));
    graphRejects("tooManyReferences", () => DocumentFileComposition.resolve("root", [source("root", host('{"1":"child"}')), source("child")], new DocumentCompositionLimits({ maximumReferences: 0 })));
    graphRejects("traversalOccurrencesExceeded", () => DocumentFileComposition.resolve("root", [source("root", host('{"1":"child","2":"child"}')), source("child")], new DocumentCompositionLimits({ maximumTraversalOccurrences: 2 })));
    const nested = new DocumentComposition("a", [{ id: "a", document: document(), references: [] }, { id: "b", document: document(), references: [] }]);
    graphRejects("tooManyDefinitions", () => DocumentFileComposition.resolve("root", [source("root", DocumentCompositionCodec.document(nested))], new DocumentCompositionLimits({ maximumDefinitions: 1 })));
    const only = source("r");
    graphRejects("profileBytesExceeded", () => DocumentFileComposition.resolve("r", [only], new DocumentCompositionLimits({ maximumProfileBytes: only.data.length + 10 })));
    expect(() => DocumentFileComposition.resolve("r", [only], undefined, { ...DocumentDecodeLimits.standard, maximumPlanes: Infinity })).toThrow(DocumentStorageError);
    graphRejects("invalidLimits", () => DocumentFileComposition.resolve("r", [only], { ...DocumentCompositionLimits.standard, maximumDepth: Infinity }));
  });

  test("pre-aborted and cooperatively aborted operations propagate the caller's cancellation reason", () => {
    const controller = new AbortController(); const reason = new Error("stop linked intake"); controller.abort(reason);
    expect(() => DocumentFileComposition.ledger(document(), controller.signal)).toThrow(reason);
    expect(() => DocumentFileComposition.resolvePath("root", undefined, controller.signal)).toThrow(reason);
    expect(() => DocumentFileComposition.resolve("root", [source("root")], undefined, undefined, controller.signal)).toThrow(reason);
    const ongoing = new AbortController(); const check = ongoing.signal.throwIfAborted.bind(ongoing.signal); let calls = 0;
    Object.defineProperty(ongoing.signal, "throwIfAborted", { value: () => { calls += 1; if (calls === 20) ongoing.abort(reason); check(); } });
    expect(() => DocumentFileComposition.resolve("root", [source("root"), source("a"), source("b")], undefined, undefined, ongoing.signal)).toThrow(reason);
    expect(calls).toBe(20);
  });
});
