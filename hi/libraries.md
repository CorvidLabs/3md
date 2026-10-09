---
hi: 1
families: [LIBRARIES]
---

# Libraries

## Intent

I want the published Swift, TypeScript, and Rust libraries to accept the same text documents and the same uncompressed kind-2 files, and I want each install path to name the version that registry or formula actually serves.

I want Sculpt.3md to stay the Mac app beside those libraries, and I want a format change to land in Swift, TypeScript, Rust, and GDScript.

## Criteria

- **LIBRARIES-1**  Swift, TypeScript, and Rust accept the same text documents and the same uncompressed kind-2 files. I can write a file in one and read it in the others.
- **LIBRARIES-2**  The hosted verification lane is Swift, TypeScript, and Rust. It does not install Godot.
- **LIBRARIES-3**  I can add the Swift package from tag v2.2.1.
- **LIBRARIES-4**  npm serves @corvidlabs/threemd 2.2.1 and @corvidlabs/three-md-element 2.2.1.
- **LIBRARIES-5**  crates.io still serves the crate threemd at 2.1.0. The Rust manifest in the GitHub repo reads 2.2.1. I am not told that cargo add installs 2.2.1.
- **LIBRARIES-6**  The Homebrew formula threemd is 2.2.1.
- **LIBRARIES-7**  Sculpt.3md is the Mac app at apps/sculpt. Its package name is Rook. It is not another format parser, and its compact .3mdb is not the upstream binary.
- **LIBRARIES-8**  A format change lands in Swift, TypeScript, Rust, and GDScript.
