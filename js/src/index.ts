// @corvidlabs/threemd
//
// A faithful TypeScript port of the Swift ThreeMD parser and serializer.
// The 3md format is Markdown extended along a single free Z axis: a document is
// a required frontmatter block, an optional Markdown preamble, and zero or more
// planes introduced by `@plane` directives.
//
// This module mirrors the canonical Swift implementation in Sources/ThreeMD
// exactly, including its error behavior. The cross-language conformance vectors
// in conformance/ pin that behavior down.

// MARK: - Types

/**
 * The meaning assigned to a 3md document's third (Z) axis.
 *
 * The value is always trimmed and lowercased, matching the Swift `Axis` type.
 * Any string is permitted; common values are `time`, `depth`, `layer`,
 * `frame`, and `space`.
 */
export type Axis = string;

/**
 * A single slice of a 3md document positioned along the Z axis.
 *
 * `z` is required and orders planes along the document's axis. `x` and `y` are
 * optional in-plane offsets. Any directive attributes other than `z`, `x`, `y`,
 * and `label` are preserved in `attributes`.
 */
export interface Plane {
  /** Position along the document's Z axis. */
  readonly z: number;
  /** Optional human-readable label, or `null` when absent. */
  readonly label: string | null;
  /** Optional horizontal offset within the plane, or `null` when absent. */
  readonly x: number | null;
  /** Optional vertical offset within the plane, or `null` when absent. */
  readonly y: number | null;
  /** Extra directive attributes that are not `z`, `x`, `y`, or `label`. */
  readonly attributes: Readonly<Record<string, string>>;
  /** The Markdown content of this plane, with surrounding blank lines trimmed. */
  readonly body: string;
}

/**
 * A parsed 3md document: Markdown extended along one free Z axis.
 */
export interface Document {
  /** The declared 3md format version, for example `"0.1"`. */
  readonly version: string;
  /** What the Z axis represents in this document (trimmed, lowercased). */
  readonly axis: Axis;
  /** Optional document title from the frontmatter, or `null`. */
  readonly title: string | null;
  /** Any frontmatter keys other than `3md`, `axis`, and `title`. */
  readonly metadata: Readonly<Record<string, string>>;
  /** Markdown content after the frontmatter but before the first plane, or `null`. */
  readonly preamble: string | null;
  /** The document's planes, in source order. */
  readonly planes: readonly Plane[];
}

// MARK: - Errors

/**
 * The set of error case names a conforming 3md parser must reject with.
 *
 * These mirror the Swift `ParseError` enum cases one to one.
 */
export type ParseErrorCode =
  | "missingFrontmatter"
  | "invalidFrontmatter"
  | "missingVersion"
  | "invalidPlaneDirective"
  | "missingPlanePosition"
  | "duplicatePlane";

/**
 * An error thrown while parsing a 3md document.
 *
 * The `code` property names the canonical Swift `ParseError` case, so callers
 * and the conformance suite can match on it without parsing the message.
 */
export class ParseError extends Error {
  /** The canonical Swift `ParseError` case name. */
  public readonly code: ParseErrorCode;
  /** Optional 1-based line number for directive-related errors. */
  public readonly line: number | undefined;
  /** Optional human-readable detail string. */
  public readonly detail: string | undefined;

  public constructor(code: ParseErrorCode, message: string, line?: number, detail?: string) {
    super(message);
    this.name = "ParseError";
    this.code = code;
    this.line = line;
    this.detail = detail;
    Object.setPrototypeOf(this, ParseError.prototype);
  }
}

// MARK: - Lexing helpers

const RESERVED_PLANE_KEYS: ReadonlySet<string> = new Set(["z", "x", "y", "label"]);

/**
 * Trims leading and trailing space and tab characters, mirroring the Swift
 * `trimmingCharacters(in: .whitespaces)` used throughout the parser. Lines are
 * already split on newlines, so only horizontal whitespace is relevant.
 */
function trimWhitespace(value: string): string {
  return value.replace(/^[ \t]+/, "").replace(/[ \t]+$/, "");
}

/**
 * Returns the first space/tab-delimited token of a line, or the empty string.
 * Mirrors the Swift `firstToken(of:)` helper.
 */
function firstToken(line: string): string {
  for (const token of line.split(/[ \t]+/)) {
    if (token.length > 0) {
      return token;
    }
  }
  return "";
}

/**
 * Splits a directive remainder into tokens, keeping single- or double-quoted
 * spans intact. Mirrors the Swift `tokenize(_:)` helper.
 */
