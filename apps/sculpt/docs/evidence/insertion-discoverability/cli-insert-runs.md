# Explicit-file insert runs

Inputs were copies of `Examples/Compositions/courtyard.3md`, `Examples/Compositions/wide-world.3md`, `Examples/little-rocket.3md` and `Examples/moon-gate.3md` in a scratch folder. Successful inserts ran with the debug RookTool built at `93b00b3`. Refusals were re-run with RookTool at `0fb74ae`, which changes only how RookTool prints errors. JSON receipts are abbreviated with `jq`.

## Successful inserts

Native composition, replacing two occupied tiles:

```text
RookTool sculpture reference insert courtyard.3md ref-comp-replace.json out/courtyard-ref.3md
{"kind":"composition","storage":"native","placed":[{"title":"Little rocket","modelID":"insert-model-1","cell":{"x":1,"y":0,"z":0}},{"title":"Moon gate","modelID":"insert-model-2","cell":{"x":2,"y":0,"z":0}}],"replacedGlyphs":["C","C"],"portableDataNotCarried":[]}
RookTool sculpture inspect out/courtyard-ref.3md  ->  mode composition, title "Courtyard of courtyards"
```

Native world at an exact trillion-cell focus:

```text
RookTool sculpture reference insert wide-world.3md ref-world.json out/world-ref.3md
{"kind":"world","storage":"native","placed":[{"title":"Little rocket","instanceID":"insert-instance-1","origin":{"x":"1000000000000","y":"0","z":"-1000000000000"}},{"title":"Moon gate","instanceID":"insert-instance-2","origin":{"x":"1000000000025","y":"0","z":"-1000000000000"}}]}
```

Portable composition with an exact expected scene, written as portable binary:

```text
RookTool sculpture portable export courtyard.3md courtyard-portable.3md   ->  35,173 bytes
RookTool sculpture portable insert courtyard-portable.3md port-comp.json out/courtyard-portable-inserted.3mdb
{"kind":"composition","storage":"portable","bytes":69231,"revisionUTF8Bytes":69191,"placed":[...Little rocket at 1,0,0; Moon gate at 2,0,0...],"replacedGlyphs":["C","C"],"diag":[]}
RookTool sculpture portable inspect out/courtyard-portable-inserted.3mdb  ->  kind composition, portableInput true, 6 models
```

## Refusals (nothing written)

```text
occupied target without replaceOccupied:
RookTool failed: Refusing to replace occupied tiles without "replaceOccupied": true. column 2, row 1, layer 1 holds C; column 3, row 1, layer 1 holds C.

existing output:
RookTool failed: Refusing existing output or symbolic link at .../out/courtyard-ref.3md. Choose a new output file.

world used as a child:
RookTool failed: wide-world.3md: Insert a voxel model or composition. A sparse world cannot be used as a child model.

expected scene from a different valid scene:
RookTool failed: staleRevision at expectedRevision: The scene differs from expectedScene.

portable parent given to reference insert:
RookTool failed: .../courtyard-portable.3md is a portable ThreeMD file. Use sculpture portable insert, or choose a native Sculpt composition or sparse world.
```

Before `0fb74ae`, the same refusals printed Swift enum spellings such as `occupied([...])` and `outputExists(...)`. That is why RookTool now prints localized explanations.
