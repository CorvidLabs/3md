---
module: ThreeMDViewer
version: 4
status: active
files:
  - web/viewer.html
  - web/gather.ts
  - web/github-source.ts
  - web/open-document.ts
  - web/assets/open-document.js
  - web/gather.test.ts
  - web/github-source.test.ts
  - web/open-document.test.ts
  - uitests/viewer.spec.mjs

db_tables: []
depends_on:
  - ThreeMD
  - ThreeMDElement
---

# ThreeMDViewer

## Purpose

ThreeMDViewer is the hosted and local viewer page. Files stay on the left. Edit, the plane preview, and Cubes share the panel beside them. One is visible at a time, and Edit is the default. Below 900px, Files and the document take turns. Cubes draws a fenced character grid as translucent cubes. The page opens a public GitHub repo, folder, or file, or a file or folder from this computer. Search reads every opened line and opens that plane. Markdown headings become planes. Opened files pack into one text document, and that document downloads as uncompressed kind 2.

The `<three-md>` element stays a text renderer. Decode, composition, linked folders, GitHub fetch, search, sections, pack, and kind 2 download belong to this page. The ThreeMD library stays free of filesystem and network I/O. Human intent for this page is VIEWER-6 in `hi/tools.md`.

## Public API

### Page

| Name | Description |
|------|-------------|
| `viewer.html` | Files on the left. Edit and Preview share one panel and switch. The live view is the `<three-md>` element. The point field takes a public GitHub locator. Open file, open folder, and drop read local bytes. |
| `open-document.js` | The browser bundle built from `web/open-document.ts`. The page imports it. The element bundle stays `web/assets/three-md.js`. |

### Exported functions

| Function | Parameters | Returns | Description |
|----------|-----------|---------|-------------|
| `parseGitHubLocator` | `input: string` | `GitHubPoint` or `null` | Reads a public GitHub URL or an `owner/repo` name. |
| `loadGitHubPoint` | `input: string`, optional `fetchImpl` | `LoadedGitHub` | Fetches the public files under a repo, folder, or file. |
| `indexLines` | `path: string`, `text: string` | `LineHit[]` | One searchable row for every non-empty line. A 3md line remembers its plane. |
| `searchRank` | `query`, `label`, `meta` | `number` or `null` | Ranks a hit. A name that ends with the query ranks above a fuzzy hit. |
| `searchScore` | `query`, `text` | `number` or `null` | A typed substring outranks a fuzzy subsequence. |
| `sectionsToDocument` | `markdown`, optional `sourceName` | `string` | Markdown headings become planes. |
| `packDocuments` | `files: GatheredFile[]` | `string` | One text document. A `.3md` file keeps its planes. |
| `kind2Bytes` | `text: string` | `Uint8Array` | Uncompressed kind 2 bytes for the text in the editor. |
| `openText` | `text: string` | `OpenedDocument` | Opens text, including a composition profile. |
| `openBytes` | `data: Uint8Array` | `OpenedDocument` | Opens uncompressed kind 1 or kind 2. |
| `openFileSet` | `files` | `OpenedDocument` | Resolves linked files from the supplied bytes. |

### Exported types

| Type | Description |
|------|-------------|
| `GitHubPoint` | `owner`, `repo`, `explicitRef`, `path`, and `kind` of `repo`, `folder`, or `file`. |
| `RemoteFile` | A fetched `path` and `data`. |
| `LoadedGitHub` | `files`, `ref`, `label`, and `truncated`. |
| `LineHit` | `kind: "line"`, `path`, `label`, `meta`, `text`, and `planeIndex`. |
| `GatheredFile` | A `path` and its `text`. |
| `GatheredSection` | A section `label` and `body`. |
| `OpenedDocument` | `text`, `activeId`, `pieces`, `container` (`text`, `kind1`, or `kind2`), and `note`. |
| `OpenedPiece` | `id`, `label`, and `text` for one composition entry. |
| `OpenDocumentError` | An `Error` with a `code`. Apple LZFSE uses `compressionUnavailable`. |

## Invariants

1. Files stay on the left. Edit, the plane preview, and Cubes share one panel, one is visible at a time, and Edit is the default. Below 900px, Files and the document take turns. Choosing Preview renders the live plane view. Choosing Cubes draws a fenced character grid as translucent cubes on a dark stage. The status bar shows the caret, the axis, and the cube count. The element stays a text renderer.
2. A public GitHub locator is accepted only when the host is `github.com`, `www.github.com`, or `raw.githubusercontent.com`, or when the input is an `owner/repo` name. A host string elsewhere in the URL is not a match.
3. A public load skips `node_modules`, keeps at most 400 files, and skips a file larger than 1.5 MB. The line index keeps at most 12,000 rows.
4. Search opens the plane for the chosen line.
5. Markdown headings become planes. Opened files pack into one text document. Kind 2 download writes uncompressed kind 2.
6. Apple LZFSE is refused. The element stays a text renderer. The library stays free of filesystem and network I/O.

## Behavioral Examples

### Scenario: Switch Edit and Preview

- **Given** the page at a desktop width
- **When** the reader chooses Preview, then Edit
- **Then** Preview shows the live plane view and hides the editor, then Edit shows the editor and hides the preview, and files stay visible

### Scenario: Open a public repo

- **Given** the locator `https://github.com/CorvidLabs/3md`
- **When** the page loads that point
- **Then** text and 3md files from the tree are listed, and other files are skipped

### Scenario: Search a line

- **Given** an opened 3md document with more than one plane
- **When** the query matches a line in the second plane
- **Then** the hit carries that plane index and the page opens it

### Scenario: Sections and kind 2

- **Given** a Markdown file with headings
- **When** the page turns it into a document and downloads kind 2
- **Then** each heading is a plane and the bytes decode back through the library

## Error Cases

| Condition | Behavior |
|-----------|----------|
| The input is not a public GitHub repo, folder, or file | `parseGitHubLocator` returns `null`. `loadGitHubPoint` throws and names the expected shape. |
| GitHub returns 403 or 429 | The page says the browser is rate limited. |
| The repo or path is private or missing | The page says it is not public, or it does not exist. |
| The bytes are Apple LZFSE | `openBytes` throws `OpenDocumentError` with code `compressionUnavailable`. |

## Dependencies

### Consumes

| Module | What is used |
|--------|-------------|
| ThreeMD | `parse` and uncompressed kind 2 encode, through `js/src`. |
| ThreeMDElement | The `<three-md>` element renders the text the page has already opened. |

### Consumed By

| Module | What is used |
|--------|-------------|
| Hosted site | `web/viewer.html` is the viewer page. |

## Change Log

| Date | Author | Change |
|------|--------|--------|
| 2026-10-09 | ThreeMDViewer change | Add the page contract for files, source, live view, public GitHub open, line search, sections, pack, and kind 2 download. |
| 2026-10-10 | SpecSync | cover-the-github-style-viewer-page-in-the-spec-the-page-is-files-source-and-the-live-plane-view-it-opens-a-public: Cover the GitHub-style viewer page in the spec. The page is files, source, and the live plane view. It opens a public GitHub repo, folder, or file, or a local file or folder. Search reads every line and opens that plane. Markdown headings become planes. Opened files pack into one text document and download as uncompressed kind 2. The three-md element stays a text renderer. |
| 2026-10-10 | ThreeMDViewer change | Edit and Preview share one panel and switch. Files stay on the left. Below 900px, Files and the document take turns. |
| 2026-10-10 | ThreeMDViewer change | Add a Sculpt-style cube stage beside Edit and Preview, and a status bar for the caret, axis, and cube count. |
