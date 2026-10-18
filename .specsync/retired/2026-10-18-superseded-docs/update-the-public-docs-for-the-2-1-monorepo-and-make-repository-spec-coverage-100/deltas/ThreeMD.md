# Public docs for ThreeMD 2.1.0 and the nested app

## ADDED

### REQUIREMENT REQ-ThreeMD-044

The public docs SHALL describe ThreeMD 2.1.0 as the current library, with the text file and binary named as the two saves, and SHALL name Kind 1 as deprecated. They SHALL say npm and crates.io serve 2.1.0.

Acceptance Criteria:
- The README leads with ThreeMD 2.1.0, the text file, binary, and Kind 1 as deprecated.
- Install docs say npm `@corvidlabs/threemd` 2.1.0 and crates.io `threemd` 2.1.0 are published.

### REQUIREMENT REQ-ThreeMD-045

The public docs SHALL identify Sculpt.3md as the nested Mac app at `apps/sculpt`, package name Rook, building against this checkout. They SHALL keep Swift, TypeScript, and Rust as the three format parsers. They SHALL NOT call the app a fourth parser or call its compact `.3mdb` the upstream binary standard.

Acceptance Criteria:
- Contributor docs name Sculpt.3md at `apps/sculpt`, package name Rook, and still require a format change in Swift, TypeScript, and Rust.
- The docs do not call the app a fourth parser and do not call compact `.3mdb` the upstream binary standard.
