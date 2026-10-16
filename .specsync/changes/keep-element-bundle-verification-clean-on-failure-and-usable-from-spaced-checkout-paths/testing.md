---
change: keep-element-bundle-verification-clean-on-failure-and-usable-from-spaced-checkout-paths
artifact: testing
---

# Testing

Corrected before-fix receipt:20261016T030801Z-D4-39c625 (2 pass,5 fail). After-fix task:20261016T030826Z-D4-bb8919 (7 pass,0 fail, real48840-byte bundle). Full pinned Trust1.2.2/native gate:20261016T031300Z-D4-2b036d, exit0,258.729s. It ran322 Swift tests,431 TypeScript tests,115 Rust tests including doc tests with1 existing ignored case,17991 imports across9 writer/reader pairs, the7 checker regressions, real bundle drift and editor grammar. Latest released SpecSync6.1.1 strict/100%coverage:20261016T030945Z-D4-9a6ae5, exit0. A separate read-only GPT reviewer found no actionable defect. Native Trust was run on the working tree before a product commit, so its empty committed-range provenance does not qualify a future commit. No hosted CI, human review, signature or merge is claimed. An earlier attempted all-process network sandbox failed Swift nested sandbox creation; the successful gate retains Swift’s sandbox and confines dependency installation to a network-denied wrapper using existing caches.
