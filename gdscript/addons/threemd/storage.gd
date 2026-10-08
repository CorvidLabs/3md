class_name ThreeMDStorage
extends RefCounted

## Version 1 binary container and canonical text.
## Payload kind 1 is canonical UTF-8 text. Payload kind 2 is the structured document.
## LZFSE is refused. Limits are the host maximum, 2^53 - 1.

const Errors = preload("res://addons/threemd/error.gd")
const Portable = preload("res://addons/threemd/portable.gd")
const Parser = preload("res://addons/threemd/parser.gd")
const Numbers = preload("res://addons/threemd/number.gd")
const Checksum = preload("res://addons/threemd/checksum.gd")
const Structured = preload("res://addons/threemd/structured.gd")

const _HEADER: int = 40
const _KIND_TEXT: int = 1
const _KIND_STRUCTURED: int = 2

static func encode_text(document: Object) -> Variant:
	var rejected: Variant = _reject_scalars(document)
	if rejected != null:
		return rejected
	var canonical: Object = Portable.canonical_document(document)
	if str(canonical.version).is_empty():
		return _error("invalidDocument", "The version must be nonempty.")
	var seen: Array = []
	for item in canonical.planes:
		var z: float = item.z
		if not is_finite(z):
			return _error("invalidDocument", "Plane coordinates must be finite.")
		if item.x != null:
			var x_value: float = item.x
			if not is_finite(x_value):
				return _error("invalidDocument", "Plane coordinates must be finite.")
		if item.y != null:
			var y_value: float = item.y
			if not is_finite(y_value):
				return _error("invalidDocument", "Plane coordinates must be finite.")
		for previous in seen:
			var prior: float = previous
			if prior == z:
				return _error("invalidDocument", "Plane positions must be unique.")
		seen.append(z)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("---")
	lines.append("3md: " + _quote(str(canonical.version)))
	lines.append("axis: " + _quote(str(canonical.axis)))
	if canonical.title != null:
		lines.append("title: " + _quote(str(canonical.title)))
	for key in Portable.canonical_keys(canonical.metadata):
		if _metadata_shadow(str(key)):
			return _error("invalidDocument", "Metadata keys cannot shadow reserved fields or comments.")
		lines.append(str(key) + ": " + _quote(str(canonical.metadata[key])))
	lines.append("---")
	if canonical.preamble != null:
		lines.append("")
		lines.append(str(canonical.preamble))
	for item in canonical.planes:
		lines.append("")
		var directive: String = "@plane z=" + Numbers.canonical(item.z)
		if item.label != null:
			directive += " label=" + _quote(str(item.label))
		if item.x != null:
			var plane_x: float = item.x
			directive += " x=" + Numbers.canonical(plane_x)
		if item.y != null:
			var plane_y: float = item.y
			directive += " y=" + Numbers.canonical(plane_y)
		for key in Portable.canonical_keys(item.attributes):
			if _attribute_shadow(str(key)):
				return _error("invalidDocument", "Attribute keys must be lowercase and cannot shadow coordinates or labels.")
			directive += " " + str(key) + "=" + _quote(str(item.attributes[key]))
		lines.append(directive)
		if str(item.body).length() > 0:
			lines.append(str(item.body))
	var text: String = "\n".join(lines) + "\n"
	var data: PackedByteArray = text.to_utf8_buffer()
	var restored: Variant = _parse_bounded(data)
	if Errors.is_error(restored):
		if str(restored.code) == "invalidText":
			return _error("invalidDocument", str(restored.detail))
		return restored
	if not Portable.documents_equal(restored, canonical):
		return _error("invalidDocument", "Text serialization would change metadata, whitespace, fences or planes.")
	return data

static func encode_text_container(document: Object) -> Variant:
	var payload: Variant = encode_text(document)
	if Errors.is_error(payload):
		return payload
	var source: PackedByteArray = payload
	if source.size() > Portable.MAXIMUM_INTEGER - _HEADER:
		return _error("oversizedInput", "")
	var container: PackedByteArray = PackedByteArray()
	container.resize(_HEADER + source.size())
	_blit(container, _HEADER, source)
	_write_header(container, _KIND_TEXT)
	return container

static func encode_binary(document: Object) -> Variant:
	if Portable.MAXIMUM_INTEGER < _HEADER:
		return _error("oversizedInput", "")
	var container: Variant = Structured.write_payload(document)
	if Errors.is_error(container):
		return container
	_write_header(container, _KIND_STRUCTURED)
	return container