function tokenize(input: string): string[] {
  const tokens: string[] = [];
  let current = "";
  let activeQuote: string | null = null;

  for (const character of input) {
    if (activeQuote !== null) {
      current += character;
      if (character === activeQuote) {
        activeQuote = null;
      }
    } else if (character === '"' || character === "'") {
      activeQuote = character;
      current += character;
    } else if (character === " " || character === "\t") {
      if (current.length > 0) {
        tokens.push(current);
        current = "";
      }
    } else {
      current += character;
    }
  }
  if (current.length > 0) {
    tokens.push(current);
  }
  return tokens;
}

/**
 * Strips a single pair of matching surrounding single or double quotes.
 * Mirrors the Swift `unquote(_:)` helper.
 */
function unquote(value: string): string {
  if (value.length < 2) {
    return value;
  }
  const first = value[0];
  const last = value[value.length - 1];
  if ((first === '"' && last === '"') || (first === "'" && last === "'")) {
    return value.slice(1, -1);
  }
  return value;
}

/**
 * Joins body lines, dropping leading and trailing blank lines. Returns `null`
 * when nothing but whitespace remains. Mirrors the Swift `collapse(_:)` helper,
 * which returns an optional.
 */
function collapse(lines: readonly string[]): string | null {
  let start = 0;
  let end = lines.length;
  while (start < end && trimWhitespace(lines[start] ?? "") === "") {
    start += 1;
  }
  while (end > start && trimWhitespace(lines[end - 1] ?? "") === "") {
    end -= 1;
  }
  if (start >= end) {
    return null;
  }
  return lines.slice(start, end).join("\n");
}

/**
 * Parses a string into a number using the same acceptance rules as Swift's
 * `Double(_ text: String)` initializer for the inputs 3md cares about.
 *
 * Swift accepts optional sign, integer and decimal forms, scientific notation,
 * hex floats (for example `0x1p4`), and the literals `inf`/`infinity`/`nan`
 * (case-insensitive). It rejects empty or whitespace-only strings, thousands
 * separators, and trailing garbage. `Number()` alone is too lenient (for
 * example `Number("")` is `0`), so the input is validated first.
 *
 * @param text The already trimmed, unquoted attribute value.
 * @returns The parsed number, or `null` when the text is not a valid number.
 */
function parseSwiftDouble(text: string): number | null {
  if (text.length === 0) {
    return null;
  }

  const decimalPattern = /^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$/;
  const hexPattern = /^[+-]?0[xX][0-9a-fA-F]*\.?[0-9a-fA-F]*[pP][+-]?\d+$/;
  const specialPattern = /^[+-]?(inf|infinity|nan)$/i;

  if (specialPattern.test(text)) {
    const lowered = text.toLowerCase();
    if (lowered.endsWith("nan")) {
      return NaN;
    }
    return lowered.startsWith("-") ? -Infinity : Infinity;
  }

  if (hexPattern.test(text)) {
    const value = Number(text);
    return Number.isNaN(value) ? null : value;
  }

  if (!decimalPattern.test(text)) {
    return null;
  }

  const value = Number(text);
  return Number.isNaN(value) ? null : value;
}

// MARK: - Parser internals

interface FrontmatterField {
  readonly key: string;
  readonly value: string;
}

interface ExtractedFrontmatter {
  readonly fields: FrontmatterField[];
  /** 1-based line number of the first body line, after the closing `---`. */
  readonly bodyStartLine: number;
  /** The remaining body lines after the closing fence. */
  readonly body: string[];
}

interface PendingPlane {
  readonly lineNumber: number;
  readonly attributes: Record<string, string>;
  readonly bodyLines: string[];
}

function extractFrontmatter(lines: readonly string[]): ExtractedFrontmatter {
  let index = 0;
  while (index < lines.length && trimWhitespace(lines[index] ?? "") === "") {
    index += 1;
  }
  if (index >= lines.length || trimWhitespace(lines[index] ?? "") !== "---") {
    throw new ParseError(
      "missingFrontmatter",
      "3md documents must begin with a '---' frontmatter block.",
    );
  }

  index += 1;
  const fields: FrontmatterField[] = [];

  while (index < lines.length) {
    const trimmed = trimWhitespace(lines[index] ?? "");
    if (trimmed === "---") {
      const bodyStart = index + 1;
      const body = bodyStart < lines.length ? lines.slice(bodyStart) : [];
      return { fields, bodyStartLine: index + 2, body };
    }
    if (trimmed !== "" && !trimmed.startsWith("#")) {
      const separator = trimmed.indexOf(":");
      if (separator < 0) {
        throw new ParseError(
          "invalidFrontmatter",
          `Invalid frontmatter: expected 'key: value', found '${trimmed}'`,
          undefined,
          `expected 'key: value', found '${trimmed}'`,
        );
      }
      const key = trimWhitespace(trimmed.slice(0, separator));
      const raw = trimWhitespace(trimmed.slice(separator + 1));
      fields.push({ key, value: unquote(raw) });
    }
    index += 1;
  }

  throw new ParseError(
    "invalidFrontmatter",
    "Invalid frontmatter: frontmatter block was not closed with '---'",
    undefined,
    "frontmatter block was not closed with '---'",
  );
}

