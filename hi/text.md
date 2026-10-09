---
hi: 1
families: [TEXT]
---

# Text

## Intent

I want a plain UTF-8 .3md file I can open in any editor, with a Z axis I name and planes of Markdown I can parse and write back.

## Criteria

- **TEXT-1**  I can keep a document as a plain UTF-8 .3md file and open it in any editor.
- **TEXT-2**  I name the Z axis.
- **TEXT-3**  I write a plane as an @plane line with a z position, an optional label, and a Markdown body.
- **TEXT-4**  I can write a file with the 3md header and no planes, and that file is one plane.
- **TEXT-5**  I mark the file as 3md with required frontmatter. An older version string such as 0.1 still opens, and the parser does not reject a document for its version string.
- **TEXT-6**  I want text grammar 1.0 to stay frozen.
- **TEXT-7**  I can parse the text into planes and render it back to an equal document.
- **TEXT-8**  I write a cross-plane link as [[z=N]], and I can see which links have no target.
- **TEXT-9**  A malformed file fails with a clear error and does not replace a document I already have.
- **TEXT-10**  I want planes to stay data. The format does not build a game, a voxel, or a scene.
