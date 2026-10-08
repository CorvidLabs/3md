extends SceneTree

## Development adapter for protocol `3md-interchange-1`.
## The library stays pure. This script only reads the two paths after `--`.

const Storage = preload("res://addons/threemd/storage.gd")
const Structured = preload("res://addons/threemd/structured.gd")
const Parser = preload("res://addons/threemd/parser.gd")
const Editing = preload("res://addons/threemd/editing.gd")
const Composition = preload("res://addons/threemd/composition.gd")
const Linked = preload("res://addons/threemd/file_composition.gd")
const Errors = preload("res://addons/threemd/error.gd")
const Portable = preload("res://addons/threemd/portable.gd")
const Documents = preload("res://addons/threemd/document.gd")
const Planes = preload("res://addons/threemd/plane.gd")

const _MAXIMUM_LINE: int = 33554432
const _COMPOSITION_NAMES: Array[String] = [
	"maximumDefinitions", "maximumReferences", "maximumDepth", "maximumDefinitionBytes",
	"maximumTraversalOccurrences", "maximumProfileBytes", "maximumReferenceAttributes",
	"maximumReferenceAttributeBytes",
]
const _DOCUMENT_NAMES: Array[String] = [
	"maximumEncodedBytes", "maximumDecodedBytes", "maximumLines", "maximumPlanes", "maximumRecordBytes",
]

func _init() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() != 2:
		quit(1)
		return
	var source: PackedByteArray = FileAccess.get_file_as_bytes(arguments[0])
	var text: String = source.get_string_from_utf8()
	var lines: PackedStringArray = PackedStringArray()
	var start: int = 0
	while start < text.length():
		var newline: int = text.find("\n", start)
		var end_index: int = text.length() if newline < 0 else newline
		var line: String = text.substr(start, end_index - start)
		if newline < 0:
			if not line.is_empty():
				lines.append(_respond(line))
			break
		lines.append(_respond(line))
		start = newline + 1
	var handle := FileAccess.open(arguments[1], FileAccess.WRITE)
	if handle == null:
		quit(1)
		return
	for item in lines:
		handle.store_string(str(item) + "\n")
	handle.flush()
	handle.close()
	quit(0)

func _respond(line: String) -> String:
	if line.length() > _MAXIMUM_LINE or line.is_empty():
		return _failure("adapterFailure")
	var parsed: Variant = JSON.parse_string(line)
	if typeof(parsed) != TYPE_DICTIONARY:
		return _failure("adapterFailure")
	var request: Dictionary = parsed
	if str(request.get("schema", "")) != "3md-interchange-1":
		return _failure("adapterFailure")
	var kind: String = str(request.get("kind", ""))
	if kind != "document" and kind != "composition" and kind != "files":
		return _failure("adapterFailure")
	if typeof(request.get("bytesHex", null)) != TYPE_STRING:
		return _failure("adapterFailure")
	var bytes: Variant = _hex_to_bytes(str(request["bytesHex"]))
	if bytes == null:
		return _failure("adapterFailure")
	var data: PackedByteArray = bytes
	if kind == "files":
		return _files(data)
	if kind == "composition":
		var composition: Variant = Composition.decode(data)
		if Errors.is_error(composition) or composition == null:
			return _failure(_code(composition))
		return _composition_response(composition)
	var document: Variant = Storage.decode(data)
	if Errors.is_error(document) or document == null:
		return _failure(_code(document))
	return _document_response(data, document)

