---
hi: 1
families: [EDITING]
---

# Editing

## Intent

I want stable identities and revision-checked edits in Swift, TypeScript, and Rust, so a patch lands completely or leaves the document I already have.

## Criteria

- **EDITING-1**  I can give a plane a stable 3md-id, and I can give a composition reference its own 3md-id inside the entry that owns it.
- **EDITING-2**  An ordinary id attribute stays metadata for my program. I use 3md-id when I want an edit to recognize that plane or reference.
- **EDITING-3**  I can adopt identities so a valid identity I already wrote stays and only a missing one is assigned. Parsing a document does not invent an identity.
- **EDITING-4**  I can apply a patch to a document or a composition in Swift, TypeScript, or Rust that checks the exact canonical revision, and a match publishes the whole result while a stale revision or a failing operation leaves what I had.
- **EDITING-5**  When an edit is refused in Swift, TypeScript, or Rust, I get a structured diagnostic with a stable code, a severity, an explanation, and the line or path evidence the edit actually has.
- **EDITING-6**  An edit leaves the frozen 1.0 text grammar, container version 1, and the 3md-composition-1 profile as they are.
- **EDITING-7**  If I cancel an edit that is still in progress in Swift, TypeScript, or Rust, I still have the document or composition I started with.
- **EDITING-8**  A plane or a reference keeps its identity when I change its body, label, position, order, or target.
- **EDITING-9**  An edit leaves my existing cross-plane Markdown links and HTML anchors written as they were.
- **EDITING-10**  I can rely on the Godot addon to replace one composition entry and keep that entry's id, and the other composition editing operations stay in Swift, TypeScript, and Rust.
