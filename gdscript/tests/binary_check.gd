extends SceneTree

const Parser = preload("res://addons/threemd/parser.gd")
const Storage = preload("res://addons/threemd/storage.gd")
const Errors = preload("res://addons/threemd/error.gd")
const Portable = preload("res://addons/threemd/portable.gd")
const Documents = preload("res://addons/threemd/document.gd")
const Planes = preload("res://addons/threemd/plane.gd")

var mismatches: int = 0
var shown: int = 0
var checked: int = 0

func fail(message: String) -> void:
	mismatches += 1
	if shown < 12:
		print("FAIL ", message)
		shown += 1

func bytes_equal(left: PackedByteArray, right: PackedByteArray) -> bool:
	if left.size() != right.size():
		return false
	for index in left.size():
		if left[index] != right[index]:
			return false
	return true

func hex_prefix(bytes: PackedByteArray) -> String:
	var count: int = mini(12, bytes.size())
	var text := ""
	for index in count:
		text += "%02x" % bytes[index]
	return text

func read_bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path)

func error_text(value: Variant) -> String:
	if Errors.is_error(value):
		return str(value.get("code")) + " " + str(value.get("message"))
	return str(value)

func mismatch_at(left: PackedByteArray, right: PackedByteArray) -> String:
	var count: int = mini(left.size(), right.size())
	for index in count:
		if left[index] != right[index]:
			return " at " + str(index) + " got " + "%02x" % left[index] + " exp " + "%02x" % right[index]
	return " truncated"

func make_plane(z: float, body: String) -> Object:
	var plane = Planes.new()
	plane.z = z
	plane.label = null
	plane.x = null
	plane.y = null
	plane.attributes = {}
	plane.body = body
	return plane

func worked_document(name: String) -> Variant:
	if name == "worked-document":
		var source: String = "---\n3md: \"1.0\"\naxis: \"time\"\ntitle: \"Week\"\nowner: \"ops\"\n---\n\n@plane z=0 label=\"Mon\"\n# Standup\n\n@plane z=1.5 label=\"Tue\" x=-2 kind=\"note\"\nShip it\n"
		return Parser.parse(source)
	var document = Documents.new()
	document.title = null
	document.metadata = {}
	document.preamble = null
	if name == "worked-numbers":
		document.version = "1.0"
		document.axis = "layer"
		var plane = make_plane(0.1, "")
		plane.x = 0.5
		plane.y = 268435456.0
		plane.attributes = {"note": "say \"hi\""}
		document.planes = [plane]
		return document
	if name == "worked-keys":
		document.version = "1"
		document.axis = ""
		document.metadata = {"z": "1", "e\u0301": "2"}
		var plane = make_plane(-3.0, "")
		plane.attributes = {"b": "x", "a": "y"}
		document.planes = [plane]
		return document
	return null

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
		if str(entry.get("kind", "")) != "document" or entry.get("compositionEnvelope", false) == true:
			continue
		checked += 1
		var name: String = str(entry.get("id", ""))
		var parsed: Variant = null
		if str(entry.get("set", "")) == "worked":
			parsed = worked_document(name)
		else:
			var source_path: String = root.path_join(str(entry["sourceFile"]))
			if not FileAccess.file_exists(source_path):
				fail(name + " missing source")
				continue
			var source: String = FileAccess.get_file_as_string(source_path)
			parsed = Parser.parse(source)
		if Errors.is_error(parsed) or parsed == null:
			fail(name + " parse")
			continue
		if entry.has("textContainerFile"):
			var kind1: Variant = Storage.encode_text_container(parsed)
			if Errors.is_error(kind1) or not (kind1 is PackedByteArray):
				fail(name + " kind1 " + error_text(kind1))
			else:
				var expected1: PackedByteArray = read_bytes(root.path_join(str(entry["textContainerFile"])))
				if not bytes_equal(kind1, expected1):
					fail(name + " kind1 bytes " + str(kind1.size()) + " != " + str(expected1.size()) + " " + hex_prefix(kind1) + mismatch_at(kind1, expected1))
			var text_container: PackedByteArray = read_bytes(root.path_join(str(entry["textContainerFile"])))
			var decoded_text: Variant = Storage.decode(text_container)
			if Errors.is_error(decoded_text) or decoded_text == null:
				fail(name + " decode kind1 " + error_text(decoded_text))
			elif not Portable.documents_equal(decoded_text, parsed):
				fail(name + " decode kind1 document")
		var kind2: Variant = Storage.encode_binary(parsed)
		if Errors.is_error(kind2) or not (kind2 is PackedByteArray):
			fail(name + " kind2 " + error_text(kind2))
		else:
			var expected2: PackedByteArray = read_bytes(root.path_join(str(entry["kind2File"])))
			if not bytes_equal(kind2, expected2):
				fail(name + " kind2 bytes " + str(kind2.size()) + " != " + str(expected2.size()) + " " + hex_prefix(kind2) + mismatch_at(kind2, expected2))
			var decoded: Variant = Storage.decode(expected2)
			if Errors.is_error(decoded) or decoded == null:
				fail(name + " decode kind2 " + error_text(decoded))
			elif not Portable.documents_equal(decoded, parsed):
				fail(name + " decode kind2 document")
	print("BINARY ", "MISMATCH " if mismatches > 0 else "OK ", mismatches, " CASES ", checked)
	quit(0 if mismatches == 0 else 2)
