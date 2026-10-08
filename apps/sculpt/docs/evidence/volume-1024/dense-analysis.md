# Literal 1024³ dense volume study

Both release runs initialized, hashed, decoded and compared exactly **1,073,741,824 bytes**, one byte for each of 1024³ cells. Both produced the same **53,965,390-byte** experimental LZFSE payload and identical raw, decoded and compressed SHA256 digests. The final decoder reduced the measured increase in process physical footprint during decode from **56,541,232 bytes to 3,768,344 bytes**.

The [initial receipt](initial/dense-receipt.json) was run at `6644ed2a9f8bfe5c5475ee3e86b00dc8e786d550`; the [final receipt](dense-receipt.json) was run at frozen implementation `619a0efc2fd41b51e02daacbce4e7404546fd8d9`. Source provenance comes from root's execution records and checkout state, not receipt-embedded fields. Root rebuilt the final executable through eight focused release tests. The [initial](initial/dense-run.log) and [final](dense-run.log) logs retain phase progress.

The [Swift probe](../../../Sources/RookTool/SculptureVolumeStudy.swift) uses one literal `malloc(1_073_741_824)` allocation and stores a nonzero value in every byte: `1 + ((x/32)*17 + (y/32)*31 + (z/32)*47)%254`. It hashes the entire buffer, streams Apple LZFSE to disk, then decodes while the original remains live. Verification compares every byte, exact length, raw SHA256 and compressed-file SHA256. Output publication uses a new destination and identity-checked staging.

The local experimental payload, `dense-1024.voxels.lzfse`, contains raw benchmark data without a Sculpt or ThreeMD container or editable-model semantics. Its size applies to this synthetic repeated-block pattern; it does not establish compression performance for arbitrary artwork.

| Verified bytes and hashes | Both runs |
| --- | --- |
| Initialized / raw / decoded bytes | 1,073,741,824 / 1,073,741,824 / 1,073,741,824 |
| Compressed file bytes | 53,965,390 |
| Raw and decoded SHA256 | `a769f4f6b088a7d13bd9228fba8d9c7dbbf7e1c42e2b19a808a1a3871b98a82a` |
| Compressed SHA256 | `e37ef0a7618d02f1fdf952cf30397957b8c3752bf53b09d4fb47eac88e86f183` |

| Phase wall time, seconds | Initial | Final |
| --- | ---: | ---: |
| Allocate | 0.000008625 | 0.000010125 |
| Fill every byte | 0.387138875 | 0.389057625 |
| Hash entire buffer | 0.462522209 | 0.486881500 |
| Encode | 6.038596833 | 6.076145084 |
| Decode and verify | 0.802948667 | 0.803959292 |
| Call `free` | 0.000000875 | 0.000000917 |

These are individual `ContinuousClock` phase measurements, not repeated averages or a throughput guarantee. Encode includes compressed SHA256, file writes and synchronization. Decode includes file reads, compressed and raw SHA256, and byte comparison.

| Process memory, bytes | Initial | Final |
| --- | ---: | ---: |
| Physical footprint before decode | 1,079,444,800 | 1,079,231,736 |
| Physical footprint after decode | 1,135,986,032 | 1,083,000,080 |
| Physical footprint decode increase | 56,541,232 | 3,768,344 |
| Resident decode increase | 56,524,800 | 3,751,936 |
| Highest recorded process physical-footprint peak | 1,135,986,032 | 1,083,016,464 |
| Highest recorded process resident peak | 1,143,341,056 | 1,090,437,120 |
| Physical footprint before / after `free` | 1,135,986,032 / 1,135,986,032 | 1,083,016,464 / 1,083,016,464 |

The final footprint increase is **52,772,888 bytes lower**. The initial increase was consistent with retained Foundation read buffers; samples alone cannot isolate every allocation. The repair uses **one reusable 1,048,576-byte POSIX input buffer** and **one 1,048,576-byte output buffer**, totaling 2,097,152 bytes of explicit decoder scratch. The receipt records **55 reads**, including marker checks and EOF, with maximum actual read **1,048,576 bytes**. Compression state, hashing and allocator overhead also contribute to memory. Fixed buffer sizes do not pin pages against OS compression or swapping.

Host: Mac13,2, Apple M1 Ultra, arm64, 20 active logical processors, **68,719,476,736 physical RAM bytes**, macOS 26.5.2 build 25F84, release mode. Receipts record the repository Swift 6.3.3 compiler pin rather than runtime discovery. The guard required **1,610,612,736 free bytes**, including a **536,870,912-byte reserve**. System free bytes measured **12,773,638,144 initially** and **8,186,642,432 finally**. Both process-limit remainders were unavailable (`null`); no numeric per-process limit was established. Free-page snapshots do not reserve memory or guarantee later availability.

Memory uses `TASK_VM_INFO` and `HOST_VM_INFO64.free_count * pageSize`, which already includes speculative pages. Peaks cover process lifetime; snapshots may miss transients. `free` relinquished ownership, but neither run showed an immediate footprint reduction. Allocator caching and kernel accounting can retain reported bytes; this does not establish one GiB reclaimed by macOS. Full initialization, hashing and comparison demonstrate touched bytes without guaranteeing continued RAM residence. Production 256-cell editable-model bounds remain unchanged; these measurements do not establish rendering performance.
