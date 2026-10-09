// Turn Markdown, loose files, and an open document into one searchable 3md.
// The <three-md> element stays a text renderer. Rebuild with open-document.ts.
import {
  parse,
  DocumentStorageCodec,
  DocumentStorageFormat,
  type Plane,
} from "../js/src/index.ts";

export interface GatheredFile {
  readonly path: string;
  readonly text: string;
}

export interface GatheredSection {
  readonly label: string;
  readonly body: string;
}

export interface LineHit {
  readonly kind: "line";
  readonly path: string;
  readonly label: string;
  readonly meta: string;
  readonly text: string;
  readonly planeIndex: number;
}

/** One searchable row for every non-empty line. A 3md line remembers its plane. */
export function indexLines(path: string, text: string): LineHit[] {
  const planes = planesOf(text);
  if (!planes) {
    return text.split(/\r\n|\n|\r/).flatMap((line, index) => {
      const trimmed = line.trim();
      if (!trimmed) return [];
      return [{
        kind: "line" as const,
        path,
        label: trimmed.slice(0, 80),
        meta: `${path} · line ${index + 1}`,
        text,
        planeIndex: 0,
      }];
    });
  }
  const hits: LineHit[] = [];
  planes.forEach((plane, planeIndex) => {
    const name = plane.label || `z=${plane.z}`;
    const lines = [name, ...plane.body.split(/\r\n|\n|\r/)];
    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed) continue;
      hits.push({
        kind: "line",
        path,
        label: trimmed.slice(0, 80),
        meta: `${path} · ${name}`,
        text,
        planeIndex,
      });
    }
  });
  return hits;
}

/** Higher is a better match. A name that ends with the query ranks above a fuzzy hit. */
export function searchRank(query: string, label: string, meta: string): number | null {
  const score = searchScore(query, `${label} ${meta}`);
  if (score === null) return null;
  const needle = query.trim().toLowerCase();
  let bonus = 0;
  if (meta.toLowerCase().endsWith(needle)) bonus += 800;
  if (label.toLowerCase() === needle) bonus += 800;
  return score + bonus;
}

/** Higher is a better match. A typed substring always beats a fuzzy hit. */
export function searchScore(query: string, text: string): number | null {
  const needle = query.trim().toLowerCase();
  const haystack = text.toLowerCase();
  if (!needle || !haystack) return null;
  const at = haystack.indexOf(needle);
  if (at >= 0) return 2000 - at;
  let cursor = 0;
  let previous = -2;
  let score = 0;
  for (const character of needle) {
    const found = haystack.indexOf(character, cursor);
    if (found < 0) return null;
    score += found === previous + 1 ? 5 : 1;
    previous = found;
    cursor = found + 1;
  }
  return score;
}

/** Markdown headings become planes. Text before the first heading stays the preamble. */
export function sectionsToDocument(markdown: string, sourceName?: string): string {
  const split = markdownSections(markdown);
  const title = fileStem(sourceName) || split.sections[0]?.label || "Document";
  return emitDocument(title, "section", split.sections, split.preamble);
}

/**
 * One text document. A `.3md` file keeps its planes. Anything else is split on
 * Markdown headings. Labels are prefixed with the file name.
 */
export function packDocuments(files: readonly GatheredFile[]): string {
  const sections: GatheredSection[] = [];
  const ordered = [...files].sort((left, right) => left.path.localeCompare(right.path));
  for (const file of ordered) {
    const stem = fileStem(file.path) || file.path;
    const planes = planesOf(file.text);
    if (planes) {
      for (const plane of planes) {
        sections.push({
          label: planes.length === 1 ? stem : `${stem} / ${plane.label ?? `z=${plane.z}`}`,
          body: plane.body,
        });
      }
      continue;
    }
    const split = markdownSections(file.text);
    if (split.preamble) sections.push({ label: `${stem} / opening`, body: split.preamble });
    for (const section of split.sections) {
      sections.push({ label: `${stem} / ${section.label}`, body: section.body });
    }
  }
  if (!sections.length) sections.push({ label: "Documents", body: "" });
  return emitDocument("Documents", "doc", sections, null);
}

/** Uncompressed kind 2 bytes for the text the editor is showing. */
export function kind2Bytes(text: string): Uint8Array {
  return DocumentStorageCodec.encode(parse(text), DocumentStorageFormat.binary());
}

function planesOf(text: string): readonly Plane[] | null {
  try {
    const document = parse(text);
    return document.planes.length ? document.planes : null;
  } catch {
    return null;
  }
}

function markdownSections(markdown: string): { preamble: string | null; sections: GatheredSection[] } {
  const lines = markdown.replace(/^\uFEFF/, "").split(/\r\n|\n|\r/);
  const intro: string[] = [];
  const sections: { label: string; lines: string[] }[] = [];
  let fence: "```" | "~~~" | null = null;
  let current: { label: string; lines: string[] } | null = null;
  for (const line of lines) {
    const trimmed = line.trim();
    if (fence) {
      if (trimmed.startsWith(fence)) fence = null;
      (current ? current.lines : intro).push(line);
      continue;
    }
    if (trimmed.startsWith("```") || trimmed.startsWith("~~~")) {
      fence = trimmed.startsWith("```") ? "```" : "~~~";
      (current ? current.lines : intro).push(line);
      continue;
    }
    const heading = /^(#{1,6})[ \t]+(.+?)\s*$/.exec(line);
    if (heading) {
      const label = heading[2]?.trim() || "section";
      current = { label, lines: [line] };
      sections.push(current);
      continue;
    }
    (current ? current.lines : intro).push(line);
  }
  const preamble = trimEdges(intro).join("\n");
  if (!sections.length) {
    return { preamble: null, sections: [{ label: "Document", body: preamble }] };
  }
  return {
    preamble: preamble || null,
    sections: sections.map((section) => ({ label: section.label, body: trimEdges(section.lines).join("\n") })),
  };
}

function emitDocument(title: string, axis: string, sections: readonly GatheredSection[], preamble: string | null): string {
  const lines = [
    "---",
    "3md: \"1.0\"",
    `axis: ${quote(axis)}`,
    `title: ${quote(title)}`,
    "---",
    "",
  ];
  if (preamble && preamble.trim()) lines.push(preamble.trim(), "");
  sections.forEach((section, index) => {
    lines.push(`@plane z=${index} label=${quote(section.label)}`);
    if (section.body) lines.push(section.body);
    lines.push("");
  });
  return lines.join("\n").replace(/\n+$/, "\n");
}

function trimEdges(lines: readonly string[]): string[] {
  let start = 0;
  let end = lines.length;
  while (start < end && lines[start]?.trim() === "") start += 1;
  while (end > start && lines[end - 1]?.trim() === "") end -= 1;
  return lines.slice(start, end);
}

function fileStem(path: string | undefined): string {
  if (!path) return "";
  const base = path.split(/[/\\]/).pop() ?? path;
  return base.replace(/\.(3md|md|txt)$/i, "").trim();
}

function quote(value: string): string {
  return JSON.stringify(value);
}