func _files(data: PackedByteArray) -> String:
	var payload_text: Variant = Structured.decode_utf8(data, 0, data.size())
	if Errors.is_error(payload_text):
		return _failure("adapterFailure")
	var scanner := _Scan.new()
	var parsed: Variant = scanner.parse(str(payload_text))
	if scanner.failed or typeof(parsed) != TYPE_DICTIONARY:
		return _failure("adapterFailure")
	var payload: Dictionary = parsed
	for key in payload:
		var name: String = str(key)
		if name != "rootPath" and name != "files" and name != "limits" and name != "documentLimits":
			return _failure("adapterFailure")
	if typeof(payload.get("rootPath", null)) != TYPE_STRING or typeof(payload.get("files", null)) != TYPE_ARRAY:
		return _failure("adapterFailure")
	var composition_fields: Variant = _limit_fields(payload, "limits", _COMPOSITION_NAMES)
	if typeof(composition_fields) == TYPE_STRING:
		return _failure("adapterFailure")
	var document_fields: Variant = _limit_fields(payload, "documentLimits", _DOCUMENT_NAMES)
	if typeof(document_fields) == TYPE_STRING:
		return _failure("adapterFailure")
	var files: Array = payload["files"]
	var ceiling: int = int(Composition.standard_limits()["maximumDefinitions"])
	if files.size() > ceiling:
		return _failure("fileLimit")
	var sources: Array = []
	for item in files:
		if typeof(item) != TYPE_DICTIONARY:
			return _failure("adapterFailure")
		var file: Dictionary = item
		var count: int = 0
		for key in file:
			count += 1
			var field: String = str(key)
			if field != "path" and field != "bytesHex":
				return _failure("adapterFailure")
		if count != 2 or typeof(file.get("path", null)) != TYPE_STRING or typeof(file.get("bytesHex", null)) != TYPE_STRING:
			return _failure("adapterFailure")
		var file_bytes: Variant = _hex_to_bytes(str(file["bytesHex"]))
		if file_bytes == null:
			return _failure("adapterFailure")
		sources.append({"path": str(file["path"]), "data": file_bytes})
	var composition_limits: Variant = Composition.resolve_limits(composition_fields)
	if Errors.is_error(composition_limits):
		return _failure(_code(composition_limits))
	var document_limits: Variant = Storage.resolve_document_limits(document_fields)
	if Errors.is_error(document_limits):
		return _failure(_code(document_limits))
	var resolved: Variant = Linked.resolve(str(payload["rootPath"]), sources, composition_limits, null, document_limits)
	if Errors.is_error(resolved) or resolved == null or typeof(resolved) != TYPE_DICTIONARY:
		return _failure(_code(resolved))
	return _composition_response(resolved["composition"])

func _limit_fields(payload: Dictionary, key: String, names: Array[String]) -> Variant:
	if not payload.has(key):
		return {}
	var value: Variant = payload[key]
	if typeof(value) != TYPE_DICTIONARY:
		return "adapter"
	var provided: Dictionary = value
	var parsed: Dictionary = {}
	for field in provided:
		var known: bool = false
		var field_name: String = str(field)
		for allowed in names:
			if field_name == allowed:
				known = true
		if not known:
			return "adapter"
		var number: Variant = _integral(provided[field])
		if number == null:
			return "adapter"
		parsed[field_name] = int(number)
	return parsed

func _integral(value: Variant) -> Variant:
	var maximum: int = Portable.MAXIMUM_INTEGER
	if typeof(value) == TYPE_INT:
		var integer: int = value
		if integer < -maximum or integer > maximum:
			return null
		return integer
	if typeof(value) != TYPE_FLOAT:
		return null
	var number: float = value
	if not is_finite(number) or number != floor(number):
		return null
	if number < -float(maximum) or number > float(maximum):
		return null
	return int(number)

