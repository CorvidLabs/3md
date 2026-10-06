# Linked file composition verification

Implementation tip: `ad17806da3eb0e093d7d02f9fb4d15dd4c3aaf90`. Base: `be41af523aecf041202a06d4c83471b19e09b275`.

The pinned Trust 1.2.2 gate passed with Fledge 1.7.2 and SpecSync 6.0.0: 264 Swift tests, 153 TypeScript tests with type checking and package build, 43 Rust tests plus three doctests, strict Clippy, editor grammar, derived bundle drift, and all nine public-package interchange pairs. The matrix has 459 cases and 17,343 imports, 1,927 per pair. Strict contract coverage is 47/47 files and 13,632/13,632 lines with zero warnings. CLI and element specs retain their existing draft limits. Trust reports the unchanged soft provenance degradation; no permitted signature or human approval is claimed.

The Swift development host probe passed eight cases: text and binary bundles, a root-folder selection, refusal of existing file/directory/symlink outputs, and source symlink/FIFO refusal. The latter returns without blocking. Existing outputs and outside bytes remain intact. Probe artifacts are retained at the path in its log. These checks do not establish protection against malicious concurrent same-user renames. Source descriptors are anchored and nonblocking; staging publication and nonrecursive identity-checked cleanup retain the documented Darwin check/use limitation.

Complementary agent source reviews found and repaired Swift scalar slash splitting, cached depth, path cancellation priority, host path-check/open races, recursive staging cleanup and binary output profile limits. Agent `threemd_typescript` reviewed Swift/Rust and the root-authored host/cases; agent `world_navigation` repaired Swift source and host. Actual executing agents are identified here, with no independent human review claim. Shared cases establish cross-port agreement and source-free bundle import; independent unit tests provide semantic assertions. Linux/Windows execution and optional Apple LZFSE parity are not established by this macOS lane.

Claude review is delegated separately through Rune and remains pending. Feature publication, official scope closure and release remain separate from these receipts. Historical evidence is unchanged.
