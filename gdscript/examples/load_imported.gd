extends SceneTree

## Headless load() of one imported .3md and one imported kind-2 .3mdb.
## Does not spawn nodes. Does not build the asset with from_text.

func fail(message: String) -> void:
	print("LOAD IMPORTED FAIL ", message)
	quit(1)

func expect_grove(asset: Variant, path: String) -> bool:
	if asset == null or not (asset is ThreeMDDocumentAsset):
		fail(path + " is not a ThreeMDDocumentAsset")
		return false
	if str(asset.document_title) != "Grove":
		fail(path + " title " + str(asset.document_title))
		return false
	var labels := PackedStringArray()
	labels.append("Ground")
	labels.append("Canopy")
	labels.append("HUD")
	var got: PackedStringArray = asset.plane_labels
	if got.size() != labels.size():
		fail(path + " label count " + str(got.size()))
		return false
	for index in labels.size():
		if got[index] != labels[index]:
			fail(path + " label " + str(index) + " " + str(got[index]))
			return false
	return true

## _initialize runs after Godot registers class_name resource loaders.
## _init on a --script SceneTree runs before that registration.
func _initialize() -> void:
	var text_path := "res://examples/grove/scene.3md"
	var binary_path := "res://examples/grove/scene.3mdb"
	var text_asset: Variant = load(text_path)
	if not expect_grove(text_asset, text_path):
		return
	var binary_asset: Variant = load(binary_path)
	if not expect_grove(binary_asset, binary_path):
		return
	print("LOAD IMPORTED OK")
	quit(0)
