# Native insertion observations, 2026-10-06

Actor: Codex root through CUA, not a human reviewer. The current saved Pixel bonsai session had no unsaved changes before replacing the running build. The earlier user's Valley castle backup remains outside this PR.

The optimized package at implementation `0845768347f84fa6d67fcc829cc11896b8393c4d` was used for these actual UI actions:

1. New composition opened Model garden, map `A.B`, `.A.`, `B.A`, with five placed tiles. Select plus column 2, row 1 changed only the insertion start. Undo remained disabled and the map stayed unchanged.
2. Insert 3md selected only `tiny-cube.3md` through the native chooser. Tile C appeared at that start, map `ACB`, `.A.`, `B.A`, six placed tiles. One Undo removed C and restored the original library/map. One Redo restored C and its model title.
3. Inserting `tiny-cross.3md` at that occupied tile opened a confirmation naming the incoming tiny-cross, the current C tiny-cube, and exact one-based column/row/layer. Cancel retained C and the map. Repeating and confirming replaced the tile with D tiny-cross, yielding `ADB`, `.A.`, `B.A`.
4. File > Export portable ThreeMD > Readable 3md copy saved `/private/tmp/sculpt-native-inserted-portable-20261006.3md`. The native status reported the portable export and restored the composition. This copy has 35,586 bytes, SHA256 `8fb276beb81368bcd71b170784233526495b220a9ebcc9ed90998db9c70d0df6`.
5. The agent-created draft was discarded after saving the separate copy. Opening only that copy through the chooser restored the complete library including tiny-cube and tiny-cross, map `ADB`, `.A.`, `B.A`, and six placed tiles. No source folder was selected in this reopen flow. Tool inspection confirms portable input with root and both namespaced inserted models and no diagnostics. This is source-free portable reopening, not a test against concurrent malicious folder edits.
6. Use in a world created one shared composition placement at 0,0,0. Insert model folder selected the authored `native/models` directory. The two-file batch added placements at 35,35,11 and 38,35,11. One Undo removed both and restored one placement; Redo restored both at the same coordinates. This temporary agent-created world was discarded.

The final package at implementation `02138387ab1c9bdff497b23a28922f72a984c1c1` was repackaged and reopened. In a fresh composition, inserting tiny-cube at occupied column 1, row 1 opened the confirmation. The actual File menu showed both Readable 3md copy and Binary 3mdb copy disabled while pending. Escape canceled the candidate and the fresh test draft was closed, leaving the unchanged Character orb document with no unsaved changes.

These observations are native interaction evidence. They do not assert a human design approval, on-screen frame rate, a notarized build or release. Folder cancellation and all stale candidate/focus/snapshot and metadata assertions also have separate automated tests in the final 440-test lane.
