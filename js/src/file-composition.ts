import type { Document } from "./index.js";
import { DocumentComposition, DocumentCompositionCodec, DocumentCompositionError, DocumentCompositionLimits,
  type DocumentEntry, type DocumentReference } from "./composition.js";
import { checkCancellation, InvalidUnicodeError, utf8Length } from "./portable.js";
import { DocumentDecodeLimits, DocumentStorageCodec } from "./storage.js";

/** Caller-supplied file bytes. The library never reads a path from a filesystem or network. */
export interface DocumentFileSource { readonly path: string; readonly data: Uint8Array; }
export interface DocumentFileReference { readonly glyph: string; readonly source: string; }
export interface DocumentFileCompositionResult {
  readonly rootPath: string;
  readonly composition: DocumentComposition;
  readonly fileRootIDs: Readonly<Record<string, string>>;
  readonly resolvedPaths: readonly string[];
}

// Disconnected embedded entries may discover files without extending the final root graph path.
// Keep recursion independently bounded; caller graph depth applies after entry remapping.
const maximumFileDiscoveryDepth = DocumentCompositionLimits.standard.maximumDepth;
export type DocumentFileCompositionErrorCode = "invalidPath" | "duplicatePath" | "invalidLedger" |
  "invalidGlyph" | "missingFile" | "inputLimit";
export class DocumentFileCompositionError extends Error {
  public readonly code: DocumentFileCompositionErrorCode;
  public readonly detail: string | undefined;
  public constructor(code: DocumentFileCompositionErrorCode, detail?: string) {
    super(`${code}${detail === undefined ? "" : `: ${detail}`}`);
    this.name = "DocumentFileCompositionError"; this.code = code; this.detail = detail;
  }
}

function pathBytes(path: string, remaining: number, signal?: AbortSignal): number {
  checkCancellation(signal);
  if (typeof path !== "string") throw new DocumentFileCompositionError("invalidPath");
  if (path.length > remaining) throw new DocumentFileCompositionError("inputLimit");
  try {
    const bytes = utf8Length(path, signal);
    if (bytes > remaining) throw new DocumentFileCompositionError("inputLimit");
    return bytes;
  } catch (error) {
    checkCancellation(signal);
    if (error instanceof InvalidUnicodeError) throw new DocumentFileCompositionError("invalidPath", path);
    throw error;
  }
}

/** A normalized containing file whose directory boundaries are located once per discovered file. */
interface ContainingFile {
  readonly path: string;
  readonly bytes: number;
  readonly directoryEnds: readonly number[];
}
const projectRoot: ContainingFile = Object.freeze({ path: "", bytes: 0, directoryEnds: Object.freeze([]) });

function containingFile(path: string, bytes: number): ContainingFile {
  const directoryEnds: number[] = [];
  for (let index = path.indexOf("/"); index >= 0; index = path.indexOf("/", index + 1)) directoryEnds.push(index);
  return { path, bytes, directoryEnds };
}

function normalizedPath(source: string, base: ContainingFile, signal?: AbortSignal): string {
  checkCancellation(signal);
  if (source.length === 0 || source.startsWith("/")) throw new DocumentFileCompositionError("invalidPath", source);
  for (let index = 0; index < source.length; index += 1) {
    if (index % 4096 === 0) checkCancellation(signal);
    const unit = source.charCodeAt(index);
    if (unit <= 31 || unit === 127 || unit === 92 || unit === 58) {
      throw new DocumentFileCompositionError("invalidPath", source);
    }
  }
  // One stack: the kept base directory segments followed by the source's own segments.
  let kept = base.directoryEnds.length;
  const segments: string[] = [];
  const normalized = source.normalize("NFC");
  for (const segment of normalized.split("/")) {
    checkCancellation(signal);
    if (segment === "") throw new DocumentFileCompositionError("invalidPath", source);
    if (segment === ".") continue;
    if (segment === "..") {
      if (segments.length > 0) segments.pop();
      else if (kept > 0) kept -= 1;
      else throw new DocumentFileCompositionError("invalidPath", source);
    } else segments.push(segment);
  }
  if (kept === 0 && segments.length === 0) throw new DocumentFileCompositionError("invalidPath", source);
  const prefix = kept > 0 ? base.path.slice(0, base.directoryEnds[kept - 1]) : "";
  if (segments.length === 0) return prefix;
  return prefix === "" ? segments.join("/") : `${prefix}/${segments.join("/")}`;
}

