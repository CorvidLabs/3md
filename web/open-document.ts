// Host helper for the viewer page. The <three-md> element stays a text renderer.
// This module uses the library to turn bytes, a composition profile, or a dropped
// folder into the text the element shows. Rebuild the browser bundle with:
//   bun build ./web/open-document.ts --outfile ./web/assets/open-document.js --format esm --target browser --minify
import {
  parse,
  serialize,
  DocumentCompositionCodec,
  DocumentCompositionError,
  DocumentFileComposition,
  DocumentFileCompositionError,
  DocumentStorageCodec,
  DocumentStorageError,
  type Document,
  type DocumentComposition,
  type DocumentFileSource,
} from "../js/src/index.ts";

export { indexLines, kind2Bytes, packDocuments, searchRank, searchScore, sectionsToDocument } from "./gather.ts";
export { loadGitHubPoint, parseGitHubLocator } from "./github-source.ts";

export class OpenDocumentError extends Error {
  public readonly code: string;

  public constructor(code: string, message: string) {
    super(message);
    this.name = "OpenDocumentError";
    this.code = code;
  }
}

export interface OpenedPiece {
  readonly id: string;
  readonly label: string;
  readonly text: string;
}

export interface OpenedDocument {
  readonly text: string;
  readonly activeId: string | null;
  readonly pieces: readonly OpenedPiece[];
  readonly container: "text" | "kind1" | "kind2";
  readonly note: string | null;
}

function asOpenError(error: unknown): OpenDocumentError {
  if (error instanceof OpenDocumentError) return error;
  if (error instanceof DocumentStorageError && error.code === "compressionUnavailable") {
    return new OpenDocumentError(
      "compressionUnavailable",
      "Apple LZFSE is not available in this viewer. Open the text file or the uncompressed binary.",
    );
  }
  if (
    error instanceof DocumentStorageError
    || error instanceof DocumentFileCompositionError
    || error instanceof DocumentCompositionError
  ) {
    return new OpenDocumentError(error.code, error.message);
  }
  const parsed = error as { code?: unknown; message?: unknown };
  const code = typeof parsed.code === "string" ? parsed.code : "invalidText";
  const message = typeof parsed.message === "string" ? parsed.message : "Could not read that document.";
  return new OpenDocumentError(code, message);
}

function normalizePath(path: string): string {
  return path.replaceAll("\\", "/").replace(/^\.\/+/, "").replace(/^\/+/, "");
}

function openedFromComposition(
  composition: DocumentComposition,
  container: OpenedDocument["container"],
  pathById: ReadonlyMap<string, string>,
  profileText: string | null,
  notePrefix: string | null,
): OpenedDocument {
  const entries: OpenedPiece[] = composition.entries.map((entry) => {
    const path = pathById.get(entry.id);
    const title = entry.document.title;
    const label = path ?? (title && title.length > 0 ? title : entry.id);
    return { id: entry.id, label, text: serialize(entry.document) };
  });
  const root = entries.find((piece) => piece.id === composition.rootID);
  if (!root) throw new OpenDocumentError("missingRoot", "That composition has no root document.");
  const pieces = profileText === null
    ? entries
    : [{ id: "profile", label: "profile source", text: profileText }, ...entries];
  const extra = pieces.length > 1 ? `Showing ${root.label}. ${entries.length} documents are in this open.` : null;
  const note = [notePrefix, extra].filter((part) => part !== null && part.length > 0).join(" ");
  return {
    text: root.text,
    activeId: root.id,
    pieces: pieces.length > 1 ? pieces : [],
    container,
    note: note.length > 0 ? note : null,
  };
}

function fromParsed(document: Document, container: OpenedDocument["container"], profileText: string | null, notePrefix: string | null): OpenedDocument {
  if (!DocumentCompositionCodec.isComposition(document)) {
    const text = container === "text" && profileText !== null ? profileText : serialize(document);
    return { text, activeId: null, pieces: [], container, note: notePrefix };
  }
  return openedFromComposition(DocumentCompositionCodec.decode(document), container, new Map(), profileText, notePrefix);
}

/** Open readable text. A composition profile shows its root document. */
export function openText(text: string): OpenedDocument {
  try {
    return fromParsed(parse(text), "text", text, null);
  } catch (error) {
    throw asOpenError(error);
  }
}

/** Open text or an uncompressed binary container. Kind 1 and kind 2 both decode. */
export function openBytes(data: Uint8Array): OpenedDocument {
  try {
    if (!DocumentStorageCodec.isBinary(data)) return openText(new TextDecoder().decode(data));
    const info = DocumentStorageCodec.containerInfo(data);
    if (info !== null && info.compression !== 0) {
      throw new OpenDocumentError(
        "compressionUnavailable",
        "Apple LZFSE is not available in this viewer. Open the text file or the uncompressed binary.",
      );
    }
    const document = DocumentStorageCodec.decode(data);
    const container = info?.payloadKind === 2 ? "kind2" : "kind1";
    const kind = container === "kind2" ? "kind 2" : "kind 1";
    return fromParsed(document, container, null, `Decoded uncompressed ${kind} binary.`);
  } catch (error) {
    throw asOpenError(error);
  }
}

function rootFile(files: readonly DocumentFileSource[]): DocumentFileSource | null {
  return files.find((file) => file.path === "scene.3md" || file.path.endsWith("/scene.3md"))
    ?? files.find((file) => file.path.toLowerCase().endsWith(".3md"))
    ?? files[0]
    ?? null;
}

/**
 * Open one file, or a folder of caller-supplied files. Linked `3md-files`
 * ledgers resolve only from the bytes in `files`.
 */
export function openFileSet(files: readonly DocumentFileSource[]): OpenedDocument {
  const documents = files
    .map((file) => ({ path: normalizePath(file.path), data: file.data }))
    .filter((file) => /\.(3md|3mdb)$/i.test(file.path));
  if (documents.length === 0) throw new OpenDocumentError("empty", "Open a .3md or .3mdb file.");
  const only = documents[0];
  if (documents.length === 1 && only) return openBytes(only.data);
  const root = rootFile(documents);
  if (!root) throw new OpenDocumentError("empty", "Open a .3md or .3mdb file.");
  try {
    const resolved = DocumentFileComposition.resolve(root.path, documents);
    const pathById = new Map<string, string>();
    for (const [path, id] of Object.entries(resolved.fileRootIDs)) pathById.set(id, path);
    return openedFromComposition(resolved.composition, "text", pathById, null, null);
  } catch (error) {
    if (error instanceof DocumentFileCompositionError || error instanceof DocumentCompositionError) {
      const opened = openBytes(root.data);
      return { ...opened, note: `Opened ${root.path}. Linked files in this drop were not applied (${error.message}).` };
    }
    throw asOpenError(error);
  }
}
