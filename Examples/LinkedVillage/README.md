# Linked village

Open scene.3md with a host that implements docs/FILE-COMPOSITION.md. Characters 1 and 4 share the same house. Tower links to Tree relative to its own models folder. The three model files are in [models](models/README.md). No module registration is required.

These are generic ThreeMD Markdown documents with ASCII illustrations. Placement/rendering belongs to the host; this example is not a Sculpt spatial-schema file.

From the repository root, create a new portable bundle:

```
swift run threemd-interchange --bundle scene.3md --folder Examples/LinkedVillage --output linked-village.3md
```

The output folder must not be a symlink: on macOS `/tmp` is one, and the host refuses it. Use a new .3mdb destination for portable uncompressed binary. The command never overwrites an existing file. A bundled profile can move away from this folder and import through each library's existing composition codec. Editing the Tree source and resolving again refreshes every linked occurrence; existing bundled copies are independent.

