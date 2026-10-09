# Sunken Vault links

[`dungeon.3md`](../../Examples/dungeon.3md) is a tiny choose-your-path dungeon. Each plane is a room. The exits are cross-plane links.

Version and library limits that apply to every study are in the [index](README.md).

## What the document is

The file is text grammar `1.0`, axis `space`, title The Sunken Vault. It also writes `genre: "choose-your-path"` and `start: "z=0"`. Those two keys are not reserved. They stay strings.

The preamble says each plane is a room. It says x and y give that room a position on an imagined map so a spatial viewer can lay it out. The preamble links to `[[z=0|the entrance]]`.

Five planes:

| z | Label | x | y |
| --- | --- | --- | --- |
| 0 | entrance | 0 | 0 |
| 1 | flooded-hall | 0 | -1 |
| 2 | armory | 1 | 0 |
| 3 | vault | 1 | -1 |
| 4 | ending | 2 | -1 |

Each room's exits are `[[z=N|text]]` links. These are the target z values in the file:

| Where | Target z | Text |
| --- | --- | --- |
| Preamble | 0 | the entrance |
| Entrance (`z=0`) | 1 | the flooded hall |
| Entrance (`z=0`) | 2 | the old armory |
| Flooded hall (`z=1`) | 3 | the vault |
| Flooded hall (`z=1`) | 0 | the entrance |
| Armory (`z=2`) | 3 | the vault |
| Armory (`z=2`) | 0 | the entrance |
| Vault (`z=3`) | 4 | you win |
| Vault (`z=3`) | 4 | you fall |

The ending plane (`z=4`) has no cross-plane link. The file has no bare `[[z=N]]` link. Every link includes text.

The spear and the two endings are prose in the plane bodies. The armory says one spear is still keen and that you take it. The vault says you win if you carry that spear, and that you fall if you are unarmed. Both of those links name `z=4`. The ending says the close is the relic in hand or a quiet drowning. The file does not mark which one happened.

## What you can open

- [`Examples/dungeon.3md`](../../Examples/dungeon.3md), the document.
- [SPEC.md section 8](../../SPEC.md#8-cross-plane-links), the `[[z=N]]` and `[[z=N|text]]` grammar.
- [`CrossPlaneLink.swift`](../../Sources/ThreeMD/CrossPlaneLink.swift), the Swift link record.
- [`Plane.swift`](../../Sources/ThreeMD/Plane.swift), where a plane stores `z`, `label`, `x`, `y`, and the body.
- The [command-line tool](../../README.md#command-line-tool) section. It names `threemd links` and `threemd check-links`.

## What the libraries do

The parser stores the version, the axis, the title, the other frontmatter strings, the preamble, and the planes. Each plane stores `z`, an optional label, optional `x`, optional `y`, and a Markdown body. This file sets a label, an `x`, and a `y` on every plane.

[SPEC.md section 8](../../SPEC.md#8-cross-plane-links) leaves a cross-plane link in the Markdown. A separate step extracts one record per link in a plane body. Swift's `CrossPlaneLink` stores `sourceZ`, `targetZ`, optional `text`, and `targetExists`. The optional text is the words after the pipe. It is not the plane label. `text` is nil when the pipe is absent. `targetExists` is true when a plane's `z` equals `targetZ`.

`Document.links()` walks plane bodies in source order, then left to right in each body. It does not read the preamble. The preamble link stays preamble text.

`threemd links` lists the extracted cross-plane links and the dangling references. `threemd check-links` exits non-zero when any `[[z=N]]` target is missing. Both accept `--json`. The README spells them as `swift run threemd links <file>` and `swift run threemd check-links <file>`.

Every target z written in this file is also a plane `z`: `0`, `1`, `2`, `3`, or `4`.

## What they do not do

The libraries do not track inventory. The spear stays a sentence in the armory body. They do not choose an ending. The two vault links store the same target z and different text. The link record does not pick one.

`x` and `y` are plane fields for a spatial viewer. The libraries store them. They do not lay out a map. The axis name `space` is metadata. It does not connect rooms.

`start` is the string `z=0`. It is not a link record. `genre` is the string `choose-your-path`. Neither key chooses a path.

A missing `[[z=N]]` target fails `threemd check-links`. That check uses links extracted from plane bodies. It does not scan the preamble.

There is no committed `.3mdb` twin of `dungeon.3md`. The hosted gallery shows the text. It does not play the dungeon.