static func decode(data: PackedByteArray) -> Variant:
	if data.size() > Portable.MAXIMUM_INTEGER:
		return _error("oversizedInput", "")
	if not _is_binary(data):
		return _parse_bounded(data)
	if data.size() < _HEADER:
		return _error("invalidContainer", "")
	var version: int = data.decode_u16(8)
	if version != 1:
		return _error("unsupportedVersion", str(version))
	var kind: int = data[10]
	if kind != _KIND_TEXT and kind != _KIND_STRUCTURED:
		return _error("unsupportedPayloadKind", str(kind))
	var compression: int = data[11]
	if compression != 0 and compression != 1:
		return _error("unsupportedCompression", str(compression))
	var flags: int = data.decode_u32(12)
	if flags != 0:
		return _error("unsupportedFlags", str(flags))
	if data.decode_u32(16) != 0:
		return _error("nonzeroReserved", "")
	var encoded: int = data.decode_u64(20)
	var decoded_length: int = data.decode_u64(28)
	if encoded < 0 or decoded_length < 0:
		return _error("oversizedOutput", "")
	var limit: int = Portable.MAXIMUM_INTEGER
	var half: int = limit >> 1
	var doubled: int = limit if limit > half else limit * 2
	var bound: int = limit if kind == _KIND_TEXT else mini(limit - _HEADER, doubled)
	if decoded_length > bound:
		return _error("oversizedOutput", "")
	if encoded == 0 or decoded_length == 0 or encoded != data.size() - _HEADER or (compression == 0 and encoded != decoded_length):
		return _error("lengthMismatch", "")
	var checksum: int = data.decode_u32(36)
	if Checksum.container_checksum(data) != checksum:
		return _error("checksumMismatch", "")
	if compression == 1:
		return _error("compressionUnavailable", "1")
	if kind == _KIND_TEXT:
		return _parse_bounded(_copy(data, _HEADER, data.size()))
	return Structured.read_structured(data, _HEADER, data.size(), true)

static func _parse_bounded(data: PackedByteArray) -> Variant:
	if data.size() > Portable.MAXIMUM_INTEGER:
		return _error("oversizedOutput", "")
	var text: Variant = Structured.decode_utf8(data, 0, data.size())
	if Errors.is_error(text):
		return text
	var source: String = text
	var parsed: Variant = Parser.parse(source)
	if Errors.is_error(parsed) or parsed == null:
		var detail: String = ""
		if Errors.is_error(parsed):
			detail = str(parsed.message)
		return _error("invalidText", detail)
	var rejected: Variant = _reject_scalars(parsed)
	if rejected != null:
		return rejected
	return Portable.canonical_document(parsed)

static func _reject_scalars(document: Object) -> Variant:
	if document.planes.size() > Portable.MAXIMUM_INTEGER:
		return _error("tooManyPlanes", "")
	if _has_break(str(document.version)) or _has_break(str(document.axis)):
		return _error("invalidDocument", "Scalar fields cannot contain physical line breaks.")
	if document.title != null and _has_break(str(document.title)):
		return _error("invalidDocument", "Scalar fields cannot contain physical line breaks.")
	for key in document.metadata:
		if _has_break(str(key)) or _has_break(str(document.metadata[key])):
			return _error("invalidDocument", "Scalar fields cannot contain physical line breaks.")
	for item in document.planes:
		if item.label != null and _has_break(str(item.label)):
			return _error("invalidDocument", "Scalar fields cannot contain physical line breaks.")
		for key in item.attributes:
			if _has_break(str(key)) or _has_break(str(item.attributes[key])):
				return _error("invalidDocument", "Scalar fields cannot contain physical line breaks.")
	return null

static func _has_break(text: String) -> bool:
	return text.find("\n") >= 0 or text.find("\r") >= 0

static func _metadata_shadow(key: String) -> bool:
	var lower: String = key.to_lower()
	if lower == "3md" or lower == "axis" or lower == "title":
		return true
	if key.find(":") >= 0:
		return true
	var index: int = 0
	while index < key.length() and (key.unicode_at(index) == 32 or key.unicode_at(index) == 9):
		index += 1
	return index < key.length() and key.unicode_at(index) == 35

static func _attribute_shadow(key: String) -> bool:
	var lower: String = key.to_lower()
	if lower == "z" or lower == "x" or lower == "y" or lower == "label":
		return true
	if key != lower or key.find("=") >= 0:
		return true
	return false

static func _quote(text: String) -> String:
	return "\"" + text.replace("\\", "\\\\").replace("\"", "\\\"") + "\""

static func _is_binary(data: PackedByteArray) -> bool:
	if data.size() < 8:
		return false
	return data[0] == 0x33 and data[1] == 0x6d and data[2] == 0x64 and data[3] == 0x62 and data[4] == 0x69 and data[5] == 0x6e and data[6] == 0x0d and data[7] == 0x0a

