@tool
extends EditorPlugin

## Enables ThreeMD import for `.3md` and `.3mdb` files.
## Enabling the plugin does not change the open scene.

var _importer: EditorImportPlugin

func _enter_tree() -> void:
	_importer = load("res://addons/threemd/import_plugin.gd").new()
	add_import_plugin(_importer)

func _exit_tree() -> void:
	if _importer != null:
		remove_import_plugin(_importer)
		_importer = null
