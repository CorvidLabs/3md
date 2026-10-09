---
hi: 1
families: [STORAGE]
---

# Storage

## Intent

I want the same document saved as the text file or as binary payload kind 2, with no fixed size stop.

## Criteria

- **STORAGE-1**  I can save the same document as the text file or as binary payload kind 2.
- **STORAGE-2**  I want kind 2 to store each plane's number, name, and body as fields. The file starts with the 40-byte header, and its magic is 3mdbin.
- **STORAGE-3**  I want kind 1 to stay deprecated. Readers still open it, and a writer can still emit kind 1 when a ThreeMD 2.0 reader must open the file. New saves use kind 2.
- **STORAGE-4**  I want no fixed size stop. I can set a lower positive limit, and a document is read and written when the process can hold it.
- **STORAGE-5**  I want a small integer coordinate to stay a fixed-width integer.
- **STORAGE-6**  I want Apple LZFSE to stay optional and only in Swift on Apple. TypeScript, Rust, and GDScript tell me it is unavailable.
- **STORAGE-7**  I want a bad checksum or a reserved payload kind to be refused.
- **STORAGE-8**  I want Sculpt.3md's compact .3mdb to stay the app's save. It is not this binary format.
- **STORAGE-9**  I want the hosted gallery viewer to stay on the text file.
