extends SceneTree

const Parser = preload("res://addons/threemd/parser.gd")
const Errors = preload("res://addons/threemd/error.gd")
const Checksum = preload("res://addons/threemd/checksum.gd")

var mismatches: int = 0
var shown: int = 0
var checked: int = 0

func fail(message: String) -> void:
	mismatches += 1
	if shown < 12:
		print("FAIL ", message)
		shown += 1

func same(got: Variant, expected: Variant, path: String) -> void:
	if typeof(expected) == TYPE_DICTIONARY:
		if typeof(got) != TYPE_DICTIONARY:
			fail(path + " type")
			return
		var left: Dictionary = got
		var right: Dictionary = expected
		for key in right:
			if not left.has(key):
				fail(path + "." + str(key) + " missing")
			else:
				same(left[key], right[key], path + "." + str(key))
		for key in left:
			if not right.has(key):
				fail(path + "." + str(key) + " extra")
		return
	if typeof(expected) == TYPE_ARRAY:
		if typeof(got) != TYPE_ARRAY:
			fail(path + " type")
			return
		var left_array: Array = got
		var right_array: Array = expected
		if left_array.size() != right_array.size():
			fail(path + " len " + str(left_array.size()) + " != " + str(right_array.size()))
			return
		for index in left_array.size():
			same(left_array[index], right_array[index], path + "[" + str(index) + "]")
		return
	if typeof(expected) == TYPE_FLOAT or typeof(expected) == TYPE_INT:
		if (typeof(got) == TYPE_FLOAT or typeof(got) == TYPE_INT) and float(got) == float(expected):
			return
		fail(path + " number got " + str(got) + " expected " + str(expected))
		return
	if got != expected:
		fail(path + " got " + str(got) + " expected " + str(expected))

func document_view(data: Dictionary) -> Dictionary:
	var planes: Array = []
	var raw_planes: Array = data.get("planes", [])
	for item in raw_planes:
		var plane: Dictionary = item
		planes.append({
			"z": plane.get("z", null),
			"label": plane.get("label", null),
			"x": plane.get("x", null),
			"y": plane.get("y", null),
			"attributes": plane.get("attributes", {}),
			"body": plane.get("body", null),
		})
	return {
		"version": data.get("version", null),
		"axis": data.get("axis", null),
		"title": data.get("title", null),
		"metadata": data.get("metadata", {}),
		"preamble": data.get("preamble", null),
		"planes": planes,
	}

func check_source(name: String, source: String, data: Dictionary) -> void:
	checked += 1
	var parsed: Variant = Parser.parse(source)
	if parsed == null:
		fail(name + " parse returned null")
		return
	if data.has("error"):
		if not Errors.is_error(parsed):
			fail(name + " expected error " + str(data["error"]))
		elif str(parsed.code) != str(data["error"]):
			fail(name + " error got " + str(parsed.code) + " expected " + str(data["error"]))
		return
	if Errors.is_error(parsed):
		fail(name + " " + str(parsed.code) + " " + str(parsed.message))
		return
	if data.has("expected"):
		same(parsed.to_dictionary(), document_view(data["expected"]), name)
	elif data.has("version"):
		same(parsed.to_dictionary(), document_view(data), name)
	if data.has("links"):
		var encoded: Array = []
		for link in Parser.links(parsed):
			encoded.append(link.to_dictionary())
		same(encoded, data["links"], name + ".links")
	var again: Variant = Parser.parse(Parser.serialize(parsed))
	if Errors.is_error(again):
		fail(name + " round trip " + str(again.code))
	else:
		same(again.to_dictionary(), parsed.to_dictionary(), name + ".round")

func check_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		fail("open " + path)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		fail("json " + path)
		return
	var data: Dictionary = parsed
	if not data.has("source"):
		return
	check_source(path.get_file(), str(data["source"]), data)

func check_pair(name: String, source_path: String, expected_path: String) -> void:
	var source_file := FileAccess.open(source_path, FileAccess.READ)
	var expected_file := FileAccess.open(expected_path, FileAccess.READ)
	if source_file == null or expected_file == null:
		fail("open " + name)
		return
	var expected: Variant = JSON.parse_string(expected_file.get_as_text())
	if typeof(expected) != TYPE_DICTIONARY:
		fail("json " + name)
		return
	check_source(name, source_file.get_as_text(), expected)

func _init() -> void:
	var sample := PackedByteArray()
	sample.append_array("123456789".to_utf8_buffer())
	if Checksum.crc32(sample) != 0xCBF43926:
		fail("crc " + str(Checksum.crc32(sample)))
	var root: String = ProjectSettings.globalize_path("res://").path_join("../conformance")
	var directory := DirAccess.open(root)
	if directory == null:
		fail("open " + root)
		quit(1)
		return
	for name in directory.get_files():
		if name.ends_with(".json"):
			check_file(root.path_join(name))
	var extensions: String = root.path_join("extensions")
	check_pair("document-unicode", extensions.path_join("document-unicode.3md"), extensions.path_join("document-unicode.json"))
	check_pair("unicode-key-order", extensions.path_join("unicode-key-order.3md"), extensions.path_join("unicode-key-order.json"))
	check_pair("unicode-source-collision", extensions.path_join("unicode-source-collision.3md"), extensions.path_join("unicode-source-collision.json"))
	print("TEXT ", "MISMATCH " if mismatches > 0 else "OK ", mismatches, " CASES ", checked)
	quit(0 if mismatches == 0 else 2)
