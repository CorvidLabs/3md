---
change: remove-the-absolute-storage-size-ceilings-so-a-1-gb-5-gb-or-any-document-the-process-can-hold-is-parsed-and-saved-in
artifact: research
---

# Research

The 64 MiB stop was not one field. SPEC.md 11.2 capped encoded bytes, decoded bytes, and the raisable record ceiling at 67,108,864. The record default was 8 MiB. Lines defaulted to 100,000 and planes to 65,536. A cube of 1024 planes of 1024 lines of 1024 letters is about 1 GiB of letters and about 1,048,576 physical lines, so it failed the line cap as well as the byte cap.

SPEC.md 11.3.3 defined one Var for every integer: unsigned LEB128, 1 to 4 bytes, maximum 2^28 − 1. The same encoding carried string lengths. The smallest 5-byte value is 2^28 (268,435,456). Five gigabytes (5,368,709,120) is a JavaScript safe integer and encodes as `80 80 80 80 14`.

Form 1 coordinates use that Var as a zigzag. The form-1 range is −2^27 through 2^27 − 1, and the zigzag of −2^27 is exactly `ff ff ff 7f`. Widening coordinate Vars would change the meaning of a 5th byte in existing files and would change which numbers use form 1. Coordinate Vars stay at 4 bytes.

Kind 2 is records, not compression. On the committed 293-file size list, kind 2 is 1,156,441 bytes against 1,188,086 of canonical text (ratio 0.973). A 1 GB text document stays about 1 GB as kind 2.

This machine is an Apple M1 Ultra with 64 GB of RAM. A local 1 GB encode and decode is the proof that the ceiling is gone. A 5 GB run is optional and is not a CI allocation. CI proves the ceiling is gone with a body of 64 MiB + 1 letters and a document of 100,001 non-blank lines. A body of only newlines is collapsed by the text format, so it is not the size proof.

Two conformance vectors were written when every Var stopped at 4 bytes. `var-five-bytes` is a version length of `ff ff ff ff 01`. That value is now the legal length 2^29 − 1, and one following byte makes it `lengthMismatch`. `var-four-continuation-truncated` is a length whose fourth byte continues and whose fifth byte is absent. A length reader asks for the fifth byte and reports `lengthMismatch`. The same shape as a coordinate is still `invalidContainer`.

The approved kind-2 delta says no limit field or error code is added, and that Var follows SPEC.md 11.3.3. This change keeps the fields and the codes and updates 11.3.3. It does not edit that approved change.
