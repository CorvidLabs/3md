import type { Document } from "./index.js";
import { boundedInteger, canonicalKeys, canonicalStrings, checkCancellation, frozenDocument, frozenStrings, InvalidUnicodeError, utf8Length, validID } from "./portable.js";
import { BoundedTextWriter, DocumentDecodeLimits, DocumentStorageCodec, DocumentStorageError, DocumentStorageFormat } from "./storage.js";

export interface DocumentReference {
  readonly targetID: string;
  readonly attributes: Readonly<Record<string, string>>;
}
export interface DocumentEntry {
  readonly id: string;
  readonly document: Document;
  readonly references: readonly DocumentReference[];
}
export type DocumentCompositionErrorCode = "invalidLimits" | "invalidID" | "duplicateID" | "missingRoot" |
  "missingTarget" | "cycle" | "tooManyDefinitions" | "tooManyReferences" | "depthExceeded" |
  "definitionBytesExceeded" | "traversalOccurrencesExceeded" | "referenceAttributesExceeded" |
  "profileBytesExceeded" | "invalidProfile" | "unsupportedProfile";
export class DocumentCompositionError extends Error {
  public readonly code: DocumentCompositionErrorCode;
  public readonly detail: string | undefined;
  public readonly target: string | undefined;
  public constructor(code: DocumentCompositionErrorCode, detail?: string, target?: string) {
    super(`${code}${detail === undefined ? "" : `: ${detail}`}${target === undefined ? "" : ` -> ${target}`}`);
    this.name = "DocumentCompositionError";
    this.code = code; this.detail = detail; this.target = target;
  }
}

function compositionDefaults(): {
  maximumDefinitions: number; maximumReferences: number; maximumDepth: number;
  maximumDefinitionBytes: number; maximumTraversalOccurrences: number;
  maximumProfileBytes: number; maximumReferenceAttributes: number; maximumReferenceAttributeBytes: number;
} {
  return { maximumDefinitions: 1024, maximumReferences: 16_384, maximumDepth: 64,
    maximumDefinitionBytes: 16 * 1024 * 1024, maximumTraversalOccurrences: 1_000_000,
    maximumProfileBytes: 20 * 1024 * 1024, maximumReferenceAttributes: 64,
    maximumReferenceAttributeBytes: 16 * 1024 };
}
type CompositionLimitOptions = ReturnType<typeof compositionDefaults>;
export class DocumentCompositionLimits {
  public readonly maximumDefinitions: number;
  public readonly maximumReferences: number;
  public readonly maximumDepth: number;
  public readonly maximumDefinitionBytes: number;
  public readonly maximumTraversalOccurrences: number;
  public readonly maximumProfileBytes: number;
  public readonly maximumReferenceAttributes: number;
  public readonly maximumReferenceAttributeBytes: number;
  public static readonly standard = /* @__PURE__ */ new DocumentCompositionLimits();
  public constructor(options: Partial<{ [Key in keyof CompositionLimitOptions]: number }> = {}) {
    const defaults = compositionDefaults();
    const values = { ...defaults, ...options };
    for (const key of Object.keys(defaults) as (keyof CompositionLimitOptions)[]) {
      const minimum = ["maximumReferences", "maximumReferenceAttributes", "maximumReferenceAttributeBytes"].includes(key) ? 0 : 1;
      if (!boundedInteger(values[key], minimum, defaults[key])) throw new DocumentCompositionError("invalidLimits", key);
    }
    this.maximumDefinitions = values.maximumDefinitions; this.maximumReferences = values.maximumReferences;
    this.maximumDepth = values.maximumDepth; this.maximumDefinitionBytes = values.maximumDefinitionBytes;
    this.maximumTraversalOccurrences = values.maximumTraversalOccurrences; this.maximumProfileBytes = values.maximumProfileBytes;
    this.maximumReferenceAttributes = values.maximumReferenceAttributes; this.maximumReferenceAttributeBytes = values.maximumReferenceAttributeBytes;
    Object.freeze(this);
  }
}

