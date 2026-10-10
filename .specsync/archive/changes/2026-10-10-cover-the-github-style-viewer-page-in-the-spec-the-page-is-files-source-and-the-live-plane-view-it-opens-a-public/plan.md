---
change: cover-the-github-style-viewer-page-in-the-spec-the-page-is-files-source-and-the-live-plane-view-it-opens-a-public
artifact: plan
---

# Plan

## WP1. Definition

- Keep this change in draft until Leif approves the definition.
- The semantic delta is `deltas/ThreeMDViewer.md`.
- Hi for this behavior is already VIEWER-6 in `hi/tools.md`.

## WP2. Canonical spec, after approval

- Scaffold `specs/ThreeMDViewer/` and register the module.
- Write the canonical spec from REQ-ThreeMDViewer-001 and REQ-ThreeMDViewer-002.
- List the page files: `web/viewer.html`, `web/gather.ts`, `web/github-source.ts`, `web/open-document.ts`, `web/assets/open-document.js`, `web/gather.test.ts`, `web/github-source.test.ts`, `web/open-document.test.ts`, and `uitests/viewer.spec.mjs`.
- Leave `ThreeMD`, `ThreeMDCLI`, and `ThreeMDElement` on their current contracts. The element source stays text-only.

## WP3. Check

- `specsync check --spec ThreeMDViewer`
- `hi check` at the repository root
- The existing bun tests for gather, github-source, and open-document, and the Playwright viewer spec

No parser, fixture, package version, tag, or publish step is in this change.