/** Resolves one ledger reference against an owner normalized once, charging the same record bound as resolvePath. */
function resolveReference(source: string, owner: ContainingFile, signal?: AbortSignal): string {
  checkCancellation(signal);
  const maximum = DocumentDecodeLimits.standard.maximumRecordBytes;
  const remaining = maximum - pathBytes(source, maximum, signal);
  if (owner.bytes > remaining) throw new DocumentFileCompositionError("inputLimit");
  return normalizedPath(source, owner, signal);
}

function scalarCompare(left: string, right: string, signal?: AbortSignal): number {
  let a = 0; let b = 0;
  while (a < left.length && b < right.length) {
    if (a % 4096 === 0 || b % 4096 === 0) checkCancellation(signal);
    const x = left.codePointAt(a) ?? 0; const y = right.codePointAt(b) ?? 0;
    if (x !== y) return x < y ? -1 : 1;
    a += x > 0xffff ? 2 : 1; b += y > 0xffff ? 2 : 1;
  }
  return a < left.length ? 1 : b < right.length ? -1 : 0;
}

/** A flat JSON object of strings, scanned before reconstruction so duplicate spellings cannot disappear. */
class LedgerScanner {
  private index = 0;
  public constructor(private readonly source: string, private readonly signal?: AbortSignal) {}
  private invalid(): never { throw new DocumentFileCompositionError("invalidLedger"); }
  private whitespace(): void {
    while (this.index < this.source.length && " \t\r\n".includes(this.source[this.index] ?? "")) {
      if (this.index % 4096 === 0) checkCancellation(this.signal);
      this.index += 1;
    }
  }
  private consume(value: string): boolean {
    if (this.source[this.index] !== value) return false;
    this.index += 1; return true;
  }
  private string(): string {
    if (!this.consume('"')) this.invalid();
    const start = this.index - 1;
    while (this.index < this.source.length) {
      if (this.index % 4096 === 0) checkCancellation(this.signal);
      const unit = this.source.charCodeAt(this.index); this.index += 1;
      if (unit === 34) {
        try {
          const value = JSON.parse(this.source.slice(start, this.index)) as string;
          utf8Length(value, this.signal);
          return value;
        } catch { checkCancellation(this.signal); return this.invalid(); }
      }
      if (unit < 32) this.invalid();
      if (unit === 92) {
        const escape = this.source[this.index]; this.index += 1;
        if (escape === "u") {
          if (!/^[0-9a-fA-F]{4}$/.test(this.source.slice(this.index, this.index + 4))) this.invalid();
          this.index += 4;
        } else if (escape === undefined || !'"\\/bfnrt'.includes(escape)) this.invalid();
      }
    }
    return this.invalid();
  }
  public scan(): DocumentFileReference[] {
    const references: DocumentFileReference[] = [];
    const keys = new Set<string>();
    this.whitespace(); if (!this.consume("{")) this.invalid(); this.whitespace();
    if (!this.consume("}")) {
      while (true) {
        const glyph = this.string();
        if (glyph.length !== 1 || glyph.charCodeAt(0) < 33 || glyph.charCodeAt(0) > 126) {
          throw new DocumentFileCompositionError("invalidGlyph", glyph);
        }
        if (keys.has(glyph)) this.invalid();
        keys.add(glyph);
        this.whitespace(); if (!this.consume(":")) this.invalid(); this.whitespace();
        const source = this.string(); references.push({ glyph, source });
        this.whitespace();
        if (this.consume("}")) break;
        if (!this.consume(",")) this.invalid(); this.whitespace();
      }
    }
    this.whitespace(); if (this.index !== this.source.length) this.invalid();
    return references.sort((a, b) => a.glyph < b.glyph ? -1 : a.glyph > b.glyph ? 1 : 0);
  }
}