function validateGraph(rootID: string, entries: readonly DocumentEntry[], limits: DocumentCompositionLimits,
  documentLimits: DocumentDecodeLimits, signal?: AbortSignal): Map<string, Uint8Array> {
  checkCancellation(signal);
  if (!validID(rootID)) throw new DocumentCompositionError("invalidID", rootID);
  if (entries.length > limits.maximumDefinitions) throw new DocumentCompositionError("tooManyDefinitions");
  const indices = new Map<string, number>();
  const sources = new Map<string, Uint8Array>();
  let references = 0;
  let sourceBytes = 0;
  for (const [index, entry] of entries.entries()) {
    checkCancellation(signal);
    if (!validID(entry.id)) throw new DocumentCompositionError("invalidID", entry.id);
    if (indices.has(entry.id)) throw new DocumentCompositionError("duplicateID", entry.id);
    indices.set(entry.id, index);
    if (entry.references.length > limits.maximumReferences - references) throw new DocumentCompositionError("tooManyReferences");
    references += entry.references.length;
    for (const reference of entry.references) {
      checkCancellation(signal);
      if (!validID(reference.targetID)) throw new DocumentCompositionError("invalidID", reference.targetID);
      if (Object.keys(reference.attributes).length > limits.maximumReferenceAttributes) throw new DocumentCompositionError("referenceAttributesExceeded");
      let bytes = 0;
      for (const [key, value] of Object.entries(reference.attributes)) {
        for (const text of [key, value]) {
          const count = utf8Length(text, signal);
          if (count > limits.maximumReferenceAttributeBytes - bytes) throw new DocumentCompositionError("referenceAttributesExceeded");
          bytes += count;
        }
      }
    }
    const remaining = limits.maximumDefinitionBytes - sourceBytes;
    if (remaining <= 0) throw new DocumentCompositionError("definitionBytesExceeded");
    const childLimits = new DocumentDecodeLimits({
      maximumEncodedBytes: Math.min(documentLimits.maximumEncodedBytes, remaining),
      maximumDecodedBytes: Math.min(documentLimits.maximumDecodedBytes, remaining),
      maximumLines: documentLimits.maximumLines, maximumPlanes: documentLimits.maximumPlanes,
      maximumRecordBytes: Math.min(documentLimits.maximumRecordBytes, remaining),
    });
    let source: Uint8Array;
    try { source = DocumentStorageCodec.encode(entry.document, DocumentStorageFormat.text, childLimits, signal); }
    catch (error) {
      checkCancellation(signal);
      if (error instanceof DocumentStorageError &&
        ((error.code === "oversizedInput" && remaining <= documentLimits.maximumEncodedBytes) ||
        (error.code === "oversizedOutput" && remaining <= documentLimits.maximumDecodedBytes) ||
        (error.code === "oversizedRecord" && remaining <= documentLimits.maximumRecordBytes))) {
        throw new DocumentCompositionError("definitionBytesExceeded");
      }
      throw error;
    }
    sourceBytes += source.byteLength;
    sources.set(entry.id, source);
  }
  if (!indices.has(rootID)) throw new DocumentCompositionError("missingRoot", rootID);
  for (const entry of entries) {
    for (const reference of entry.references) {
      checkCancellation(signal);
      if (!indices.has(reference.targetID)) throw new DocumentCompositionError("missingTarget", entry.id, reference.targetID);
    }
  }
  const states = new Uint8Array(entries.length);
  const depths = new Uint8Array(entries.length);
  const occurrences = new Uint32Array(entries.length);
  const visit = (index: number, activeDepth: number): void => {
    checkCancellation(signal);
    const entry = entries[index];
    if (entry === undefined) throw new DocumentCompositionError("invalidProfile", "missing graph entry");
    if (states[index] === 1) throw new DocumentCompositionError("cycle", entry.id);
    if (states[index] === 2) return;
    if (activeDepth >= limits.maximumDepth) throw new DocumentCompositionError("depthExceeded");
    states[index] = 1;
    let depth = 1;
    let count = 1;
    for (const reference of entry.references) {
      const target = indices.get(reference.targetID);
      if (target === undefined) throw new DocumentCompositionError("missingTarget", entry.id, reference.targetID);
      visit(target, activeDepth + 1);
      depth = Math.max(depth, (depths[target] ?? 0) + 1);
      if (depth > limits.maximumDepth) throw new DocumentCompositionError("depthExceeded");
      const added = occurrences[target] ?? 0;
      if (added > limits.maximumTraversalOccurrences - count) throw new DocumentCompositionError("traversalOccurrencesExceeded");
      count += added;
    }
    states[index] = 2; depths[index] = depth; occurrences[index] = count;
  };
  for (let index = 0; index < entries.length; index += 1) visit(index, 0);
  return sources;
}

