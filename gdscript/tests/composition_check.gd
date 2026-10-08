extends SceneTree

## Round-trips every composition envelope in the structured manifest.
## The outer document is parsed as text. Embedded definitions go through storage.

const Parser = preload("res://addons/threemd/parser.gd")
const Errors = preload("res://addons/threemd/error.gd")
const Composition = preload("res://addons/threemd/composition.gd")

var mismatches: int = 0
var shown: int = 0
var checked: int = 0

func fail(message: String) -> void:
	mismatches += 1
	if shown < 12:
		print("FAIL ", message)
		shown += 1

func _init() -> void:
	var root: String = ProjectSettings.globalize_path("res://").path_join("..")
	var manifest_text: String = FileAccess.get_file_as_string(root.path_join("conformance/structured/manifest.json"))
	var manifest: Variant = JSON.parse_string(manifest_text)
	if typeof(manifest) != TYPE_DICTIONARY:
		fail("manifest")
		quit(1)
		return
	var files: Array = manifest["files"]
	for item in files:
		var entry: Dictionary = item
		if entry.get("compositionEnvelope", false) != true:
			continue
		checked += 1
		var name: String = str(entry.get("id", ""))
		var source: String = FileAccess.get_file_as_string(root.path_join(str(entry["sourceFile"])))
		var parsed: Variant = Parser.parse(source)
		if Errors.is_error(parsed) or parsed == null:
			fail(name + " parse")
			continue
		var decoded: Variant = Composition.decode(parsed)
		if Errors.is_error(decoded) or decoded == null:
			var code: String = str(decoded.code) if Errors.is_error(decoded) else "null"
			fail(name + " decode " + code + " " + str(decoded.message if Errors.is_error(decoded) else ""))
			continue
		if str(decoded.root_id).is_empty():
			fail(name + " root")
		if decoded.entries.is_empty():
			fail(name + " entries")
		var rebuilt: Variant = Composition.to_document(decoded)
		if Errors.is_error(rebuilt) or rebuilt == null:
			var code: String = str(rebuilt.code) if Errors.is_error(rebuilt) else "null"
			fail(name + " document " + code + " " + str(rebuilt.message if Errors.is_error(rebuilt) else ""))
			continue
		var original_body: String = str(parsed.planes[0].body)
		var rebuilt_body: String = str(rebuilt.planes[0].body)
		if rebuilt_body != original_body:
			fail(name + " body " + str(rebuilt_body.length()) + " != " + str(original_body.length()))
		var again: Variant = Composition.decode(rebuilt)
		if Errors.is_error(again) or again == null:
			fail(name + " redecode")
		elif str(again.root_id) != str(decoded.root_id) or again.entries.size() != decoded.entries.size():
			fail(name + " redecode shape")
	print("COMPOSITION ", "MISMATCH " if mismatches > 0 else "OK ", mismatches, " CASES ", checked)
	quit(0 if mismatches == 0 else 2)
