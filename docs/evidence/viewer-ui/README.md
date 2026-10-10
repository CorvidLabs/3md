# Viewer UI and UX evidence

This pass continues Leif’s request to improve the viewer UI and UX on PR 92. The cube renderer retains the Sculpt comparison and bounds recorded in [the parity evidence](../viewer-sculpt-parity/README.md).

The workspace uses the existing CorvidLabs tokens and Schibsted Grotesk/Spline Sans Mono typography. A compact header and toolbar give the stage more room. The title stays visible, insert tools appear in Edit, and the Document disclosure groups downloads, copying, heading conversion, and file packing. Composition entry selection remains visible in the stage when needed.

Fit restores the native-style starting camera without changing the document or selected slice. Buttons and keyboard controls provide bounded zoom and orbiting. Controls sit below the canvas. The slice outline stays in one scrolling row and keeps the selected slice visible. Tabs and slices provide one tab stop per group with arrow, Home, and End navigation.

Nongrid documents offer Preview without replacing their source. An unavailable WebGL2 context explains how to keep reading in Preview. GitHub open exposes its busy state, prevents duplicate submits, and restores its controls after errors.

## Live visual checks

Screenshots were captured from the running local viewer after the UI changes. Desktop captures use a 1440 by 900 viewport; the phone capture uses 390 by 844. The starter has 122 cells, with the walls slice selected. Temporary viewport and theme changes were restored. These are agent observations, not Leif’s diff review or an accessibility certification.

- [Dark desktop](desktop-dark.jpg): stage, title, slice selection, and camera controls.
- [Light desktop](desktop-light.jpg): themed workspace around the same dark GPU stage.
- [Document actions](document-actions.jpg): the open disclosure and clear export labels.
- [Edit](edit.jpg): source tools and keyboard hints appear in context.
- [Phone](phone.jpg): Files/Document switching, complete sculpture framing, and camera controls below the drawing.

## Verification

The final viewer suite passed all 84 cases in Chromium and WebKit. It includes the prior full-face pixel, nearest-slice picking, no-upload camera/selection, and 1600-cell responsiveness checks, plus camera controls, phone geometry, disclosure dismissal, both download formats, save-shortcut focus, prose Preview, 30-slice keyboard navigation, GitHub rate-limit recovery, and GPU-unavailable guidance.

Text download retains the source bytes. Binary export is checked as parsed fields and plane bodies because its decoded text is canonical. Camera-direction checks are independent of font-driven layout changes. The strict ThreeMDViewer contract check and hi check also pass; hi reports the pre-existing stale INTENT.md feature index.

Pinned Trust runs after committing and pushing the feature head. Its exact-head result and provenance limitations are reported on PR 92. The existing SpecSync definition stays an unapproved draft; no lifecycle approval, merge, release, deployment, signature, or independent human review is recorded by these screenshots or tests.