func _document_response(data: PackedByteArray, document: Object) -> String:
	var canonical: Variant = Storage.encode_text(document)
	if Errors.is_error(canonical):
		return _failure(_code(canonical))
	var binary: Variant = Storage.encode_binary(document)
	if Errors.is_error(binary):
		return _failure(_code(binary))
	var text_container: Variant = Storage.encode_text_container(document)
	if Errors.is_error(text_container):
		return _failure(_code(text_container))
	var raw: Variant = null
	if not _is_binary(data):
		var source: Variant = Structured.decode_utf8(data, 0, data.size())
		if Errors.is_error(source):
			return _failure(_code(source))
		var parsed: Variant = Parser.parse(str(source))
		if Errors.is_error(parsed) or parsed == null:
			return _failure(_code(parsed))
		raw = Storage.encode_text(parsed)
		if Errors.is_error(raw):
			return _failure(_code(raw))
	var adopted: Variant = Editing.adopt_document(document)
	if Errors.is_error(adopted):
		return _failure(_code(adopted))
	var snap: Variant = Editing.snapshot(adopted)
	if Errors.is_error(snap):
		return _failure(_code(snap))
	var adopted_bytes: Variant = Storage.encode_text(adopted)
	if Errors.is_error(adopted_bytes):
		return _failure(_code(adopted_bytes))
	var edited: Variant = snap
	var stale: bool = true
	if adopted.planes.size() > 0:
		var first: Object = adopted.planes[0]
		var identifier: Variant = Editing.stable_id(first)
		if identifier == null:
			return _failure("adapterFailure")
		var patch: Dictionary = {
			"expected_revision": str(snap["revision"]),
			"operations": [{"kind": "replace", "id": str(identifier), "plane": _edited_plane(first)}],
		}
		var applied: Variant = Editing.apply(patch, snap)
		if Errors.is_error(applied):
			return _failure(_code(applied))
		edited = applied
		var again: Variant = Editing.apply(patch, edited)
		stale = Errors.is_error(again) and str(again.code) == "staleRevision"
		if Errors.is_error(again) and str(again.code) != "staleRevision":
			return _failure(_code(again))
	var edited_bytes: Variant = Storage.encode_text(edited["document"])
	if Errors.is_error(edited_bytes):
		return _failure(_code(edited_bytes))
	return _success(canonical, binary, text_container, _utf8(Parser.serialize(document)), raw, adopted_bytes, adopted_bytes, edited_bytes, stale, _semantic_document(document))

func _composition_response(composition: Object) -> String:
	var canonical: Variant = Composition.encode(composition)
	if Errors.is_error(canonical):
		return _failure(_code(canonical))
	var profile: Variant = Composition.to_document(composition)
	if Errors.is_error(profile):
		return _failure(_code(profile))
	var binary: Variant = Storage.encode_binary(profile)
	if Errors.is_error(binary):
		return _failure(_code(binary))
	var text_container: Variant = Storage.encode_text_container(profile)
	if Errors.is_error(text_container):
		return _failure(_code(text_container))
	var adopted: Variant = Editing.adopt_composition(composition)
	if Errors.is_error(adopted):
		return _failure(_code(adopted))
	var snap: Variant = Editing.composition_snapshot(adopted)
	if Errors.is_error(snap):
		return _failure(_code(snap))
	var adopted_bytes: Variant = Composition.encode(adopted)
	if Errors.is_error(adopted_bytes):
		return _failure(_code(adopted_bytes))
	var edited: Variant = snap
	var stale: bool = true
	var root: Variant = adopted.root_entry()
	if Errors.is_error(root):
		return _failure(_code(root))
	var root_entry: Dictionary = root
	var root_document: Object = root_entry["document"]
	if root_document.planes.size() > 0:
		var replacement: Dictionary = {
			"id": str(root_entry["id"]),
			"document": _edited_document(root_document),
			"references": root_entry["references"],
		}
		var patch: Dictionary = {
			"expected_revision": str(snap["revision"]),
			"operations": [{"kind": "replaceEntry", "id": str(root_entry["id"]), "entry": replacement}],
		}
		var applied: Variant = Editing.apply_composition(patch, snap)
		if Errors.is_error(applied):
			return _failure(_code(applied))
		edited = applied
		var again: Variant = Editing.apply_composition(patch, edited)
		stale = Errors.is_error(again) and str(again.code) == "staleRevision"
		if Errors.is_error(again) and str(again.code) != "staleRevision":
			return _failure(_code(again))
	var edited_bytes: Variant = Composition.encode(edited["composition"])
	if Errors.is_error(edited_bytes):
		return _failure(_code(edited_bytes))
	return _success(canonical, binary, text_container, null, null, adopted_bytes, adopted_bytes, edited_bytes, stale, _semantic_composition(composition))