export function frozenReference(reference: DocumentReference, signal?: AbortSignal): DocumentReference {
  checkCancellation(signal);
  return Object.freeze({ targetID: reference.targetID, attributes: frozenStrings(reference.attributes, signal) });
}
export function frozenEntry(entry: DocumentEntry, signal?: AbortSignal): DocumentEntry {
  return Object.freeze({ id: entry.id, document: frozenDocument(entry.document, signal),
    references: Object.freeze(entry.references.map((reference) => frozenReference(reference, signal))) });
}

/** A complete self-contained validated graph; IDs are never external resource names. */
export class DocumentComposition {
  public readonly rootID: string;
  public readonly entries: readonly DocumentEntry[];
  public get rootEntry(): DocumentEntry {
    const root = this.entry(this.rootID);
    if (root === undefined) throw new DocumentCompositionError("missingRoot", this.rootID);
    return root;
  }
  public constructor(rootID: string, entries: readonly DocumentEntry[], limits = DocumentCompositionLimits.standard,
    documentLimits = DocumentDecodeLimits.standard, signal?: AbortSignal) {
    checkCancellation(signal);
    limits = new DocumentCompositionLimits(limits);
    documentLimits = new DocumentDecodeLimits(documentLimits);
    try { validateGraph(rootID, entries, limits, documentLimits, signal); }
    catch (error) {
      checkCancellation(signal);
      if (error instanceof InvalidUnicodeError) throw new DocumentCompositionError("invalidProfile", error.message);
      throw error;
    }
    this.rootID = rootID;
    this.entries = Object.freeze([...entries].sort((left, right) => left.id < right.id ? -1 : left.id > right.id ? 1 : 0)
      .map((entry) => frozenEntry(entry, signal)));
    checkCancellation(signal);
    Object.freeze(this);
  }
  public entry(id: string): DocumentEntry | undefined { return this.entries.find((entry) => entry.id === id); }
  public static fromJSON(value: { readonly rootID: string; readonly entries: readonly DocumentEntry[] },
    limits = DocumentCompositionLimits.standard, documentLimits = DocumentDecodeLimits.standard, signal?: AbortSignal): DocumentComposition {
    return new DocumentComposition(value.rootID, value.entries, limits, documentLimits, signal);
  }
}