interface InterpretedFrontmatter {
  readonly version: string;
  readonly axis: Axis;
  readonly title: string | null;
  readonly metadata: Record<string, string>;
}

function interpretFrontmatter(fields: readonly FrontmatterField[]): InterpretedFrontmatter {
  let version: string | null = null;
  let axis: Axis = "layer";
  let title: string | null = null;
  const metadata: Record<string, string> = {};

  for (const field of fields) {
    switch (field.key.toLowerCase()) {
      case "3md":
        version = field.value;
        break;
      case "axis":
        axis = trimWhitespace(field.value).toLowerCase();
        break;
      case "title":
        title = field.value;
        break;
      default:
        metadata[field.key] = field.value;
        break;
    }
  }

  if (version === null || version.length === 0) {
    throw new ParseError(
      "missingVersion",
      "Frontmatter is missing the required '3md' version key.",
    );
  }
  return { version, axis, title, metadata };
}

function parseDirective(trimmed: string, line: number): Record<string, string> {
  const remainder = trimWhitespace(trimmed.slice("@plane".length));
  const result: Record<string, string> = {};

  for (const token of tokenize(remainder)) {
    const separator = token.indexOf("=");
    if (separator < 0) {
      throw new ParseError(
        "invalidPlaneDirective",
        `Invalid @plane directive on line ${line}: expected key=value, found '${token}'`,
        line,
        `expected key=value, found '${token}'`,
      );
    }
    const key = trimWhitespace(token.slice(0, separator)).toLowerCase();
    const value = unquote(trimWhitespace(token.slice(separator + 1)));
    if (key.length === 0) {
      throw new ParseError(
        "invalidPlaneDirective",
        `Invalid @plane directive on line ${line}: empty attribute key in '${token}'`,
        line,
        `empty attribute key in '${token}'`,
      );
    }
    result[key] = value;
  }

  return result;
}

function optionalDouble(
  value: string | undefined,
  key: string,
  line: number,
): number | null {
  if (value === undefined) {
    return null;
  }
  const parsed = parseSwiftDouble(value);
  if (parsed === null) {
    throw new ParseError(
      "invalidPlaneDirective",
      `Invalid @plane directive on line ${line}: ${key} must be a number, found '${value}'`,
      line,
      `${key} must be a number, found '${value}'`,
    );
  }
  return parsed;
}

function makePlane(pending: PendingPlane): Plane {
  const attributes = pending.attributes;
  const line = pending.lineNumber;

  const zRaw = attributes["z"];
  if (zRaw === undefined) {
    throw new ParseError(
      "missingPlanePosition",
      `The @plane directive on line ${line} is missing a 'z' position.`,
      line,
    );
  }
  const z = parseSwiftDouble(zRaw);
  if (z === null) {
    throw new ParseError(
      "invalidPlaneDirective",
      `Invalid @plane directive on line ${line}: z must be a number, found '${zRaw}'`,
      line,
      `z must be a number, found '${zRaw}'`,
    );
  }

  const x = optionalDouble(attributes["x"], "x", line);
  const y = optionalDouble(attributes["y"], "y", line);
  const labelRaw = attributes["label"];
  const label = labelRaw === undefined ? null : labelRaw;

  const extras: Record<string, string> = {};
  for (const attributeKey of Object.keys(attributes)) {
    if (!RESERVED_PLANE_KEYS.has(attributeKey)) {
      const attributeValue = attributes[attributeKey];
      if (attributeValue !== undefined) {
        extras[attributeKey] = attributeValue;
      }
    }
  }

  const body = collapse(pending.bodyLines) ?? "";
  return { z, label, x, y, attributes: extras, body };
}

interface ParsedBody {
  readonly preamble: string | null;
  readonly planes: Plane[];
}