func _success(canonical: Variant, binary: Variant, text_container: Variant, legacy: Variant, raw: Variant, revision: Variant, adopted: Variant, edited: Variant, stale: bool, semantic: Dictionary) -> String:
	var response: Dictionary = {
		"ok": true,
		"canonicalHex": _hex(canonical),
		"binaryHex": _hex(binary),
		"textContainerHex": _hex(text_container),
		"legacyHex": null if legacy == null else _hex(legacy),
		"rawCanonicalHex": null if raw == null else _hex(raw),
		"revisionHex": _hex(revision),
		"adoptedHex": _hex(adopted),
		"editedHex": _hex(edited),
		"staleRejected": stale,
		"semantic": semantic,
	}
	return JSON.stringify(response)

func _semantic_document(document: Object) -> Dictionary:
	var planes: Array = []
	for item in document.planes:
		planes.append({
			"zBits": _bits(item.z),
			"xBits": _bits(item.x),
			"yBits": _bits(item.y),
			"label": item.label,
			"attributes": item.attributes,
			"body": item.body,
		})
	return {
		"version": document.version,
		"axis": document.axis,
		"title": document.title,
		"metadata": document.metadata,
		"preamble": document.preamble,
		"planes": planes,
	}

func _semantic_composition(composition: Object) -> Dictionary:
	var ordered: Array = []
	for item in composition.entries:
		var entry: Dictionary = item
		var placed: bool = false
		for index in ordered.size():
			var existing: Dictionary = ordered[index]
			if str(entry["id"]) < str(existing["id"]):
				ordered.insert(index, entry)
				placed = true
				break
		if not placed:
			ordered.append(entry)
	var entries: Array = []
	for ordered_item in ordered:
		var encoded_entry: Dictionary = ordered_item
		var references: Array = []
		for reference_item in encoded_entry["references"]:
			var reference: Dictionary = reference_item
			var target: String = str(reference["target_id"]) if reference.has("target_id") else str(reference.get("targetID", ""))
			references.append({"targetID": target, "attributes": reference["attributes"]})
		entries.append({
			"id": str(encoded_entry["id"]),
			"document": _semantic_document(encoded_entry["document"]),
			"references": references,
		})
	return {"rootID": str(composition.root_id), "entries": entries}

func _edited_document(document: Object) -> Object:
	var planes: Array = []
	for index in document.planes.size():
		var plane: Object = document.planes[index]
		if index == 0:
			planes.append(_edited_plane(plane))
		else:
			planes.append(plane)
	var copy := Documents.new()
	copy.version = document.version
	copy.axis = document.axis
	copy.title = document.title
	copy.metadata = document.metadata
	copy.preamble = document.preamble
	copy.planes = planes
	return copy

func _edited_plane(source: Object) -> Object:
	var plane := Planes.new()
	plane.z = source.z
	plane.x = source.x
	plane.y = source.y
	plane.label = source.label
	plane.attributes = source.attributes.duplicate(true)
	if str(source.body).is_empty():
		plane.body = "interchange edited"
	else:
		plane.body = str(source.body) + "\ninterchange edited"
	return plane

func _bits(value: Variant) -> Variant:
	if value == null:
		return null
	var number: float = value
	if number == 0.0:
		return "0000000000000000"
	var raw := PackedByteArray()
	raw.resize(8)
	raw.encode_double(0, number)
	var digits := "0123456789abcdef"
	var hex := ""
	for index in range(7, -1, -1):
		var byte: int = raw[index]
		hex += digits[byte >> 4]
		hex += digits[byte & 15]
	return hex

func _is_binary(data: PackedByteArray) -> bool:
	if data.size() < 8:
		return false
	return data[0] == 0x33 and data[1] == 0x6d and data[2] == 0x64 and data[3] == 0x62 and data[4] == 0x69 and data[5] == 0x6e and data[6] == 0x0d and data[7] == 0x0a

func _utf8(text: String) -> PackedByteArray:
	return text.to_utf8_buffer()

func _hex(data: Variant) -> String:
	var bytes: PackedByteArray = data
	var digits := "0123456789abcdef"
	var ascii := PackedByteArray()
	ascii.resize(bytes.size() * 2)
	for index in bytes.size():
		var byte: int = bytes[index]
		ascii[index * 2] = digits.unicode_at(byte >> 4)
		ascii[index * 2 + 1] = digits.unicode_at(byte & 15)
	return ascii.get_string_from_ascii()