/** Preflight before JSON.parse rejects duplicates, nesting and record allocations. */
class JSONScanner {
  private index = 0;
  private arrayElements = 0;
  private objects = 0;
  public constructor(private readonly source: string, private readonly limits: DocumentCompositionLimits,
    private readonly signal?: AbortSignal) {}
  public scan(): void {
    this.value(0); this.whitespace();
    if (this.index !== this.source.length) this.invalid("trailing JSON input");
  }
  private invalid(message: string): never { throw new DocumentCompositionError("invalidProfile", message); }
  private whitespace(): void {
    while (this.index < this.source.length && " \t\r\n".includes(this.source[this.index] ?? "")) {
      if (this.index % 4096 === 0) checkCancellation(this.signal);
      this.index += 1;
    }
  }
  private consume(character: string): boolean {
    if (this.source[this.index] !== character) return false;
    this.index += 1; return true;
  }
  private value(depth: number): void {
    checkCancellation(this.signal);
    if (depth > 12) this.invalid("excessive JSON nesting");
    this.whitespace();
    const character = this.source[this.index];
    if (character === "{") this.object(depth + 1);
    else if (character === "[") this.array(depth + 1);
    else if (character === '"') this.string(false);
    else if (character === "t") this.literal("true");
    else if (character === "f") this.literal("false");
    else if (character === "n") this.literal("null");
    else if (character !== undefined && "-0123456789".includes(character)) this.invalid("numeric JSON fields are not part of this profile");
    else this.invalid("invalid or truncated JSON value");
  }
  private object(depth: number): void {
    this.objects += 1;
    if (this.objects > 1 + this.limits.maximumDefinitions + 2 * this.limits.maximumReferences) this.invalid("too many JSON records");
    this.index += 1; this.whitespace();
    if (this.consume("}")) return;
    const keys = new Set<string>();
    while (true) {
      const key = this.string(true);
      if (key === undefined || keys.has(key.normalize("NFC"))) this.invalid("duplicate JSON object key");
      keys.add(key.normalize("NFC"));
      if (keys.size > Math.max(3, this.limits.maximumReferenceAttributes)) throw new DocumentCompositionError("referenceAttributesExceeded");
      this.whitespace();
      if (!this.consume(":")) this.invalid("missing JSON colon");
      this.value(depth); this.whitespace();
      if (this.consume("}")) return;
      if (!this.consume(",")) this.invalid("missing JSON comma");
      this.whitespace();
    }
  }
  private array(depth: number): void {
    this.index += 1; this.whitespace();
    if (this.consume("]")) return;
    while (true) {
      this.arrayElements += 1;
      if (this.arrayElements > this.limits.maximumDefinitions + this.limits.maximumReferences) this.invalid("too many JSON array elements");
      this.value(depth); this.whitespace();
      if (this.consume("]")) return;
      if (!this.consume(",")) this.invalid("missing JSON comma");
      this.whitespace();
    }
  }
  private string(isKey: boolean): string | undefined {
    if (!this.consume('"')) this.invalid("JSON key must be a string");
    const start = this.index - 1;
    while (this.index < this.source.length) {
      if (this.index % 4096 === 0) checkCancellation(this.signal);
      const character = this.source[this.index] ?? "";
      this.index += 1;
      if (character === '"') {
        if (!isKey) return undefined;
        const raw = this.source.slice(start, this.index);
        if (utf8Length(raw, this.signal) > 6 * this.limits.maximumReferenceAttributeBytes + 256) throw new DocumentCompositionError("referenceAttributesExceeded");
        try {
          const result = JSON.parse(raw) as string;
          utf8Length(result, this.signal);
          return result;
        } catch { checkCancellation(this.signal); return this.invalid("invalid JSON key escape"); }
      }
      if (character.charCodeAt(0) < 32) this.invalid("unescaped JSON control character");
      if (character === "\\") {
        const escaped = this.source[this.index]; this.index += 1;
        if (escaped === "u") {
          if (!/^[0-9a-fA-F]{4}$/.test(this.source.slice(this.index, this.index + 4))) this.invalid("invalid Unicode escape");
          this.index += 4;
        } else if (escaped === undefined || !'"\\/bfnrt'.includes(escaped)) this.invalid("invalid JSON escape");
      }
    }
    return this.invalid("unterminated JSON string");
  }
  private literal(text: string): void {
    if (!this.source.startsWith(text, this.index)) this.invalid("invalid JSON literal");
    this.index += text.length;
  }
}