interface DiscoveredFile {
  readonly rootID: string;
  readonly entries: readonly DocumentEntry[];
  readonly links: ReadonlyMap<string, readonly { readonly glyph: string; readonly path: string }[]>;
  readonly depth: number;
}

/** Explicitly bundles reachable caller-supplied files into the existing self-contained composition profile. */
export class DocumentFileComposition {
  public static ledger(document: Document, signal?: AbortSignal): readonly DocumentFileReference[] {
    checkCancellation(signal);
    const value = document.metadata["3md-files"];
    if (value === undefined) return Object.freeze([]);
    if (typeof value !== "string") throw new DocumentFileCompositionError("invalidLedger");
    const maximum = DocumentDecodeLimits.standard.maximumRecordBytes;
    if (value.length > maximum) throw new DocumentFileCompositionError("inputLimit");
    try {
      if (utf8Length(value, signal) > maximum) throw new DocumentFileCompositionError("inputLimit");
    } catch (error) {
      checkCancellation(signal);
      if (error instanceof InvalidUnicodeError) throw new DocumentFileCompositionError("invalidLedger");
      throw error;
    }
    return Object.freeze(new LedgerScanner(value, signal).scan().map((reference) => Object.freeze(reference)));
  }

  public static resolvePath(source: string, relativeTo?: string, signal?: AbortSignal): string {
    checkCancellation(signal);
    let remaining = DocumentDecodeLimits.standard.maximumRecordBytes;
    remaining -= pathBytes(source, remaining, signal);
    if (relativeTo === undefined) return normalizedPath(source, projectRoot, signal);
    const ownerBytes = pathBytes(relativeTo, remaining, signal);
    return normalizedPath(source, containingFile(normalizedPath(relativeTo, projectRoot, signal), ownerBytes), signal);
  }