func _hex_to_bytes(hex: String) -> Variant:
	if hex.length() % 2 != 0:
		return null
	var data := PackedByteArray()
	data.resize(hex.length() >> 1)
	for index in data.size():
		var high: int = _nibble(hex.unicode_at(index * 2))
		var low: int = _nibble(hex.unicode_at(index * 2 + 1))
		if high < 0 or low < 0:
			return null
		data[index] = high * 16 + low
	return data

func _nibble(unit: int) -> int:
	if unit >= 48 and unit <= 57:
		return unit - 48
	if unit >= 97 and unit <= 102:
		return unit - 87
	return -1

func _code(value: Variant) -> String:
	if not Errors.is_error(value):
		return "adapterFailure"
	var code: String = str(value.code)
	if code == "invalidPath" or code == "duplicatePath":
		return "filePath"
	if code == "invalidLedger" or code == "invalidGlyph":
		return "fileLedger"
	if code == "missingFile":
		return "missingFile"
	if code == "inputLimit":
		return "fileLimit"
	return code

func _failure(code: String) -> String:
	return JSON.stringify({"ok": false, "error": code})

class _Scan:
	extends RefCounted

	const _Unicode = preload("res://addons/threemd/nfc.gd")
	const _Numbers = preload("res://addons/threemd/number.gd")

	var source: String = ""
	var index: int = 0
	var failed: bool = false

	func parse(text: String) -> Variant:
		source = text
		index = 0
		failed = false
		var parsed: Variant = _value(0)
		_space()
		if failed or index != source.length():
			failed = true
			return null
		return parsed

	func _space() -> void:
		while index < source.length():
			var unit: int = source.unicode_at(index)
			if unit != 9 and unit != 10 and unit != 13 and unit != 32:
				return
			index += 1

	func _value(depth: int) -> Variant:
		if failed:
			return null
		if depth > 64:
			failed = true
			return null
		_space()
		if index >= source.length():
			failed = true
			return null
		var unit: int = source.unicode_at(index)
		if unit == 34:
			return _string()
		if unit == 123:
			return _object(depth)
		if unit == 91:
			return _array(depth)
		var start: int = index
		while index < source.length():
			var current: int = source.unicode_at(index)
			if current == 9 or current == 10 or current == 13 or current == 32 or current == 44 or current == 93 or current == 125:
				break
			index += 1
		if index == start:
			failed = true
			return null
		var literal: String = source.substr(start, index - start)
		if literal == "null":
			return null
		if literal == "true":
			return true
		if literal == "false":
			return false
		if not _json_number(literal):
			failed = true
			return null
		var number: Variant = _Numbers.parse_finite(literal)
		if number == null or not is_finite(float(number)):
			failed = true
			return null
		return number

	func _json_number(literal: String) -> bool:
		var cursor: int = 0
		if literal.begins_with("-"):
			cursor = 1
		if cursor >= literal.length():
			return false
		if literal.unicode_at(cursor) == 48:
			cursor += 1
		elif literal.unicode_at(cursor) >= 49 and literal.unicode_at(cursor) <= 57:
			while cursor < literal.length():
				var integer_digit: int = literal.unicode_at(cursor)
				if integer_digit < 48 or integer_digit > 57:
					break
				cursor += 1
		else:
			return false
		if cursor < literal.length() and literal.unicode_at(cursor) == 46:
			cursor += 1
			var fraction: int = cursor
			while cursor < literal.length():
				var fraction_digit: int = literal.unicode_at(cursor)
				if fraction_digit < 48 or fraction_digit > 57:
					break
				cursor += 1
			if cursor == fraction:
				return false
		if cursor < literal.length() and (literal.unicode_at(cursor) == 101 or literal.unicode_at(cursor) == 69):
			cursor += 1
			if cursor < literal.length() and (literal.unicode_at(cursor) == 43 or literal.unicode_at(cursor) == 45):
				cursor += 1
			var exponent: int = cursor
			while cursor < literal.length():
				var exponent_digit: int = literal.unicode_at(cursor)
				if exponent_digit < 48 or exponent_digit > 57:
					break
				cursor += 1
			if cursor == exponent:
				return false
		return cursor == literal.length()

	func _object(depth: int) -> Dictionary:
		index += 1
		_space()
		var fields: Dictionary = {}
		if index < source.length() and source.unicode_at(index) == 125:
			index += 1
			return fields
		var seen: Dictionary = {}
		while not failed:
			var key: String = _Unicode.nfc(_string())
			if failed:
				return fields
			if seen.has(key):
				failed = true
				return fields
			seen[key] = true
			_expect(58)
			var child: Variant = _value(depth + 1)
			if failed:
				return fields
			fields[key] = child
			_space()
			if index < source.length() and source.unicode_at(index) == 125:
				index += 1
				return fields
			_expect(44)
		failed = true
		return fields

	func _array(depth: int) -> Array:
		index += 1
		_space()
		var items: Array = []
		if index < source.length() and source.unicode_at(index) == 93:
			index += 1
			return items
		while not failed:
			var child: Variant = _value(depth + 1)
			if failed:
				return items
			items.append(child)
			_space()
			if index < source.length() and source.unicode_at(index) == 93:
				index += 1
				return items
			_expect(44)
		failed = true
		return items

	func _expect(unit: int) -> void:
		_space()
		if index >= source.length() or source.unicode_at(index) != unit:
			failed = true
			return
		index += 1

	func _string() -> String:
		_space()
		if index >= source.length() or source.unicode_at(index) != 34:
			failed = true
			return ""
		index += 1
		var parts: PackedStringArray = PackedStringArray()
		var start: int = index
		while index < source.length():
			var unit: int = source.unicode_at(index)
			if unit < 32:
				failed = true
				return ""
			if unit == 34:
				parts.append(source.substr(start, index - start))
				index += 1
				return "".join(parts)
			if unit != 92:
				index += 1
				continue
			parts.append(source.substr(start, index - start))
			index += 1
			if index >= source.length():
				failed = true
				return ""
			var escape: int = source.unicode_at(index)
			index += 1
			var decoded: String = ""
			if escape == 34 or escape == 92 or escape == 47:
				decoded = char(escape)
			elif escape == 98:
				decoded = "\b"
			elif escape == 102:
				decoded = "\f"
			elif escape == 110:
				decoded = "\n"
			elif escape == 114:
				decoded = "\r"
			elif escape == 116:
				decoded = "\t"
			elif escape == 117:
				var point: int = _hex4()
				if failed:
					return ""
				if point >= 0xD800 and point <= 0xDBFF:
					if index + 1 >= source.length() or source.unicode_at(index) != 92 or source.unicode_at(index + 1) != 117:
						failed = true
						return ""
					index += 2
					var low: int = _hex4()
					if failed or low < 0xDC00 or low > 0xDFFF:
						failed = true
						return ""
					point = 0x10000 + ((point - 0xD800) << 10) + (low - 0xDC00)
				elif point >= 0xDC00 and point <= 0xDFFF:
					failed = true
					return ""
				# Godot replaces U+0000 with U+FFFD when a string is built, which would hide a
				# rejected path control. Keep a different C0 control so the path check still fails.
				if point == 0:
					point = 1
				decoded = char(point)
			else:
				failed = true
				return ""
			parts.append(decoded)
			start = index
		failed = true
		return ""

	func _hex4() -> int:
		if index + 4 > source.length():
			failed = true
			return 0
		var point: int = 0
		for _hex_index in 4:
			var unit: int = source.unicode_at(index)
			index += 1
			var nibble: int = -1
			if unit >= 48 and unit <= 57:
				nibble = unit - 48
			elif unit >= 97 and unit <= 102:
				nibble = unit - 87
			elif unit >= 65 and unit <= 70:
				nibble = unit - 55
			if nibble < 0:
				failed = true
				return 0
			point = point * 16 + nibble
		return point