function parseBody(lines: readonly string[], bodyStartLine: number): ParsedBody {
  const seenZ = new Set<number>();
  const planes: Plane[] = [];
  let pending: PendingPlane | null = null;
  const preambleLines: string[] = [];

  const flushPending = (): void => {
    if (pending === null) {
      return;
    }
    const plane = makePlane(pending);
    if (seenZ.has(plane.z)) {
      throw new ParseError(
        "duplicatePlane",
        `Two planes share the same z position: ${plane.z}`,
        undefined,
        String(plane.z),
      );
    }
    seenZ.add(plane.z);
    planes.push(plane);
  };

  lines.forEach((raw, offset) => {
    const lineNumber = bodyStartLine + offset;
    const trimmed = trimWhitespace(raw);

    if (firstToken(trimmed) !== "@plane") {
      if (pending !== null) {
        pending.bodyLines.push(raw);
      } else {
        preambleLines.push(raw);
      }
      return;
    }

    flushPending();
    const attributes = parseDirective(trimmed, lineNumber);
    pending = { lineNumber, attributes, bodyLines: [] };
  });

  flushPending();

  const preamble = collapse(preambleLines);

  if (planes.length === 0) {
    if (preamble === null) {
      return { preamble: null, planes: [] };
    }
    return {
      preamble: null,
      planes: [{ z: 0, label: null, x: null, y: null, attributes: {}, body: preamble }],
    };
  }
  return { preamble, planes };
}

// MARK: - Public API

/**
 * Parses 3md source text into a {@link Document}.
 *
 * Frontmatter is required and must declare a `3md` version key (the format's
 * magic marker). Planes are introduced by `@plane` directives carrying
 * `key=value` attributes; the text between directives is plain Markdown. A
 * document with no directives parses as a single plane at `z = 0`.
 *
 * @param source The full contents of a `.3md` file.
 * @returns The parsed document.
 * @throws {ParseError} When the source is malformed. The error's `code`
 *   property names the canonical case (`missingFrontmatter`,
 *   `invalidFrontmatter`, `missingVersion`, `missingPlanePosition`,
 *   `invalidPlaneDirective`, or `duplicatePlane`).
 */
export function parse(source: string): Document {
  const normalized = source.replace(/\r\n/g, "\n");
  const lines = normalized.split("\n");

  const frontmatter = extractFrontmatter(lines);
  const interpreted = interpretFrontmatter(frontmatter.fields);
  const { preamble, planes } = parseBody(frontmatter.body, frontmatter.bodyStartLine);

  return {
    version: interpreted.version,
    axis: interpreted.axis,
    title: interpreted.title,
    metadata: interpreted.metadata,
    preamble,
    planes,
  };
}

/**
 * Formats a number as an integer string when the value is whole and in range,
 * falling back to the default decimal representation otherwise. Mirrors the
 * Swift serializer's `format(_:)` helper.
 */
function formatNumber(value: number): string {
  if (Number.isInteger(value) && Math.abs(value) < 1e15) {
    return String(value);
  }
  return String(value);
}

/**
 * Wraps a value in double quotes when it contains whitespace, is empty, or when
 * `forceQuote` is true. Embedded double quotes are escaped. Mirrors the Swift
 * serializer's `quoteIfNeeded(_:forceQuote:)` helper.
 */
function quoteIfNeeded(value: string, forceQuote = false): string {
  const needsQuote =
    forceQuote || value.includes(" ") || value.includes("\t") || value.length === 0;
  if (!needsQuote) {
    return value;
  }
  return `"${value.replace(/"/g, '\\"')}"`;
}

function frontmatterLines(document: Document): string[] {
  const lines = ["---", `3md: ${document.version}`, `axis: ${document.axis}`];

  if (document.title !== null) {
    lines.push(`title: ${quoteIfNeeded(document.title)}`);
  }

  for (const key of Object.keys(document.metadata).sort()) {
    lines.push(`${key}: ${quoteIfNeeded(document.metadata[key] ?? "")}`);
  }
  lines.push("---");

  return lines;
}

function directiveLine(plane: Plane): string {
  const parts = ["@plane", `z=${formatNumber(plane.z)}`];

  if (plane.label !== null) {
    parts.push(`label=${quoteIfNeeded(plane.label, true)}`);
  }
  if (plane.x !== null) {
    parts.push(`x=${formatNumber(plane.x)}`);
  }
  if (plane.y !== null) {
    parts.push(`y=${formatNumber(plane.y)}`);
  }

  for (const key of Object.keys(plane.attributes).sort()) {
    parts.push(`${key}=${quoteIfNeeded(plane.attributes[key] ?? "", true)}`);
  }

  return parts.join(" ");
}

/**
 * Renders a {@link Document} back into 3md source text.
 *
 * The output round-trips through {@link parse}: parsing serialized text yields
 * an equivalent document for content that does not rely on quote escaping.
 * Mirrors the Swift `Serializer`.
 *
 * @param document The document to render.
 * @returns The serialized `.3md` contents.
 */
export function serialize(document: Document): string {
  const lines = frontmatterLines(document);

  if (document.preamble !== null) {
    lines.push("");
    lines.push(document.preamble);
  }

  for (const plane of document.planes) {
    lines.push("");
    lines.push(directiveLine(plane));
    if (plane.body.length > 0) {
      lines.push(plane.body);
    }
  }

  return lines.join("\n") + "\n";
}
