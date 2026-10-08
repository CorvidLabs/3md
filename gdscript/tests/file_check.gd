extends SceneTree

## LinkedVillage: four caller-supplied files become one composition profile.

const Errors = preload("res://addons/threemd/error.gd")
const Linked = preload("res://addons/threemd/file_composition.gd")
const Files = preload("res://addons/threemd/files.gd")
const Composition = preload("res://addons/threemd/composition.gd")

func fail(message: String) -> void:
	print("FAIL ", message)
	quit(1)

func _init() -> void:
	var root: String = ProjectSettings.globalize_path("res://").path_join("..")
	var folder: String = root.path_join("Examples/LinkedVillage")
	var names: PackedStringArray = PackedStringArray([
		"scene.3md",
		"models/house.3md",
		"models/tree.3md",
		"models/tower.3md",
	])
	var sources: Array = []
	for name in names:
		var data: PackedByteArray = FileAccess.get_file_as_bytes(folder.path_join(name))
		if data.is_empty():
			fail("missing " + name)
			return
		sources.append({"path": name, "data": data})
	var resolved: Variant = Linked.resolve("scene.3md", sources)
	if Errors.is_error(resolved):
		fail("resolve " + str(resolved.code) + " " + str(resolved.message))
		return
	if str(resolved["root_path"]) != "scene.3md":
		fail("root " + str(resolved["root_path"]))
		return
	var paths: Array = resolved["resolved_paths"]
	if paths.size() != 4:
		fail("paths " + str(paths.size()))
		return
	var composition: Object = resolved["composition"]
	if composition.entries.size() != 4:
		fail("entries " + str(composition.entries.size()))
		return
	var encoded: Variant = Composition.encode(composition)
	if Errors.is_error(encoded) or not (encoded is PackedByteArray):
		fail("encode")
		return
	var again: Variant = Composition.decode(encoded)
	if Errors.is_error(again) or str(again.root_id) != str(composition.root_id):
		fail("redecode")
		return
	var loaded: Variant = Files.load_linked("scene.3md", folder)
	if Errors.is_error(loaded) or str(loaded["root_path"]) != "scene.3md":
		fail("files " + str(loaded.code if Errors.is_error(loaded) else loaded))
		return
	print("FILES OK ", paths.size())
	quit(0)