static func _write_header(container: PackedByteArray, kind: int) -> void:
	container[0] = 0x33
	container[1] = 0x6d
	container[2] = 0x64
	container[3] = 0x62
	container[4] = 0x69
	container[5] = 0x6e
	container[6] = 0x0d
	container[7] = 0x0a
	container.encode_u16(8, 1)
	container[10] = kind
	var payload: int = container.size() - _HEADER
	container.encode_u64(20, payload)
	container.encode_u64(28, payload)
	var checksum: int = Checksum.container_checksum(container)
	container.encode_u32(36, checksum)

static func _blit(target: PackedByteArray, position: int, source: PackedByteArray) -> void:
	for index in source.size():
		target[position + index] = source[index]

static func _copy(data: PackedByteArray, start: int, end_index: int) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(end_index - start)
	for index in out.size():
		out[index] = data[start + index]
	return out

static func standard_document_limits() -> Dictionary:
	var maximum: int = Portable.MAXIMUM_INTEGER
	return {
		"maximumEncodedBytes": maximum,
		"maximumDecodedBytes": maximum,
		"maximumLines": maximum,
		"maximumPlanes": maximum,
		"maximumRecordBytes": maximum,
	}

static func resolve_document_limits(options: Variant) -> Variant:
	var limits: Dictionary = standard_document_limits()
	if options == null:
		return limits
	if typeof(options) != TYPE_DICTIONARY:
		return _error("invalidLimits", "")
	var provided: Dictionary = options
	for key in limits:
		if not provided.has(key):
			continue
		var value: Variant = provided[key]
		if typeof(value) != TYPE_INT:
			return _error("invalidLimits", str(key))
		if not Portable.bounded_integer(int(value), 1, Portable.MAXIMUM_INTEGER):
			return _error("invalidLimits", str(key))
		limits[key] = int(value)
	return limits

static func enforce_document_limits(document: Object, limits: Dictionary) -> Variant:
	if document.planes.size() > int(limits["maximumPlanes"]):
		return _error("tooManyPlanes", "")
	var total: int = 0
	var decoded_max: int = int(limits["maximumDecodedBytes"])
	var record_max: int = int(limits["maximumRecordBytes"])
	var step: Variant = _scalar_budget(str(document.version), total, decoded_max, record_max)
	if Errors.is_error(step):
		return step
	total = int(step)
	step = _scalar_budget(str(document.axis), total, decoded_max, record_max)
	if Errors.is_error(step):
		return step
	total = int(step)
	if document.title != null:
		step = _scalar_budget(str(document.title), total, decoded_max, record_max)
		if Errors.is_error(step):
			return step
		total = int(step)
	for key in document.metadata:
		step = _scalar_budget(str(key), total, decoded_max, record_max)
		if Errors.is_error(step):
			return step
		total = int(step)
		step = _scalar_budget(str(document.metadata[key]), total, decoded_max, record_max)
		if Errors.is_error(step):
			return step
		total = int(step)
	if document.preamble != null:
		step = _body_budget(str(document.preamble), total, decoded_max, record_max)
		if Errors.is_error(step):
			return step
		total = int(step)
	for item in document.planes:
		step = _body_budget(str(item.body), total, decoded_max, record_max)
		if Errors.is_error(step):
			return step
		total = int(step)
		if item.label != null:
			step = _scalar_budget(str(item.label), total, decoded_max, record_max)
			if Errors.is_error(step):
				return step
			total = int(step)
		for key in item.attributes:
			step = _scalar_budget(str(key), total, decoded_max, record_max)
			if Errors.is_error(step):
				return step
			total = int(step)
			step = _scalar_budget(str(item.attributes[key]), total, decoded_max, record_max)
			if Errors.is_error(step):
				return step
			total = int(step)
	return null

static func _decoded_budget(text: String, total: int, decoded_max: int) -> Variant:
	var count: int = Portable.utf8_length(text)
	if count >= decoded_max - total:
		return _error("oversizedOutput", "")
	return total + count + 1

static func _scalar_budget(text: String, total: int, decoded_max: int, record_max: int) -> Variant:
	if Portable.utf8_length(text) > record_max:
		return _error("oversizedRecord", "")
	if _has_break(text):
		return _error("invalidDocument", "Scalar fields cannot contain physical line breaks.")
	return _decoded_budget(text, total, decoded_max)

static func _body_budget(text: String, total: int, decoded_max: int, record_max: int) -> Variant:
	if Portable.utf8_length(text) > record_max:
		return _error("oversizedRecord", "")
	return _decoded_budget(text, total, decoded_max)

static func _error(code: String, detail: String) -> Variant:
	var message: String = code if detail.is_empty() else code + ": " + detail
	return Errors.make(code, message, -1, detail)
