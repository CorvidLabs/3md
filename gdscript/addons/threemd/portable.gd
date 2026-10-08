class_name ThreeMDPortable
extends RefCounted

## Shared text helpers. Whitespace is the frozen Foundation set, not Godot's
## strip_edges, so every language trims the same scalar values.

const _Unicode = preload("res://addons/threemd/nfc.gd")

static func is_whitespace(unit: int) -> bool:
	return unit == 0x0009 or unit == 0x0020 or unit == 0x00A0 or unit == 0x1680 \
		or (unit >= 0x2000 and unit <= 0x200B) or unit == 0x202F or unit == 0x205F or unit == 0x3000

static func trim(value: String) -> String:
	var start: int = 0
	var end: int = value.length()
	while start < end and is_whitespace(value.unicode_at(start)):
		start += 1
	while end > start and is_whitespace(value.unicode_at(end - 1)):
		end -= 1
	if start == 0 and end == value.length():
		return value
	return value.substr(start, end - start)

static func canonical_strings(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var spellings: Dictionary = {}
	for key in source:
		var text: String = str(key)
		var normalized: String = _Unicode.nfc(text)
		var spelling: String = text
		if spellings.has(normalized):
			spelling = spellings[normalized]
		else:
			spellings[normalized] = text
		result[spelling] = source[key]
	return result

static func canonical_keys(source: Dictionary) -> PackedStringArray:
	var keys: Array[String] = []
	var norms: Array[String] = []
	for key in source:
		var text: String = str(key)
		var norm: String = _Unicode.nfc(text)
		var placed: bool = false
		for index in keys.size():
			if _Unicode.compare(norm, norms[index]) < 0:
				keys.insert(index, text)
				norms.insert(index, norm)
				placed = true
				break
		if not placed:
			keys.append(text)
			norms.append(norm)
	var packed := PackedStringArray()
	for key in keys:
		packed.append(key)
	return packed

static func valid_id(id: String) -> bool:
	var count: int = id.length()
	if count < 1 or count > 64:
		return false
	for index in count:
		var unit: int = id.unicode_at(index)
		var alphanumeric: bool = (unit >= 48 and unit <= 57) or (unit >= 65 and unit <= 90) or (unit >= 97 and unit <= 122)
		if index == 0:
			if not alphanumeric:
				return false
		elif not alphanumeric and unit != 95 and unit != 45:
			return false
	return true

const MAXIMUM_INTEGER: int = 9007199254740991

static func nfc(text: String) -> String:
	return _Unicode.nfc(text)

static func utf8_length(text: String) -> int:
	return text.to_utf8_buffer().size()

static func bounded_integer(value: int, minimum: int, maximum: int) -> bool:
	return value >= minimum and value <= maximum and value >= -MAXIMUM_INTEGER and value <= MAXIMUM_INTEGER

static func strings_equal(left: Dictionary, right: Dictionary) -> bool:
	var first := _nfc_map(left)
	var second := _nfc_map(right)
	if first.size() != second.size():
		return false
	for key in first:
		if not second.has(key) or str(first[key]) != str(second[key]):
			return false
	return true

static func documents_equal(left: Object, right: Object) -> bool:
	if str(left.version) != str(right.version) or str(left.axis) != str(right.axis):
		return false
	if left.title != right.title or left.preamble != right.preamble:
		return false
	if not strings_equal(left.metadata, right.metadata):
		return false
	if left.planes.size() != right.planes.size():
		return false
	for index in left.planes.size():
		var plane: Object = left.planes[index]
		var other: Object = right.planes[index]
		if float(plane.z) != float(other.z) or plane.x != other.x or plane.y != other.y:
			return false
		if plane.label != other.label or str(plane.body) != str(other.body):
			return false
		if not strings_equal(plane.attributes, other.attributes):
			return false
	return true

static func canonical_document(document: Object) -> Object:
	var _Documents = preload("res://addons/threemd/document.gd")
	var _Planes = preload("res://addons/threemd/plane.gd")
	var copy = _Documents.new()
	copy.version = document.version
	copy.axis = document.axis
	copy.title = document.title
	copy.preamble = document.preamble
	copy.metadata = canonical_strings(document.metadata)
	var planes: Array = []
	for item in document.planes:
		var plane = _Planes.new()
		plane.z = item.z
		plane.x = item.x
		plane.y = item.y
		plane.label = item.label
		plane.body = item.body
		plane.attributes = canonical_strings(item.attributes)
		planes.append(plane)
	copy.planes = planes
	return copy

static func _nfc_map(source: Dictionary) -> Dictionary:
	var normalized := canonical_strings(source)
	var result: Dictionary = {}
	for key in normalized:
		result[nfc(str(key))] = normalized[key]
	return result
