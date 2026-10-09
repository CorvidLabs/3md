class_name ThreeMDDocumentFormatLoader
extends ResourceFormatLoader

## Loads an imported ThreeMDDocumentAsset outside the editor.
## Godot registers this class_name from the global script class cache at
## startup, including a running game. The importer plugin is editor-only.
## This loader claims only type ThreeMDDocumentAsset and extension res.
## Virtual methods stay untyped so Godot binds them.

func _get_recognized_extensions():
	var extensions := PackedStringArray()
	extensions.append("res")
	return extensions

func _handles_type(type):
	return type == &"ThreeMDDocumentAsset"

func _get_resource_type(path):
	if path.get_extension() != "res":
		return ""
	return "ThreeMDDocumentAsset"

func _load(path, _original_path, _use_sub_threads, _cache_mode):
	if path.get_extension() != "res":
		return ERR_FILE_UNRECOGNIZED
	# An empty type lets the binary loader open the .res. CACHE_MODE_IGNORE
	# keeps this read off the import remap that called it. A typed load of
	# the same path would recurse.
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
