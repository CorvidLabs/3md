---
change: harden-linked-composition-parity-across-swift-typescript-and-rust-after-2-0-0
artifact: context
---

# Context

ThreeMD 2.0.0 shipped linked file composition. A read-only parity audit of main 9ac2454 and two adversarial reviews of the follow-up work found no result divergence for ordinary inputs, but found that per-reference discovery work and memory grew with the containing path (for a 1 MiB directory with 16,356 references, Swift took 56 s and about 16 GB and Rust 14 s and about 14 GB), that over-bound source-file edges were refused only after discovery, that caller limits and several refusal orders were testable only per language, that Rust parsed long limit literals and reported adoption at the exact attribute bound differently, and that Swift and Rust lacked mid-operation cancellation tests.

This change was prepared on 2026-10-06 under Leif's direct request to continue 3md release preparation, while another session owned the 2.0.0 release itself. The implementation was written on an unpublished local branch under an earlier definition (local commit cdf01b7, approved by agent:claude before implementation) that also listed release documentation. Leif then split the work: the release session delivered the release documentation, CLI build fix and publish workflows in PR69, and this follow-up keeps only the parity hardening, the Linux CI job and its own documentation. This definition records that narrowed scope on a branch from the released main ca2d1e3. No merge, tag, release, package publication or deployment is part of it.