  public static resolve(rootPath: string, sources: readonly DocumentFileSource[],
    limits = DocumentCompositionLimits.standard, documentLimits = DocumentDecodeLimits.standard,
    signal?: AbortSignal): DocumentFileCompositionResult {
    checkCancellation(signal);
    limits = new DocumentCompositionLimits(limits); documentLimits = new DocumentDecodeLimits(documentLimits);
    if (sources.length > limits.maximumDefinitions) throw new DocumentFileCompositionError("inputLimit");
    let pathBudget = limits.maximumProfileBytes;
    pathBudget -= pathBytes(rootPath, pathBudget, signal);
    for (const source of sources) pathBudget -= pathBytes(source.path, pathBudget, signal);
    const root = normalizedPath(rootPath, projectRoot, signal);
    const index = new Map<string, DocumentFileSource>();
    for (const source of sources) {
      checkCancellation(signal);
      const path = normalizedPath(source.path, projectRoot, signal);
      if (index.has(path)) throw new DocumentFileCompositionError("duplicatePath", path);
      index.set(path, source);
    }
    const files = new Map<string, DiscoveredFile>();
    const active = new Set<string>();
    let encodedBytes = 0; let definitions = 0; let references = 0;
    const visit = (path: string, activeDepth: number): DiscoveredFile => {
      checkCancellation(signal);
      if (active.has(path)) throw new DocumentCompositionError("cycle", path);
      const prior = files.get(path);
      if (prior !== undefined) {
        if (activeDepth >= maximumFileDiscoveryDepth || prior.depth > maximumFileDiscoveryDepth - activeDepth) {
          throw new DocumentCompositionError("depthExceeded");
        }
        return prior;
      }
      if (activeDepth >= maximumFileDiscoveryDepth) throw new DocumentCompositionError("depthExceeded");
      const source = index.get(path);
      if (source === undefined) throw new DocumentFileCompositionError("missingFile", path);
      if (source.data.byteLength > limits.maximumProfileBytes - encodedBytes) throw new DocumentFileCompositionError("inputLimit");
      encodedBytes += source.data.byteLength;
      const outerLimits = new DocumentDecodeLimits({ maximumEncodedBytes: limits.maximumProfileBytes,
        maximumDecodedBytes: limits.maximumProfileBytes, maximumRecordBytes: limits.maximumProfileBytes });
      let document = DocumentStorageCodec.decode(source.data, outerLimits, signal);
      const composition = DocumentCompositionCodec.isComposition(document)
        ? DocumentCompositionCodec.decode(document, limits, documentLimits, signal) : undefined;
      if (composition === undefined) document = DocumentStorageCodec.decode(source.data, documentLimits, signal);
      const entries = composition?.entries ?? [{ id: "root", document, references: [] }];
      if (entries.length > limits.maximumDefinitions - definitions) throw new DocumentCompositionError("tooManyDefinitions");
      definitions += entries.length;
      active.add(path);
      const links = new Map<string, { glyph: string; path: string }[]>();
      let depth = 1;
      const owner = containingFile(path, utf8Length(path, signal));
      for (const entry of [...entries].sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0)) {
        checkCancellation(signal);
        const ledger = DocumentFileComposition.ledger(entry.document, signal);
        const count = entry.references.length + ledger.length;
        if (count > limits.maximumReferences - references) throw new DocumentCompositionError("tooManyReferences");
        references += count;
        const resolved: { glyph: string; path: string }[] = [];
        for (const reference of ledger) {
          checkCancellation(signal);
          const childPath = resolveReference(reference.source, owner, signal);
          const child = visit(childPath, activeDepth + 1);
          depth = Math.max(depth, child.depth + 1);
          if (depth > maximumFileDiscoveryDepth) throw new DocumentCompositionError("depthExceeded");
          resolved.push({ glyph: reference.glyph, path: childPath });
        }
        links.set(entry.id, resolved);
      }
      const result = { rootID: composition?.rootID ?? "root", entries, links, depth };
      files.set(path, result); active.delete(path); return result;
    };
    visit(root, 0);
    const paths = [...files.keys()].sort((a, b) => scalarCompare(a, b, signal));
    const assigned = new Map<string, Map<string, string>>();
    const fileRootIDs: Record<string, string> = Object.create(null);
    let ordinal = 0;
    for (const path of paths) {
      checkCancellation(signal);
      const file = files.get(path)!;
      const IDs = new Map<string, string>();
      for (const entry of [...file.entries].sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0)) {
        IDs.set(entry.id, `file-${String(ordinal).padStart(6, "0")}`); ordinal += 1;
      }
      assigned.set(path, IDs); fileRootIDs[path] = IDs.get(file.rootID)!;
    }
    const bundled: DocumentEntry[] = [];
    for (const path of paths) {
      const file = files.get(path)!; const IDs = assigned.get(path)!;
      for (const entry of file.entries) {
        checkCancellation(signal);
        const metadata: Record<string, string> = Object.create(null);
        for (const [key, value] of Object.entries(entry.document.metadata)) if (key !== "3md-files") metadata[key] = value;
        const edges: DocumentReference[] = entry.references.map((reference) => ({
          targetID: IDs.get(reference.targetID)!, attributes: reference.attributes,
        }));
        for (const reference of file.links.get(entry.id) ?? []) {
          checkCancellation(signal);
          edges.push({ targetID: fileRootIDs[reference.path]!, attributes: { glyph: reference.glyph, "source-file": reference.path } });
        }
        bundled.push({ id: IDs.get(entry.id)!, document: { ...entry.document, metadata }, references: edges });
      }
    }
    const composition = new DocumentComposition(fileRootIDs[root]!, bundled, limits, documentLimits, signal);
    // Profile bounds include the eventual sharing envelope, not only the encoded source intake.
    DocumentCompositionCodec.encode(composition, limits, documentLimits, signal);
    checkCancellation(signal);
    return Object.freeze({ rootPath: root, composition, fileRootIDs: Object.freeze(fileRootIDs), resolvedPaths: Object.freeze(paths) });
  }
}
