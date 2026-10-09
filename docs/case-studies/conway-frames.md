# Conway frames

[`game-of-life.3md`](../../Examples/game-of-life.3md) is a text example. The axis is `frame`. Each plane is one generation stored as a Markdown body.

Version and library limits that apply to every study are in the [index](README.md).

## What the document is

The file is text grammar `1.0`, axis `frame`, title Conway's Game of Life. The frontmatter is:

| Key | Value |
| --- | --- |
| 3md | 1.0 |
| axis | frame |
| legend | o=● |
| title | Conway's Game of Life |
| fps | "6" |
| rule | "B3/S23" |
| seed | glider + blinker + block |

The quotes around `6` and `B3/S23` are frontmatter syntax. A parser stores the strings inside them.

Before the first plane, the preamble says: "Each plane is one generation. Press play (or scrub Z) to run the simulation." The next sentence says the glider travels, the blinker oscillates, and the block stays put. That prose is the file.

The file has 24 `@plane` directives. `z` runs from 0 through 23. The first label is `gen 0`. The last label is `gen 23`. Each label is `gen` plus that plane's `z`.

Each body is a Markdown picture. The picture uses `o`. The legend says `o=●`. The libraries store that legend string. They do not draw the dot.

## What you can open

- [`Examples/game-of-life.3md`](../../Examples/game-of-life.3md), the document.
- [`Examples/README.md`](../../Examples/README.md). It lists this file under `axis: frame` as Conway's Game of Life. The same note says the hosted viewer does not yet decode binary files.
- The root [README](../../README.md). It describes this file as "a real 24-generation Conway run (animates, and renders as a 3D object in the viewer's blend view)."
- [`element/README.md`](../../element/README.md). Parsing stays in `@corvidlabs/threemd`. The element owns only the visual.

[`Examples/conways-game-of-life.3md`](../../Examples/conways-game-of-life.3md) is a different file. The README size table names that one. This study does not use it.

## What the libraries do

Swift and TypeScript parse each plane as data: `z`, an optional label, optional `x` and `y`, any other directive attributes, and a Markdown body. These 24 directives set `z` and a label. They set no `x`, no `y`, and no other attributes.

A document keeps the version, the axis, the title, metadata, an optional preamble, and the planes. Metadata is any frontmatter key other than `3md`, `axis`, and `title`. `legend`, `fps`, `rule`, and `seed` stay on the document. They are not plane fields. There is no simulation API.

The next generation is already written in the next plane.

## What they do not do

The libraries store each plane and do not execute `B3/S23`. `rule` stays a metadata string. No code path here counts neighbors or writes a new generation.

A viewer may scrub or play planes. The element README says the component is a 3D stack of planes you scrub, drag, and step through along Z. `play()` and `pause()` control auto-advancing playback. `autoplay`, and `mode="play"`, start that advance when content loads. The step adds one to the focused plane index and renders the plane already stored. It reads `fps` from document metadata only to time that step. The root README says this file animates, and that the viewer's blend view renders it as a 3D object. That is the viewer moving `z`. It is not the library computing `B3/S23`.

When the element draws a fenced picture, it may replace a character using the `legend` metadata. That remap belongs to the element. The libraries still do not draw the dot.

The hosted gallery shows text examples. It does not decode `.3mdb`. This file is text. This study has no binary twin in the repo.
