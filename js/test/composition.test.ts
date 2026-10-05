import { describe, expect, test } from "bun:test";
import {
  DocumentComposition, DocumentCompositionCodec, DocumentCompositionError, DocumentCompositionLimits,
  DocumentDecodeLimits, DocumentStorageError, parse,
  type Document, type DocumentCompositionErrorCode, type DocumentEntry,
} from "../src/index.ts";

function entry(id: string, targets: readonly string[] = []): DocumentEntry {
  return { id, document: parse(`---\n3md: 1\n---\n@plane z=0\n${id}\n`), references: targets.map((targetID) => ({ targetID, attributes: {} })) };
}
function profile(json: string): Document {
  return { version: "0.1", axis: "layer", title: null, preamble: null, metadata: { profile: "3md-composition-1" },
    planes: [{ z: 0, label: "Composition", x: null, y: null, attributes: {}, body: `\`\`\`json\n${json}\n\`\`\`` }] };
}
function rejects(code: DocumentCompositionErrorCode, operation: () => unknown): void {
  let caught: unknown;
  try { operation(); } catch (error) { caught = error; }
  expect(caught).toBeInstanceOf(DocumentCompositionError);
  expect((caught as DocumentCompositionError).code).toBe(code);
}
const source = "---\n3md: 1\n---\n@plane z=0\nBody\n";
function manifest(): { schema: string; rootID: string; entries: { id: string; source: string;
  references: { targetID: string; attributes: Record<string, string> }[] }[] } {
  return { schema: "3md-composition-1", rootID: "root", entries: [{ id: "root", source, references: [] }] };
}

