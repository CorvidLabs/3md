# ThreeMD delta

## MODIFIED

### Spec Section Dependencies

- Swift Foundation for text, Data, JSON and localized errors.
- Conditional Apple system Compression for optional LZFSE; no third-party Swift
  dependency or CryptoKit requirement. The original text surface stays portable.
- TypeScript adds no production dependency. Rust adds exact unicode-normalization 0.1.25 for new canonical key comparison, locked with its small dependencies. Existing text parsing/serialization behavior is unchanged.
- ThreeMD 2.1 adds no runtime dependency in any language. Rust keeps
  `unicode-normalization = "=0.1.25"` as its only dependency and adds
  `#![forbid(unsafe_code)]`. The fast CRC is table-driven code in each port,
  with no hardware intrinsics required.
- Repository validation runs the element bundle checker and its subprocess
  regressions through the existing `element-bundle` lane step. The checker
  preserves bundle bytes, removes temporary output after success or failure,
  and supports checkout paths containing spaces. This adds no library dependency.
