---
spec: ThreeMDViewer.spec.md
---

## Automated Testing

| Test File | Type | What It Covers |
|-----------|------|----------------|
| `web/gather.test.ts` | bun | Section planes, pack, kind 2 round-trip, line plane index, search rank. |
| `web/github-source.test.ts` | bun | Repo, folder, file, and raw locators. Host and path routing. Issues URL rejected. |
| `web/open-document.test.ts` | bun | Text, composition, kind 1, kind 2, LZFSE refusal, linked folder. |
| `uitests/viewer.spec.mjs` | Playwright | Edit, Preview, and Cubes share one panel; full cube face pixels from all sides; glyph fill and gold edge selection; nearest slice picking; no camera/selection geometry uploads; about 1400 cubes; no console errors; narrow layout; kind 2, linked village, search, sections, composition; keyboard camera and slice controls; phone stage space; disclosure dismissal and both downloads; source shortcut focus; Preview empty state; GitHub busy/error recovery; GPU-unavailable guidance. |

## Requirement evidence

| ID | Canonical | Evidence |
| --- | --- | --- |
| REQ-ThreeMDViewer-001 | REQ-ThreeMDViewer-001 | VIEWER-6 in `hi/tools.md`. The page and the bun and Playwright tests above. |
| REQ-ThreeMDViewer-002 | REQ-ThreeMDViewer-002 | `web/github-source.ts` hostname checks, the 400 file and 1.5 MB caps, the 12,000 line cap in `web/viewer.html`, and the LZFSE test. |
| REQ-ThreeMDViewer-003 | REQ-ThreeMDViewer-003 | VIEWER-6 in `hi/tools.md`. Desktop and narrow layout tests in `uitests/viewer.spec.mjs`. |
| REQ-ThreeMDViewer-004 | REQ-ThreeMDViewer-004 | VIEWER-6 in `hi/tools.md`. `uitests/viewer.spec.mjs` opens the page and requires lit cubes inside the window, checks that the page does not autoplay, and draws about 1400 cubes on WebGL2. |

## Manual Testing

- [x] Run Sculpt locally, orbit Character orb in Cubes, and compare the same orb in the refreshed local viewer. Screenshots: `docs/evidence/viewer-sculpt-parity/`.
- [x] Inspect one-cell and starter sculptures for filled top, front, and side faces, visible edges, and pane framing.
- [x] Open `viewer.html`. On a wide window, files stay on the left and Edit, Preview, and Cubes switch in the panel beside them. On a narrow window, Files and the document take turns.

## Edge Cases & Boundary Conditions

| Scenario | Expected Behavior |
|----------|-------------------|
| Host name only appears inside the path or query | The locator is rejected. |
| Tree contains `node_modules` or a file over 1.5 MB | Those files are skipped. |
| More than 400 text files, or more than 12,000 lines | The list stops at the cap and says so. |
| Apple LZFSE bytes | The page refuses them and names `compressionUnavailable`. |
| Desktop width | Files stay visible while Edit, Preview, and Cubes switch. Preview shows the live plane view. |
| Width at or below 900px | Files and the document take turns. The document still switches Edit and Preview. |

## Continuing UI and UX verification

- The viewer suite exercises the new controls in Chromium and WebKit. Binary export is compared as parsed document fields and plane bodies because decoding returns canonical text. Camera direction assertions are independent of font-driven aspect-ratio changes.
- Live desktop dark, desktop light, Edit, and phone views are inspected and captured in `docs/evidence/viewer-ui/`. These are agent visual checks, not human approval.
