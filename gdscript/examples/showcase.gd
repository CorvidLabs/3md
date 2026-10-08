extends SceneTree

## Headless tour of the Godot 4.7 addon: text, both payload kinds, a resource,
## a self-contained composition, linked files, a revision-checked edit, and
## plane-to-node mapping. The editor importer is constructed here only to
## check its registration data. Import itself runs inside the Godot editor.

const Parser = preload("res://addons/threemd/parser.gd")
const Errors = preload("res://addons/threemd/error.gd")
const Storage = preload("res://addons/threemd/storage.gd")
const Asset = preload("res://addons/threemd/document_asset.gd")
const Composition = preload("res://addons/threemd/composition.gd")
const Files = preload("res://addons/threemd/files.gd")
const Editing = preload("res://addons/threemd/editing.gd")
const Layers = preload("res://examples/layer_map.gd")
const ImportInfo = preload("res://addons/threemd/import_info.gd")
const Planes = preload("res://addons/threemd/plane.gd")

func fail(message: String) -> void:
	print("SHOWCASE FAIL ", message)
	quit(1)

func _init() -> void:
	var folder: String = ProjectSettings.globalize_path("res://examples/grove")
	var scene_path: String = folder.path_join("scene.3md")
	var scene_text: String = FileAccess.get_file_as_string(scene_path)
	var asset: Variant = Asset.from_text(scene_text)
	if Errors.is_error(asset) or str(asset.document_title) != "Grove" or asset.plane_labels.size() != 3:
		fail("asset")
		return
	if asset.plane_labels[0] != "Ground" or asset.axis != "layer":
		fail("asset fields")
		return
	var parsed: Variant = asset.parsed()
	if Errors.is_error(parsed) or parsed.planes.size() != 3:
		fail("parsed")
		return
	var binary: Variant = Storage.encode_binary(parsed)
	if Errors.is_error(binary) or binary.slice(0, 8).get_string_from_ascii() != "3mdbin\r\n" or binary[10] != 2:
		fail("kind 2")
		return
	var from_binary: Variant = Asset.from_bytes(binary)
	if Errors.is_error(from_binary) or from_binary.plane_labels.size() != 3:
		fail("kind 2 asset")
		return
	var text_container: Variant = Storage.encode_text_container(parsed)
	if Errors.is_error(text_container) or text_container[10] != 1:
		fail("kind 1")
		return
	var lantern: Variant = Parser.parse(FileAccess.get_file_as_string(folder.path_join("props/lantern.3md")))
	if Errors.is_error(lantern):
		fail("lantern")
		return
	var profile: Variant = Composition.make("grove", [
		{
			"id": "grove",
			"document": parsed,
			"references": [{"target_id": "lantern", "attributes": {"role": "prop"}}],
		},
		{"id": "lantern", "document": lantern, "references": []},
	])
	if Errors.is_error(profile) or profile.entries.size() != 2:
		fail("composition " + str(profile.code if Errors.is_error(profile) else profile.entries.size()))
		return
	var encoded: Variant = Composition.encode(profile)
	var decoded: Variant = Composition.decode(encoded) if not Errors.is_error(encoded) else encoded
	if Errors.is_error(decoded) or str(decoded.root_id) != "grove":
		fail("composition bytes")
		return
	var linked: Variant = Files.load_linked("scene.3md", folder)
	if Errors.is_error(linked) or linked["resolved_paths"].size() != 2:
		fail("linked " + str(linked.code if Errors.is_error(linked) else linked["resolved_paths"].size()))
		return
	var adopted: Variant = Editing.adopt_document(parsed)
	var snap: Variant = Editing.snapshot(adopted) if not Errors.is_error(adopted) else adopted
	if Errors.is_error(snap):
		fail("snapshot")
		return
	var first: Object = adopted.planes[0]
	var identifier: Variant = Editing.stable_id(first)
	var replacement := Planes.new()
	replacement.z = first.z
	replacement.x = first.x
	replacement.y = first.y
	replacement.label = first.label
	replacement.attributes = first.attributes.duplicate(true)
	replacement.body = str(first.body) + "\nEdited in Godot."
	var applied: Variant = Editing.apply({
		"expected_revision": str(snap["revision"]),
		"operations": [{"kind": "replace", "id": str(identifier), "plane": replacement}],
	}, snap)
	if Errors.is_error(applied) or not str(applied["document"].planes[0].body).contains("Edited in Godot."):
		fail("edit")
		return
	var stale: Variant = Editing.apply({
		"expected_revision": str(snap["revision"]),
		"operations": [{"kind": "replace", "id": str(identifier), "plane": replacement}],
	}, applied)
	if not Errors.is_error(stale) or str(stale.code) != "staleRevision":
		fail("stale")
		return
	var layers: Variant = Layers.build(scene_path)
	if Errors.is_error(layers) or layers.size() != 3 or str(layers[0].name) != "Ground":
		fail("layers")
		return
	if float(layers[1].get_meta("threemd_z")) != 1.0:
		fail("layer z")
		return
	var extensions: PackedStringArray = ImportInfo.extensions()
	if ImportInfo.resource_type() != "ThreeMDDocumentAsset" or ImportInfo.save_extension() != "res":
		fail("importer type")
		return
	if extensions.size() != 2 or extensions[0] != "3md" or extensions[1] != "3mdb":
		fail("importer extensions")
		return
	print("SHOWCASE OK")
	quit(0)