describe("bounded self-contained composition", () => {
  test("safe ID grammar, duplicates, absent roots and unreachable missing targets fail", () => {
    for (const id of ["", "_start", "../path", "https://host", "é", "a".repeat(65)]) rejects("invalidID", () => new DocumentComposition(id, []));
    rejects("duplicateID", () => new DocumentComposition("root", [entry("root"), entry("root")]));
    rejects("missingRoot", () => new DocumentComposition("root", [entry("other")]));
    rejects("missingTarget", () => new DocumentComposition("root", [entry("root"), entry("unused", ["missing"])]));
    const valid = new DocumentComposition("A_9", [entry("A_9"), entry("case"), entry("Case")]);
    expect(valid.entries.map((entry) => entry.id)).toEqual(["A_9", "Case", "case"]);
    expect(valid.entry("Case")?.id).toBe("Case"); expect(valid.entry("CASE")).toBeUndefined();
  });
  test("cycles, unused cycles, cached depth and repeated-traversal occurrence limits fail", () => {
    rejects("cycle", () => new DocumentComposition("root", [entry("root", ["root"])]));
    rejects("cycle", () => new DocumentComposition("root", [entry("root"), entry("unused", ["unused"])]));
    const chain = [entry("a", ["b"]), entry("b", ["c"]), entry("c")];
    rejects("depthExceeded", () => new DocumentComposition("a", chain, new DocumentCompositionLimits({ maximumDepth: 2 })));
    expect(new DocumentComposition("a", [...chain].reverse(), new DocumentCompositionLimits({ maximumDepth: 3 })).entries.length).toBe(3);
    const repeated = [entry("root", ["shared", "shared"]), entry("shared", ["leaf", "leaf"]), entry("leaf")];
    rejects("traversalOccurrencesExceeded", () => new DocumentComposition("root", repeated,
      new DocumentCompositionLimits({ maximumTraversalOccurrences: 6 })));
    expect(new DocumentComposition("root", repeated, new DocumentCompositionLimits({ maximumTraversalOccurrences: 7 })).entries.length).toBe(3);
  });
  test("counts, unique source bytes and per-reference UTF-8 attributes are bounded", () => {
    rejects("tooManyDefinitions", () => new DocumentComposition("root", [entry("root"), entry("leaf")], new DocumentCompositionLimits({ maximumDefinitions: 1 })));
    rejects("tooManyReferences", () => new DocumentComposition("root", [entry("root", ["leaf"]), entry("leaf")], new DocumentCompositionLimits({ maximumReferences: 0 })));
    rejects("definitionBytesExceeded", () => new DocumentComposition("root", [entry("root")], new DocumentCompositionLimits({ maximumDefinitionBytes: 8 })));
    const root = { ...entry("root", ["leaf"]), references: [{ targetID: "leaf", attributes: { key: "雪" } }] };
    rejects("referenceAttributesExceeded", () => new DocumentComposition("root", [root, entry("leaf")], new DocumentCompositionLimits({ maximumReferenceAttributes: 0 })));
    rejects("referenceAttributesExceeded", () => new DocumentComposition("root", [root, entry("leaf")], new DocumentCompositionLimits({ maximumReferenceAttributeBytes: 5 })));
    expect(new DocumentComposition("root", [root, entry("leaf")], new DocumentCompositionLimits({ maximumReferenceAttributeBytes: 6 })).rootEntry.references[0]?.attributes["key"]).toBe("雪");
    expect(() => new DocumentComposition("root", [entry("root")], undefined, new DocumentDecodeLimits({ maximumRecordBytes: 2 }))).toThrow(DocumentStorageError);
  });
  test("constructors enforce absolute integer limits and legitimate zero reference limits", () => {
    for (const maximumDepth of [0, 65, 1.5, NaN]) rejects("invalidLimits", () => new DocumentCompositionLimits({ maximumDepth }));
    expect(new DocumentCompositionLimits({ maximumReferences: 0, maximumReferenceAttributes: 0, maximumReferenceAttributeBytes: 0 }).maximumReferences).toBe(0);
  });
  test("public graph codecs validate plain-object composition policies before reading or writing", () => {
    const graph = new DocumentComposition("root", [entry("root")]);
    const invalid = { ...DocumentCompositionLimits.standard, maximumProfileBytes: Infinity };
    rejects("invalidLimits", () => new DocumentComposition("root", graph.entries, invalid));
    rejects("invalidLimits", () => DocumentCompositionCodec.document(graph, invalid));
    rejects("invalidLimits", () => DocumentCompositionCodec.encode(graph, invalid));
    rejects("invalidLimits", () => DocumentCompositionCodec.decode(new Uint8Array(), invalid));
    const invalidChild = { ...DocumentDecodeLimits.standard, maximumPlanes: Infinity };
    expect(() => new DocumentComposition("root", graph.entries, undefined, invalidChild)).toThrow(DocumentStorageError);
  });
  test("strict envelopes, schemas, unknown fields and JSON types are rejected", () => {
    const original = manifest();
    for (const value of [{ ...original, extra: "bad" }, { ...original, entries: [{ ...original.entries[0], extra: "bad" }] },
      { ...original, rootID: true }, { ...original, entries: [{ id: "root", source, references: [{ targetID: "root", attributes: { key: 2 } }] }] }]) {
      rejects("invalidProfile", () => DocumentCompositionCodec.decode(profile(JSON.stringify(value))));
    }
    rejects("unsupportedProfile", () => DocumentCompositionCodec.decode(profile(JSON.stringify({ ...original, schema: "future" }))));
    rejects("invalidProfile", () => DocumentCompositionCodec.decode({ ...profile(JSON.stringify(original)), title: "extra" }));
    rejects("unsupportedProfile", () => DocumentCompositionCodec.decode({ ...profile(JSON.stringify(original)), metadata: {} }));
  });
  test("duplicate escaped keys, nested records, numeric fields and trailing JSON fail before object decoding", () => {
    const invalid = [
      '{"schema":"3md-composition-1","rootID":"root","\\u0072ootID":"root","entries":[]}',
      '{"schema":"3md-composition-1","rootID":"root","entries":[{"id":"root","id":"other","source":"x","references":[]}]}',
      '[1]', '["' + "a" + '"] true', "[".repeat(14) + "null" + "]".repeat(14),
      JSON.stringify({ ...manifest(), extra: 1 }),
    ];
    for (const value of invalid) rejects("invalidProfile", () => DocumentCompositionCodec.decode(profile(value)));
    rejects("invalidProfile", () => DocumentCompositionCodec.decode(profile("[{},{}]"), new DocumentCompositionLimits({ maximumDefinitions: 1, maximumReferences: 0 })));
  });
  test("embedded paths and malformed unused sources stay local parse errors", () => {
    const value = manifest(); value.entries.push({ id: "unused", source: "/private/tmp/never-open-this.3md", references: [] });
    expect(() => DocumentCompositionCodec.decode(profile(JSON.stringify(value)))).toThrow(DocumentStorageError);
    value.entries[1] = { id: "unused", source, references: [{ targetID: "missing", attributes: {} }] };
    rejects("missingTarget", () => DocumentCompositionCodec.decode(profile(JSON.stringify(value))));
  });
  test("profile and escaped JSON bounds count the complete envelope", () => {
    const graph = new DocumentComposition("root", [entry("root")]);
    const bytes = DocumentCompositionCodec.encode(graph);
    expect(DocumentCompositionCodec.decode(bytes, new DocumentCompositionLimits({ maximumProfileBytes: bytes.length }))).toEqual(graph);
    rejects("profileBytesExceeded", () => DocumentCompositionCodec.encode(graph, new DocumentCompositionLimits({ maximumProfileBytes: bytes.length - 1 })));
    rejects("profileBytesExceeded", () => DocumentCompositionCodec.decode(bytes, new DocumentCompositionLimits({ maximumProfileBytes: bytes.length - 1 })));
  });
  test("opaque attributes preserve controls, Unicode and prototype-looking keys", () => {
    const attributes = JSON.parse('{"__proto__":"data","constructor":"value","control":"\\u0000\\n\\t\\\"\\\\雪"}') as Record<string, string>;
    const graph = new DocumentComposition("root", [{ ...entry("root"), references: [{ targetID: "leaf", attributes }] }, entry("leaf")]);
    expect(DocumentCompositionCodec.decode(DocumentCompositionCodec.encode(graph)).rootEntry.references[0]?.attributes).toEqual(attributes);
    expect(Object.getPrototypeOf(graph.rootEntry.references[0]?.attributes)).toBeNull();
  });
  test("pre-aborted graph construction and codecs propagate cancellation", () => {
    const graph = new DocumentComposition("root", [entry("root")]);
    const abort = new AbortController(); const reason = new Error("cancelled"); abort.abort(reason);
    expect(() => new DocumentComposition("root", [entry("root")], undefined, undefined, abort.signal)).toThrow(reason);
    expect(() => DocumentCompositionCodec.encode(graph, undefined, undefined, abort.signal)).toThrow(reason);
    expect(() => DocumentCompositionCodec.decode(new Uint8Array(), undefined, undefined, abort.signal)).toThrow(reason);
  });
  test("new reference writers sort Unicode scalar keys and strict JSON rejects equivalent duplicate keys", () => {
    const attributes = { "😀": "emoji", "\ue000": "private", "e\u0301": "first", z: "ascii", "é": "last" };
    const graph = new DocumentComposition("root", [{ ...entry("root"), references: [{ targetID: "leaf", attributes }] }, entry("leaf")]);
    expect(Object.keys(graph.rootEntry.references[0]?.attributes ?? {}).filter((key) => key.normalize("NFC") === "é")).toEqual(["e\u0301"]);
    const body = DocumentCompositionCodec.document(graph).planes[0]?.body ?? "";
    expect(body).toContain('"attributes": {"z": "ascii", "e\u0301": "last", "\ue000": "private", "😀": "emoji"}');
    const value = manifest(); value.entries[0]!.references = [{ targetID: "root", attributes: { "e\u0301": "first", "é": "second" } }];
    rejects("invalidProfile", () => DocumentCompositionCodec.decode(profile(JSON.stringify(value))));
  });
});
