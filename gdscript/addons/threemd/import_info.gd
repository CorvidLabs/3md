extends RefCounted

## Registration data for the Godot 4.7 editor importer.
## Headless checks read this. Only the editor constructs EditorImportPlugin.

static func extensions() -> PackedStringArray:
	return PackedStringArray(["3md", "3mdb"])

static func resource_type() -> String:
	return "ThreeMDDocumentAsset"

static func save_extension() -> String:
	return "res"
