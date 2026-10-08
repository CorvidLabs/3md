class_name ThreeMDLayerMap
extends Node

## Example game boundary. Attach this to a node the game owns.
## Each plane becomes a child Node. The addon does not instance gameplay nodes
## on its own. Set `document_path` to a project `.3md` file.

const _Files = preload("res://addons/threemd/files.gd")
const _Errors = preload("res://addons/threemd/error.gd")

@export var document_path: String = ""

func _ready() -> void:
	if document_path.is_empty():
		return
	var built: Variant = build(document_path)
	if _Errors.is_error(built) or not (built is Array):
		push_error("ThreeMD layer map failed for " + document_path)
		return
	for item in built:
		add_child(item)

static func build(path: String) -> Variant:
	var document: Variant = _Files.load_document(path)
	if _Errors.is_error(document) or document == null:
		return document if _Errors.is_error(document) else _Errors.make("invalidText", "invalidText", -1, path)
	var layers: Array = []
	for item in document.planes:
		var layer := Node.new()
		var label: String = "plane" if item.label == null or str(item.label).is_empty() else str(item.label)
		layer.name = label
		layer.set_meta("threemd_z", item.z)
		layer.set_meta("threemd_body", str(item.body))
		layers.append(layer)
	return layers
