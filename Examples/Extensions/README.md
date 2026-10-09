# Storage and composition fixtures

Two readable documents, and the binary saves beside them. The parent
[examples catalog](../README.md#storage-and-composition-fixtures) is the longer
note. [manifest.json](manifest.json) records the byte counts and SHA256 hashes.
Those hashes check the fixture. They do not authenticate an author.

| File | What it is |
|------|------------|
| [canopy.3md](canopy.3md) | Text. Axis `space`. Title Reusable canopy. Two planes. |
| [canopy.3mdb](canopy.3mdb) | Kind 1, uncompressed. The text copied after the 40-byte header. Kind 1 is deprecated for new files. |
| [canopy.structured.3mdb](canopy.structured.3mdb) | Kind 2, uncompressed. The structured payload of that same document. |
| [canopy.lzfse.3mdb](canopy.lzfse.3mdb) | Kind 1, Apple LZFSE. The viewer and the non-Apple libraries refuse it. |
| [shared-grove.3md](shared-grove.3md) | Readable composition profile `3md-composition-1`. |
| [shared-grove.3mdb](shared-grove.3mdb) | Kind 1, uncompressed. The profile text after the header. |
| [shared-grove.structured.3mdb](shared-grove.structured.3mdb) | Kind 2, uncompressed. The same profile as structured fields. |
| [shared-grove.lzfse.3mdb](shared-grove.lzfse.3mdb) | Kind 1, Apple LZFSE. |

Canopy is the document stored inside the grove. Shared grove embeds that text
once and points at it. The library does not open a path while decoding the
grove.

Every `.3md` file here uses newlines and ends with one. Inside
`shared-grove.3md`, the embedded documents are JSON `source` strings, so their
newlines are written as `\n`.

The CLI reads the text files. The viewer page opens the uncompressed binaries
and this composition. Gallery cards stay on the text catalog.
