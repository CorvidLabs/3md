# Edit and Preview share one panel

## ADDED

### REQUIREMENT REQ-ThreeMDViewer-003

The viewer page SHALL show Edit and Preview in one panel. Exactly one of them SHALL be visible. Edit SHALL be the default. Files SHALL stay in the column beside that panel. Below 900px, Files and the document SHALL take turns, and the document panel SHALL still switch Edit and Preview. Choosing Preview SHALL render the live plane view.

Acceptance Criteria:

- At a desktop width, files stay visible. Edit shows the editor and hides the preview. Preview shows the live plane view and hides the editor.
- At 800px, Files and the document take turns. The document panel still switches Edit and Preview.
- Evidence is VIEWER-6 and the layout tests in `uitests/viewer.spec.mjs`.
