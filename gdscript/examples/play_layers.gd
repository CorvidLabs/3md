extends SceneTree

## Loads one 3md document and reports each plane as a game layer.
## The addon returns data. The game decides which nodes those planes become.

const Parser = preload("res://addons/threemd/parser.gd")
const Errors = preload("res://addons/threemd/error.gd")

func _init() -> void:
	var path: String = ProjectSettings.globalize_path("res://examples/layers.3md")
	var source: String = FileAccess.get_file_as_string(path)
	var document: Variant = Parser.parse(source)
	if Errors.is_error(document) or document == null:
		print("LAYERS FAIL")
		quit(1)
		return
	if str(document.title) != "Grove" or document.planes.size() != 3:
		print("LAYERS FAIL shape")
		quit(1)
		return
	var labels: PackedStringArray = PackedStringArray()
	for item in document.planes:
		labels.append(str(item.z) + " " + str(item.label))
	if labels[0] != "0.0 Ground" and labels[0] != "0 Ground":
		print("LAYERS FAIL ground ", labels[0])
		quit(1)
		return
	if str(document.planes[1].label) != "Canopy" or str(document.planes[2].label) != "HUD":
		print("LAYERS FAIL labels")
		quit(1)
		return
	print("LAYERS OK ", document.planes.size())
	quit(0)