function object(value: unknown, keys?: readonly string[]): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) throw new DocumentCompositionError("invalidProfile", "JSON fields have invalid types or values");
  const record = value as Record<string, unknown>;
  if (keys !== undefined && (Object.keys(record).length !== keys.length || !keys.every((key) => Object.hasOwn(record, key)))) {
    throw new DocumentCompositionError("invalidProfile", "missing or unknown JSON record keys");
  }
  return record;
}
function string(value: unknown): string {
  if (typeof value !== "string") throw new DocumentCompositionError("invalidProfile", "JSON fields have invalid types or values");
  try { utf8Length(value); }
  catch { throw new DocumentCompositionError("invalidProfile", "invalid Unicode scalar value"); }
  return value;
}
function array(value: unknown): unknown[] {
  if (!Array.isArray(value)) throw new DocumentCompositionError("invalidProfile", "JSON fields have invalid types or values");
  return value as unknown[];
}
function profileLimits(limits: DocumentCompositionLimits): DocumentDecodeLimits {
  return new DocumentDecodeLimits({ maximumEncodedBytes: limits.maximumProfileBytes, maximumDecodedBytes: limits.maximumProfileBytes,
    maximumPlanes: 1, maximumRecordBytes: limits.maximumProfileBytes });
}
function boundedProfile<Value>(operation: () => Value): Value {
  try { return operation(); }
  catch (error) {
    if (error instanceof DocumentStorageError && ["oversizedInput", "oversizedOutput", "oversizedRecord"].includes(error.code)) {
      throw new DocumentCompositionError("profileBytesExceeded");
    }
    throw error;
  }
}

