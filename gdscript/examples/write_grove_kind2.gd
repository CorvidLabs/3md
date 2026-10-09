extends SceneTree

## Writes examples/grove/scene.3mdb with this addon's payload kind 2 encoder.
## The load example imports that file. This script does not call load().

const Parser = preload("res://addons/threemd/parser.gd")
const Storage = preload("res://addons/threemd/storage.gd")
const Errors = preload("res://addons/threemd/error.gd")

func fail(message: String) -> void:
	print("WRITE KIND2 FAIL ", message)
	quit(1)

func _init() -> void:
	var folder: String = ProjectSettings.globalize_path("res://examples/grove")
	var text: String = FileAccess.get_file_as_string(folder.path_join("scene.3md"))
	var document: Variant = Parser.parse(text)
	if Errors.is_error(document) or document == null:
		fail("parse")
		return
	var binary: Variant = Storage.encode_binary(document)
	if Errors.is_error(binary) or not (binary is PackedByteArray):
		fail("encode")
		return
	var bytes: PackedByteArray = binary
	if bytes.size() < 11 or bytes.slice(0, 8).get_string_from_ascii() != "3mdbin\r\n" or bytes[10] != 2:
		fail("not kind 2")
		return
	var destination: String = folder.path_join("scene.3mdb")
	var file: FileAccess = FileAccess.open(destination, FileAccess.WRITE)
	if file == null:
		fail("open")
		return
	file.store_buffer(bytes)
	file.close()
	print("WRITE KIND2 OK bytes=", bytes.size())
	quit(0)
