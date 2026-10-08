@tool
extends EditorImportPlugin

## Imports `.3md` text and `.3mdb` containers as ThreeMDDocumentAsset resources.
## Godot 4.7 calls this from the editor. The library itself does not read files.

const _Asset = preload("res://addons/threemd/document_asset.gd")
const _Errors = preload("res://addons/threemd/error.gd")
const _Info = preload("res://addons/threemd/import_info.gd")

func _get_importer_name() -> String:
	return "threemd.document"

func _get_visible_name() -> String:
	return "ThreeMD Document"

func _get_recognized_extensions() -> PackedStringArray:
	return _Info.extensions()

func _get_save_extension() -> String:
	return _Info.save_extension()

func _get_resource_type() -> String:
	return _Info.resource_type()

func _get_priority() -> float:
	return 1.0

func _get_format_version() -> int:
	return 1

func _get_preset_count() -> int:
	return 1

func _get_preset_name(preset_index: int) -> String:
	return "Document"

func _get_import_options(path: String, preset_index: int) -> Array[Dictionary]:
	return []

func _import(source_file: String, save_path: String, options: Dictionary, platform_variants: Array, gen_files: Array) -> Error:
	var data: PackedByteArray = FileAccess.get_file_as_bytes(source_file)
	if data.is_empty():
		return ERR_FILE_CANT_READ
	var asset: Variant = _Asset.from_bytes(data)
	if _Errors.is_error(asset) or not (asset is Resource):
		return ERR_PARSE_ERROR
	return ResourceSaver.save(asset, "%s.%s" % [save_path, _get_save_extension()])
