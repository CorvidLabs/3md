---
change: remove-the-absolute-storage-size-ceilings-so-a-1-gb-5-gb-or-any-document-the-process-can-hold-is-parsed-and-saved-in
artifact: design
---

# Design

## Defaults

`DocumentDecodeLimits.standard` (Rust `Default`) sets all five fields to the host maximum. The constructor rejects only a non-positive value. TypeScript also rejects non-integers and values above `Number.MAX_SAFE_INTEGER`, because a JavaScript bitwise or shift path cannot be trusted with those numbers. Length arithmetic uses multiply and divide.

`data.count <= limit` is true for every buffer the process can allocate when the limit is the host maximum. Writers size their buffers from the document estimate. They do not allocate `Int.max` or `usize::MAX` up front.

## Kind-2 decoded bound

D10 for kind 2 is `min(maximumEncodedBytes − 40, 2 × maximumDecodedBytes)`. Swift, TypeScript, and Rust saturate the subtraction and the product. `2 * Int.max` and `2 * Number.MAX_SAFE_INTEGER` must not wrap.

## Integers

One LEB128 routine used to serve lengths, counts, and form-1 coordinates, capped at 4 bytes (2^28 − 1). A 256 MB string needs a 5th byte, so that cap made a large document unrepresentable even after the byte ceiling was removed.

Length and count readers accept at most 10 bytes and accumulate a `UInt64` / `u64`. The last allowed byte rejects a continuation. A trailing zero byte is still `invalidContainer`. The host conversion is `oversizedOutput` when the magnitude fits in 64 bits and not in `Int` or `usize`.

Coordinate form 1 calls the same reader with a maximum of 4 bytes. Zigzag of −2^27 remains `ff ff ff 7f`. `ff ff ff ff 01` is a valid length and an invalid coordinate.

Writers emit the minimal form. Values that already fit in 4 bytes are unchanged, so committed kind-2 goldens stay byte-identical.

## What stays capped

`DocumentCompositionLimits` and `DocumentEditLimits` keep their absolute ceilings. File composition's standalone `resolvePath` and `ledger` read `DocumentDecodeLimits.standard.maximumRecordBytes`. After this change that check accepts any path the process can hold. The profile byte budget is still `maximumProfileBytes`.

## Samples that still use 64 MiB

Cancellation and memory tests that used to depend on the default ceiling now pass an explicit 64 MiB encoded or decoded limit, an explicit 100,000-line limit, or an explicit 8 MiB record limit. Those files are samples of the algorithm. They are not a product cap.