/** Strict versioned composition profile carried by an ordinary general Document. */
export class DocumentCompositionCodec {
  public static isComposition(document: Document): boolean { return document.metadata["profile"] === "3md-composition-1"; }
  public static document(composition: DocumentComposition, limits = DocumentCompositionLimits.standard,
    documentLimits = DocumentDecodeLimits.standard, signal?: AbortSignal): Document {
    checkCancellation(signal);
    limits = new DocumentCompositionLimits(limits);
    documentLimits = new DocumentDecodeLimits(documentLimits);
    const sources = validateGraph(composition.rootID, composition.entries, limits, documentLimits, signal);
    const writer = new BoundedTextWriter(limits.maximumProfileBytes, signal, () => new DocumentCompositionError("profileBytesExceeded"));
    writer.append('{\n  "entries": [');
    for (const [index, entry] of [...composition.entries].sort((left, right) => left.id < right.id ? -1 : left.id > right.id ? 1 : 0).entries()) {
      checkCancellation(signal);
      writer.append(index === 0 ? "\n" : ",\n"); writer.append('    {\n      "id": '); writer.quoted(entry.id, true);
      writer.append(',\n      "references": [');
      for (const [referenceIndex, reference] of entry.references.entries()) {
        writer.append(referenceIndex === 0 ? "\n" : ",\n"); writer.append('        {"attributes": {');
        const attributes = canonicalStrings(reference.attributes, signal);
        for (const [attributeIndex, key] of canonicalKeys(attributes).entries()) {
          writer.append(attributeIndex === 0 ? "" : ", "); writer.quoted(key, true); writer.append(": "); writer.quoted(attributes[key] ?? "", true);
        }
        writer.append('}, "targetID": '); writer.quoted(reference.targetID, true); writer.append("}");
      }
      writer.append(entry.references.length === 0 ? '],\n      "source": ' : '\n      ],\n      "source": ');
      const source = sources.get(entry.id);
      if (source === undefined) throw new DocumentCompositionError("invalidProfile", "definition source missing");
      writer.quoted(new TextDecoder().decode(source), true); writer.append("\n    }");
    }
    writer.append('\n  ],\n  "rootID": '); writer.quoted(composition.rootID, true);
    writer.append(',\n  "schema": "3md-composition-1"\n}');
    const document: Document = { version: "0.1", axis: "layer", title: null, preamble: null,
      metadata: { profile: "3md-composition-1" },
      planes: [{ z: 0, label: "Composition", x: null, y: null, attributes: {}, body: `\`\`\`json\n${writer.finish()}\n\`\`\`` }] };
    boundedProfile(() => DocumentStorageCodec.validate(document, profileLimits(limits), signal));
    return frozenDocument(document, signal);
  }
  public static encode(composition: DocumentComposition, limits = DocumentCompositionLimits.standard,
    documentLimits = DocumentDecodeLimits.standard, signal?: AbortSignal): Uint8Array {
    checkCancellation(signal);
    limits = new DocumentCompositionLimits(limits);
    documentLimits = new DocumentDecodeLimits(documentLimits);
    return boundedProfile(() => DocumentStorageCodec.encode(this.document(composition, limits, documentLimits, signal),
      DocumentStorageFormat.text, profileLimits(limits), signal));
  }
  public static decode(input: Uint8Array | Document, limits = DocumentCompositionLimits.standard,
    documentLimits = DocumentDecodeLimits.standard, signal?: AbortSignal): DocumentComposition {
    checkCancellation(signal);
    limits = new DocumentCompositionLimits(limits);
    documentLimits = new DocumentDecodeLimits(documentLimits);
    let document: Document;
    if (input instanceof Uint8Array) {
      if (input.byteLength > limits.maximumProfileBytes) throw new DocumentCompositionError("profileBytesExceeded");
      document = boundedProfile(() => DocumentStorageCodec.decode(input, profileLimits(limits), signal));
    } else document = input;
    boundedProfile(() => DocumentStorageCodec.validate(document, profileLimits(limits), signal));
    if (!this.isComposition(document)) throw new DocumentCompositionError("unsupportedProfile", document.metadata["profile"] ?? "missing");
    const plane = document.planes[0];
    if (document.version !== "0.1" || document.axis !== "layer" || document.title !== null || document.preamble !== null ||
      Object.keys(document.metadata).length !== 1 || document.planes.length !== 1 || plane === undefined || plane.z !== 0 ||
      plane.label !== "Composition" || plane.x !== null || plane.y !== null || Object.keys(plane.attributes).length !== 0 ||
      !plane.body.startsWith("```json\n") || !plane.body.endsWith("\n```")) {
      throw new DocumentCompositionError("invalidProfile", "unexpected composition envelope");
    }
    const json = plane.body.slice(8, -4);
    new JSONScanner(json, limits, signal).scan();
    let parsed: unknown;
    try { parsed = JSON.parse(json) as unknown; }
    catch { checkCancellation(signal); throw new DocumentCompositionError("invalidProfile", "JSON fields have invalid types or values"); }
    const manifest = object(parsed, ["schema", "rootID", "entries"]);
    const schema = string(manifest["schema"]);
    if (schema !== "3md-composition-1") throw new DocumentCompositionError("unsupportedProfile", schema);
    const rootID = string(manifest["rootID"]);
    const rawEntries = array(manifest["entries"]);
    if (rawEntries.length > limits.maximumDefinitions) throw new DocumentCompositionError("tooManyDefinitions");
    let total = 0;
    const entries: DocumentEntry[] = [];
    for (const rawEntry of rawEntries) {
      checkCancellation(signal);
      const entry = object(rawEntry, ["id", "source", "references"]);
      const source = string(entry["source"]);
      const bytes = utf8Length(source, signal);
      if (bytes > limits.maximumDefinitionBytes - total) throw new DocumentCompositionError("definitionBytesExceeded");
      total += bytes;
      const data = new TextEncoder().encode(source);
      if (DocumentStorageCodec.isBinary(data)) throw new DocumentCompositionError("invalidProfile", "embedded definitions must be text 3md");
      const references = array(entry["references"]).map((raw): DocumentReference => {
        const reference = object(raw, ["targetID", "attributes"]);
        const rawAttributes = object(reference["attributes"]);
        const attributes: Record<string, string> = Object.create(null);
        for (const [key, value] of Object.entries(rawAttributes)) attributes[key] = string(value);
        return { targetID: string(reference["targetID"]), attributes };
      });
      entries.push({ id: string(entry["id"]), document: DocumentStorageCodec.decode(data, documentLimits, signal), references });
    }
    return new DocumentComposition(rootID, entries, limits, documentLimits, signal);
  }
}
