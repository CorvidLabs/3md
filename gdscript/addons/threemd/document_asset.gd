class_name ThreeMDDocumentAsset
extends Resource

## A Godot resource for one 3md document.
## The editor importer saves this type. A game can also build it from text or
## from payload kind 1 and kind 2 bytes. Parsing stays in the pure library.

const _Parser = preload("res://addons/threemd/parser.gd")
const _Storage = preload("res://addons/threemd/storage.gd")
const _Errors = preload("res://addons/threemd/error.gd")

@export var source: String = ""
@export var axis: String = ""
@export var document_title: String = ""
@export var plane_labels: PackedStringArray = PackedStringArray()

static func from_text(text: String) -> Variant:
	var document: Variant = _Parser.parse(text)
	if _Errors.is_error(document) or document == null:
		return document if _Errors.is_error(document) else _Errors.make("invalidText", "invalidText", -1, "")
	var asset: Object = load("res://addons/threemd/document_asset.gd").new()
	asset.source = text
	asset.axis = str(document.axis)
	asset.document_title = "" if document.title == null else str(document.title)
	var labels := PackedStringArray()
	for item in document.planes:
		labels.append("" if item.label == null else str(item.label))
	asset.plane_labels = labels
	return asset

static func from_bytes(data: PackedByteArray) -> Variant:
	var document: Variant = _Storage.decode(data)
	if _Errors.is_error(document) or document == null:
		return document if _Errors.is_error(document) else _Errors.make("invalidText", "invalidText", -1, "")
	var canonical: Variant = _Storage.encode_text(document)
	if _Errors.is_error(canonical) or not (canonical is PackedByteArray):
		return canonical if _Errors.is_error(canonical) else _Errors.make("invalidDocument", "invalidDocument", -1, "")
	var packed: PackedByteArray = canonical
	return from_text(packed.get_string_from_utf8())

func parsed() -> Variant:
	return _Parser.parse(source)
