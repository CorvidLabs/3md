# Claude review triage, 2026-10-06

Claude's read-only review completed successfully through Rune. Its unmodified receipt is `claude-review-receipt.json`. Reviewed implementation source is unchanged between `ad17806` and published `3127e83`. The review is agent evidence, not a GitHub approval, runtime proof or signature.

Source inspection confirms three actionable issues: Swift's outer recognition applies a lowered plane policy too early; file discovery counts unused embedded ledgers against incoming depth instead of final entry-graph depth; the Rust adapter bounds source count before hex decoding while the others do the reverse. Corrections and focused regressions are assigned to agent `world_navigation`. New complete verification is pending; the earlier passing receipt remains historical evidence for its recorded source.

The bounded depth correction separates a fixed 64-file discovery safety ceiling from caller-selected final entry-graph depth. The adapter correction consistently refuses an oversized source array before allocating per-file bytes. The documented host same-user rename limitation remains; optional portability and coverage observations require individual validation and are not all treated as proven defects.

PR65 is open and currently marked ready externally, with GitHub Trust, UI and CodeQL passing on `3127e83`. That green CI does not close these new review findings. No merge, release or finalization is claimed.
