---
change: put-edit-and-preview-in-the-same-viewer-panel-and-toggle-them-like-github-files-stay-on-the-left-edit-shows-first-below
artifact: testing
---

# Testing

## Requirement evidence

| ID | Canonical | Evidence |
| --- | --- | --- |
| REQ-ThreeMDViewer-003 | REQ-ThreeMDViewer-003 | VIEWER-6 in `hi/tools.md`. `web/viewer.html` switches Edit and Preview in one panel and calls `render` for Preview. `uitests/viewer.spec.mjs` covers the desktop switch and the narrow Files and document switch. |
| REQ-ThreeMDViewer-004 | REQ-ThreeMDViewer-004 | VIEWER-6 in `hi/tools.md`. `web/viewer.html` holds the element on `mode="single"`, removes the render-mode menu and the play control, and draws cubes with WebGL2. `uitests/viewer.spec.mjs` covers no autoplay and about 1400 cubes. |

- `specsync check --spec ThreeMDViewer`
- `hi check` at the repository root
- Playwright `uitests/viewer.spec.mjs` passed 60 tests on Chromium and WebKit after the outline chip opens Preview first. The desktop and narrow layout tests passed again after the bar metadata hide.

The Sculpt parity pass runs `./node_modules/.bin/playwright test viewer.spec.mjs` in `uitests` on Chromium and WebKit. Added GPU pixel evidence for a full single cell from six viewpoints and gold edges with unchanged glyph fill; nearest-Z picking; 1600 cells with zero camera/selection geometry uploads and one instanced draw per redraw. Live screenshots for Character orb and the starter geometry are in `docs/evidence/viewer-sculpt-parity/`. This is agent verification and was completed while definition approval remained open.

Final parity browser verification: 70 passed on Chromium and WebKit. Strict ThreeMDViewer SpecSync check: 1 passed, zero warnings or failures. `hi check`: 85 criteria, no problems. Element bundle: current, 48840 bytes, no storage code.

## Continuing UI and UX pass

The Chromium/WebKit suite covers camera controls, phone layout and non-overlapping controls, Document disclosure dismissal, text and kind 2 download fidelity, editor focus after the save shortcut, prose Preview and sample loading, 30-slice keyboard navigation, GitHub rate-limit recovery, and WebGL2-unavailable guidance. Inspect dark/light desktop, Edit, and phone views and preserve screenshots under docs/evidence/viewer-ui/.

## File navigation fix

The Chromium and WebKit viewer suite covers exact draft restoration, invalid and empty edits, the caret and slice, composition-entry independence, linked entry/file sharing, original-text edited markers, current-text download, search and pack, file filtering and keyboard selection, mobile document reveal, failed-open preservation, and stale source-query removal on navigation. Screenshots from live desktop and phone inspection are in `docs/evidence/viewer-navigation/`. These are agent checks and do not themselves record human definition approval.

## Closure verification

The initial PR 93 hosted UI run had three Linux WebKit failures: a 179px canvas at 320 by 740, slice 0 restored instead of 1, and file keyboard focus leaving the expected button. All three reproduced in the matching Linux Playwright environment. Keep the assertions and verify the fixes in Linux and macOS. Leif's subsequent "I approve" authorizes recording the current definition and closing approval, without claiming backdated approval or independent review.

Closure implementation checks: macOS viewer 98 passed; Linux hosted UI 190 passed and 8 existing skips; Bun helper suite 15 passed; strict SpecSync 4 specs passed with zero warnings and full configured coverage; Hi 85 criteria with no problems; pinned element bundle drift passed at 48840 bytes. Logs remain local under /private/tmp/3md-viewer-closure-*. The Trust and SpecSync closing gates are still pending.
