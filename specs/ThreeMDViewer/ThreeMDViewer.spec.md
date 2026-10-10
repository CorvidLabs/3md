---
module: ThreeMDViewer
version: 11
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

ThreeMDViewer is the hosted and local viewer page. Files stay on the left. Edit, the plane preview, and Cubes share the panel beside them. One is visible at a time, and Cubes is the default, inside the window. The opening document is a small sculpture. Below 900px, Files and the document take turns. The page does not offer a render-mode switch and does not autoplay. Preview stays on one plane. Cubes draws a fenced character grid with Sculpt-style lit, translucent glyph fill and visible edges. Gold edges mark the selected Z slice without repainting its fill. The page opens a public GitHub repo, folder, or file, or a file or folder from this computer. Search reads every opened line and opens that plane. Markdown headings become planes. Opened files pack into one text document, and that document downloads as uncompressed kind 2.

The `<three-md>` element stays a text renderer. Decode, composition, linked folders, GitHub fetch, search, sections, pack, and kind 2 download belong to this page. The compact workspace gives the stage room on desktop and phone screens. The document title stays visible, insert tools appear in Edit, and the Document disclosure holds export and conversion actions. Fit, zoom buttons, keyboard camera control, and a scrolling slice row make the cube stage usable without a mouse. A document without a grid offers Preview. The ThreeMD library stays free of filesystem and network I/O. Human intent for this page is VIEWER-6 in `hi/tools.md`.

## Public API

### Page

| Name | Description |
|------|-------------|
| `viewer.html` | Files on the left. Edit, Preview, and Cubes share one panel and switch. Preview is the `<three-md>` element held on one plane. Cubes is a page WebGL2 stage. The point field takes a public GitHub locator. Open file, open folder, and drop read local bytes. |
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

1. Files stay on the left. Edit, the plane preview, and Cubes share one panel, one is visible at a time, and Cubes is the default. The opening document is a small sculpture, and its cubes are inside the window. Below 900px, Files and the document take turns. The page does not switch render modes and does not autoplay. Choosing Preview renders the live plane view and holds it on one plane. Choosing Cubes draws a fenced character grid as lit cubes on a dark GPU stage. Web fill uses 0.5 opacity for visible faces under browser blending, compared with Sculpt’s native 0.35; glyph edges use 0.4, and selected edges use gold rgb(1, 0.79, 0.44) at 0.8. The background is rgb(0.065, 0.085, 0.10). All six cube faces are wound outward, back faces are culled, and faces shared with occupied neighbors are suppressed as in Sculpt. The cell scale is 0.98. X is the column, Y is the row with row 0 toward the top, and Z is the plane index. Orbit, zoom, and selection update camera or selection uniforms with one instanced draw, without scanning the document or uploading geometry. Click picking intersects full cube bounds and chooses the nearest hit. The camera follows Sculpt’s distance and scale with a fit margin that keeps complete cubes inside the pane. The status bar shows the caret, the axis, and the cube count. The element stays a text renderer.
2. A public GitHub locator is accepted only when the host is `github.com`, `www.github.com`, or `raw.githubusercontent.com`, or when the input is an `owner/repo` name. A host string elsewhere in the URL is not a match.
3. A public load skips `node_modules`, keeps at most 400 files, and skips a file larger than 1.5 MB. The line index keeps at most 12,000 rows.
4. Search opens the plane for the chosen line.
5. Markdown headings become planes. Opened files pack into one text document. Kind 2 download writes uncompressed kind 2.
6. Apple LZFSE is refused. The element stays a text renderer. The library stays free of filesystem and network I/O.
7. The workspace SHALL keep infrequent export and conversion actions in the Document disclosure, show insert tools only in Edit, and show the document title in every view. Tabs and the single-row plane outline SHALL provide one tab stop per group, with arrow, Home, and End navigation. Fit SHALL restore yaw 0.6, pitch 0.35, and zoom 1 without changing source or the selected slice. Camera buttons and the focused canvas SHALL support bounded zoom, and arrow keys SHALL orbit the focused canvas. Camera controls SHALL sit below the drawing without covering cubes. A document without a cube grid and an unavailable WebGL2 context SHALL offer Preview while preserving the source. The Document disclosure closes after an action, outside click, or Escape; Escape returns focus to its summary. The source download shortcut keeps focus in Edit. GitHub open exposes a busy state, prevents duplicate submits, and recovers its controls even on failure. Zoom is bounded from 0.45 to 3.2. Camera controls use the canvas dimensions for framing and occupy a separate strip below it.

8. File and composition-entry navigation SHALL preserve current edits, caret, and selected plane within the open collection. Edited documents SHALL be identified in every view. Opened files SHALL support filtering and keyboard navigation. Choosing a file or search result on a narrow screen SHALL reveal the document. Search and packing SHALL use current drafts. Failed local opens SHALL preserve the current collection. Explicit document navigation SHALL replace a stale source query with the current document hash. Drafts are in memory for the current collection. Download exports the current document and does not write the original file or clear its Edited marker. Opening another collection or refreshing clears these session drafts. Linked entries share their draft with the matching source file. Composition downloads remain exports of the selected document; edits do not rewrite the composition profile.

The cube input keeps at most 12 distinct non-space characters, at most 64 columns and 64 rows per plane, and at most 4000 occupied cells. Space, dot, and tab are empty. Cube painting and erasing into source, 256 cubed volumes, sparse worlds, OBJ export, and changes to Sculpt are outside this pass. The page does not rebuild the element or open-document bundles.

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
| 2026-10-10 | ThreeMDViewer change | Remove the render-mode switch and autoplay. Draw the cube stage with WebGL2 so about 1400 cubes stay interactive. |
| 2026-10-10 | ThreeMDViewer change | Open on the cube stage. The starter document is a small sculpture, and those cubes sit inside the window. |
| 2026-10-10 | ThreeMDViewer change | Keep one WebGL2 context. The bitmap size is set before the context is created so Safari does not drop it. |
| 2026-10-10 | ThreeMDViewer change | Draw every cube face. Each cell is a solid cube. |
| 2026-10-09 | agent:codex | Match Sculpt fill, glyph edges, gold selected-slice edges, background, document axes, and camera framing; retain one instanced draw and geometry reuse. |
| 2026-10-09 | agent:codex | Compact the workspace, group document actions, add Fit and accessible camera/slice controls, and clarify empty and loading states under Leif’s request to continue improving UI and UX. The layout definition remains an unapproved draft. |

| 2026-10-10 | agent:codex | Preserve file and composition drafts across navigation, expose edited state, and improve file filtering, keyboard navigation, mobile reveal, and current-document URLs in a follow-up PR after PR 92 merged. The definition remains an unapproved draft. |

| 2026-10-10 | agent:codex | Preserve the slice across editor refresh, sort file paths for consistent keyboard navigation, and compact small-phone spacing. Leif approved the final scope; verification, acceptance, and archiving are pending. |
| 2026-10-10 | SpecSync | put-edit-and-preview-in-the-same-viewer-panel-and-toggle-them-like-github-files-stay-on-the-left-edit-shows-first-below: Put Edit and Preview in the same viewer panel and toggle them like GitHub. Files stay on the left. Edit shows first. Below 900px, Files and the document take turns, and the document panel still switches Edit and Preview. |
