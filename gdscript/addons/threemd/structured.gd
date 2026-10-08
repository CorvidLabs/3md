extends RefCounted

## Payload kind 2, the structured document record (SPEC.md 11.3).
## storage.gd owns the 40-byte header. This script reads and writes the payload.

const Errors = preload("res://addons/threemd/error.gd")
const Portable = preload("res://addons/threemd/portable.gd")
const Numbers = preload("res://addons/threemd/number.gd")
const Unicode = preload("res://addons/threemd/nfc.gd")
const Parser = preload("res://addons/threemd/parser.gd")
const Documents = preload("res://addons/threemd/document.gd")
const Planes = preload("res://addons/threemd/plane.gd")
const Big = preload("res://addons/threemd/big.gd")

const _INTEGER_MINIMUM: int = -134217728
const _INTEGER_MAXIMUM: int = 134217727
const _SCALAR_BREAK: String = "Scalar fields cannot contain physical line breaks."
const _FINITE: String = "Plane coordinates must be finite."
const _UNIQUE: String = "Plane positions must be unique."
const _VERSION: String = "The version must be nonempty."
const _AXIS: String = "The axis must already be trimmed and lowercase."
const _METADATA_KEY: String = "Metadata keys cannot shadow reserved fields or comments."
const _ATTRIBUTE_KEY: String = "Attribute keys must be lowercase and cannot shadow coordinates or labels."
const _EQUIVALENT: String = "Canonically equivalent dictionary keys cannot be represented faithfully."
const _PREAMBLE_PLANES: String = "A preamble requires at least one plane."
const _DIRECTIVE: String = "The plane directive would not parse back to the same plane."
const _EMPTY_PREAMBLE: String = "An empty preamble cannot be represented."
const _TRAILING_CR: String = "A segment cannot end with a carriage return."
const _CRLF: String = "A segment cannot contain CRLF."
const _BLANK_EDGE: String = "A segment cannot begin or end with a blank line."
const _DIRECTIVE_LINE: String = "A segment line outside a fence cannot start a plane directive."
const _OPEN_FENCE: String = "Only the last plane body may end inside an open fence."
const _DOCUMENT_FLAGS: String = "The structured payload sets an undefined document flag bit."
const _PLANE_FLAGS: String = "The structured payload sets an undefined plane flag bit or has no z coordinate."
const _VAR_TOO_LONG: String = "A Var continues past the last byte its field allows."
const _VAR_MINIMAL: String = "A Var in the structured payload is not minimal."
const _NUMBER_FORM: String = "A number in the structured payload is not in its canonical form."
const _KEY_ORDER: String = "Keys in a structured payload map must be in strictly increasing UTF-8 byte order."

var _bytes: PackedByteArray = PackedByteArray()
var _position: int = 0
var _end: int = 0
var _fault: Variant = null
var _string_start: int = 0
var _string_length: int = 0

static func decode_utf8(bytes: PackedByteArray, start: int, end_index: int) -> Variant:
	var index: int = start
	while index < end_index:
		var byte: int = bytes[index]
		var width: int = 1
		if byte < 0x80:
			width = 1
		elif byte < 0xC2 or byte > 0xF4:
			return _error("invalidUTF8", "")
		elif byte < 0xE0:
			width = 2
			if index + 1 >= end_index or (bytes[index + 1] & 0xC0) != 0x80:
				return _error("invalidUTF8", "")
		elif byte < 0xF0:
			width = 3
			if index + 2 >= end_index:
				return _error("invalidUTF8", "")
			var second: int = bytes[index + 1]
			var third: int = bytes[index + 2]
			if (second & 0xC0) != 0x80 or (third & 0xC0) != 0x80:
				return _error("invalidUTF8", "")
			if (byte == 0xE0 and second < 0xA0) or (byte == 0xED and second > 0x9F):
				return _error("invalidUTF8", "")
		else:
			width = 4
			if index + 3 >= end_index:
				return _error("invalidUTF8", "")
			var second4: int = bytes[index + 1]
			var third4: int = bytes[index + 2]
			var fourth: int = bytes[index + 3]
			if (second4 & 0xC0) != 0x80 or (third4 & 0xC0) != 0x80 or (fourth & 0xC0) != 0x80:
				return _error("invalidUTF8", "")
			if (byte == 0xF0 and second4 < 0x90) or (byte == 0xF4 and second4 > 0x8F):
				return _error("invalidUTF8", "")
		index += width
	return bytes.slice(start, end_index).get_string_from_utf8()

static func read_structured(bytes: PackedByteArray, start: int, end_index: int, materialize: bool) -> Variant:
	var reader = load("res://addons/threemd/structured.gd").new()
	var result: Variant = reader._read(bytes, start, end_index)
	if Errors.is_error(result):
		return result
	if not materialize:
		return null
	return result

static func write_payload(document: Object) -> Variant:
	var strings: Array = []
	var metadata: Array = _ordered(document.metadata)
	if _has_equivalent(_entries(document.metadata)):
		var rejected: Variant = _reject_scalars(document)
		if rejected != null:
			return rejected
	var has_title: bool = document.title != null
	var has_preamble: bool = document.preamble != null
	var flags: int = (1 if has_title else 0) | (2 if has_preamble else 0)
	_add_string(strings, str(document.version))
	_add_string(strings, str(document.axis))
	if has_title:
		_add_string(strings, str(document.title))
	for entry in metadata:
		_add_string(strings, str(entry[0]))
		_add_string(strings, str(entry[1]))
	if has_preamble:
		_add_string(strings, str(document.preamble))
	var plane_count: int = document.planes.size()
	var plane_flags: Array = []
	var coordinates: Array = []
	var attribute_lists: Array = []
	for item in document.planes:
		var z: float = _nonnegative_zero(item.z)
		var x_present: bool = item.x != null
		var y_present: bool = item.y != null
		var x: float = 0.0
		var y: float = 0.0
		if x_present:
			x = _nonnegative_zero(item.x)
		if y_present:
			y = _nonnegative_zero(item.y)
		var z_form: int = _number_form(z)
		var x_form: int = 0 if not x_present else _number_form(x)
		var y_form: int = 0 if not y_present else _number_form(y)
		var label_present: bool = item.label != null
		var flag: int = z_form | (x_form << 2) | (y_form << 4) | (0x40 if label_present else 0)
		plane_flags.append(flag)
		coordinates.append([z, x_present, x, y_present, y])
		if label_present:
			_add_string(strings, str(item.label))
		var ordered_attributes: Array = _ordered(item.attributes)
		attribute_lists.append(ordered_attributes)
		for attribute in ordered_attributes:
			_add_string(strings, str(attribute[0]))
			_add_string(strings, str(attribute[1]))
		_add_string(strings, str(item.body))
	var size: int = 1 + _var_size(metadata.size()) + _var_size(plane_count)
	var cursor: int = 0
	size += _string_size_at(strings, cursor)
	cursor += 1
	size += _string_size_at(strings, cursor)
	cursor += 1
	if has_title:
		size += _string_size_at(strings, cursor)
		cursor += 1
	for _entry in metadata:
		size += _string_size_at(strings, cursor)
		cursor += 1
		size += _string_size_at(strings, cursor)
		cursor += 1
	if has_preamble:
		size += _string_size_at(strings, cursor)
		cursor += 1
	for index in plane_count:
		var point: Array = coordinates[index]
		var flag_value: int = plane_flags[index]
		size += 1
		size += _number_size(point[0], flag_value & 3)
		if point[1] == true:
			size += _number_size(point[2], (flag_value >> 2) & 3)
		if point[3] == true:
			size += _number_size(point[4], (flag_value >> 4) & 3)
		if (flag_value & 0x40) != 0:
			size += _string_size_at(strings, cursor)
			cursor += 1
		var counted_attributes: Array = attribute_lists[index]
		size += _var_size(counted_attributes.size())
		for _attr in counted_attributes:
			size += _string_size_at(strings, cursor)
			cursor += 1
			size += _string_size_at(strings, cursor)
			cursor += 1
		size += _string_size_at(strings, cursor)
		cursor += 1
	if cursor != strings.size():
		return _error("invalidDocument", "Text serialization would change metadata, whitespace, fences or planes.")
	if size > Portable.MAXIMUM_INTEGER - 40:
		return _error("oversizedInput", "")
	var output: PackedByteArray = PackedByteArray()
	output.resize(40 + size)
	var position: int = 40
	var next: int = 0
	output[position] = flags
	position += 1
	position = _write_queued(output, position, strings, next)
	next += 1
	position = _write_queued(output, position, strings, next)
	next += 1
	if has_title:
		position = _write_queued(output, position, strings, next)
		next += 1
	position = _write_var(output, position, metadata.size())
	for _entry in metadata:
		position = _write_queued(output, position, strings, next)
		next += 1
		position = _write_queued(output, position, strings, next)
		next += 1
	if has_preamble:
		position = _write_queued(output, position, strings, next)
		next += 1
	position = _write_var(output, position, plane_count)
	for index in plane_count:
		var flag_value: int = plane_flags[index]
		var point: Array = coordinates[index]
		output[position] = flag_value
		position += 1
		position = _write_number(output, position, point[0], flag_value & 3)
		if point[1] == true:
			position = _write_number(output, position, point[2], (flag_value >> 2) & 3)
		if point[3] == true:
			position = _write_number(output, position, point[4], (flag_value >> 4) & 3)
		if (flag_value & 0x40) != 0:
			position = _write_queued(output, position, strings, next)
			next += 1
		var emitted_attributes: Array = attribute_lists[index]
		position = _write_var(output, position, emitted_attributes.size())
		for _attr in emitted_attributes:
			position = _write_queued(output, position, strings, next)
			next += 1
			position = _write_queued(output, position, strings, next)
			next += 1
		position = _write_queued(output, position, strings, next)
		next += 1
	if position != output.size():
		return _error("invalidDocument", "Text serialization would change metadata, whitespace, fences or planes.")
	var checked: Variant = read_structured(output, 40, output.size(), false)
	if Errors.is_error(checked):
		return checked
	return output

func _read(bytes: PackedByteArray, start: int, end_index: int) -> Variant:
	_bytes = bytes
	_position = start
	_end = end_index
	_fault = null
	var record: int = Portable.MAXIMUM_INTEGER
	var flags: int = _u8()
	if _fault != null:
		return _fault
	if (flags & 0xFC) != 0:
		return _fail("invalidContainer", _DOCUMENT_FLAGS)
	var version: String = _read_scalar(record)
	if _fault != null:
		return _fault
	if version.is_empty():
		return _fail("invalidDocument", _VERSION)
	var axis: String = _read_scalar(record)
	if _fault != null:
		return _fault
	if not _axis_normalized(axis):
		return _fail("invalidDocument", _AXIS)
	var title: Variant = null
	if (flags & 1) != 0:
		title = _read_scalar(record)
		if _fault != null:
			return _fault
	var metadata_count: int = _count(2)
	if _fault != null:
		return _fault
	var metadata: Dictionary = {}
	var metadata_keys: Array = []
	var previous: String = ""
	for index in metadata_count:
		var key: String = _read_scalar(record)
		if _fault != null:
			return _fault
		if index > 0 and Unicode.compare(previous, key) >= 0:
			return _fail("invalidContainer", _KEY_ORDER)
		if not _metadata_key_valid(key):
			return _fail("invalidDocument", _METADATA_KEY)
		var value: String = _read_scalar(record)
		if _fault != null:
			return _fault
		metadata[key] = value
		metadata_keys.append(key)
		previous = key
	var equivalent: Variant = _equivalent(metadata_keys)
	if equivalent != null:
		return equivalent
	var preamble: Variant = null
	if (flags & 2) != 0:
		var preamble_text: String = _read_segment(record - 1 if record > 0 else record)
		if _fault != null:
			return _fault
		var preamble_error: Variant = _check_segment(preamble_text, true, false)
		if preamble_error != null:
			return preamble_error
		preamble = preamble_text
	var plane_count: int = _count(4)
	if _fault != null:
		return _fault
	if plane_count > Portable.MAXIMUM_INTEGER:
		return _fail("tooManyPlanes", "")
	if preamble != null and plane_count == 0:
		return _fail("invalidDocument", _PREAMBLE_PLANES)
	var planes: Array = []
	var positions: Array = []
	var marked: Array = []
	for index in plane_count:
		var plane_flags: int = _u8()
		if _fault != null:
			return _fault
		var z_form: int = plane_flags & 3
		var x_form: int = (plane_flags >> 2) & 3
		var y_form: int = (plane_flags >> 4) & 3
		if (plane_flags & 0x80) != 0 or z_form == 0:
			return _fail("invalidContainer", _PLANE_FLAGS)
		var z: float = _read_number(z_form)
		if _fault != null:
			return _fault
		var x: Variant = null
		var y: Variant = null
		if x_form != 0:
			x = _read_number(x_form)
			if _fault != null:
				return _fault
		if y_form != 0:
			y = _read_number(y_form)
			if _fault != null:
				return _fault
		var label: Variant = null
		if (plane_flags & 0x40) != 0:
			label = _read_scalar(record)
			if _fault != null:
				return _fault
		var attribute_count: int = _count(3)
		if _fault != null:
			return _fault
		var attributes: Dictionary = {}
		var attribute_keys: Array = []
		var attribute_values: Array = []
		var any_quote: bool = false
		var keys_valid: bool = true
		previous = ""
		for entry in attribute_count:
			var attribute_key: String = _read_scalar(record)
			if _fault != null:
				return _fault
			if entry > 0 and Unicode.compare(previous, attribute_key) >= 0:
				return _fail("invalidContainer", _KEY_ORDER)
			if attribute_key.find("\"") >= 0 or attribute_key.find("'") >= 0:
				any_quote = true
			if keys_valid and not _attribute_key_valid(attribute_key):
				keys_valid = false
			var attribute_value: String = _read_scalar(record)
			if _fault != null:
				return _fault
			attributes[attribute_key] = attribute_value
			attribute_keys.append(attribute_key)
			attribute_values.append(attribute_value)
			previous = attribute_key
		var attribute_equivalent: Variant = _equivalent(attribute_keys)
		if attribute_equivalent != null:
			return attribute_equivalent
		if any_quote:
			marked.append([z, x, y, label, attribute_keys, attribute_values])
		elif not keys_valid:
			return _fail("invalidDocument", _ATTRIBUTE_KEY)
		var body: String = _read_segment(record)
		if _fault != null:
			return _fault
		var body_error: Variant = _check_segment(body, false, index + 1 == plane_count)
		if body_error != null:
			return body_error
		var plane = Planes.new()
		plane.z = z
		plane.x = x
		plane.y = y
		plane.label = label
		plane.attributes = attributes
		plane.body = body
		planes.append(plane)
		positions.append(z)
	if _position != _end:
		return _fail("lengthMismatch", "")
	var unique: Variant = _unique_positions(positions)
	if unique != null:
		return unique
	for mark in marked:
		var round_trip: Variant = _directive_round_trip(mark[0], mark[1], mark[2], mark[3], mark[4], mark[5])
		if round_trip != null:
			return round_trip
	var document = Documents.new()
	document.version = version
	document.axis = axis
	document.title = title
	document.metadata = metadata
	document.preamble = preamble
	document.planes = planes
	return document

func _u8() -> int:
	if _position >= _end:
		_fail("lengthMismatch", "")
		return 0
	var byte: int = _bytes[_position]
	_position += 1
	return byte

func _read_var(maximum_bytes: int) -> int:
	if _fault != null:
		return 0
	if _position >= _end:
		_fail("lengthMismatch", "")
		return 0
	var byte: int = _bytes[_position]
	_position += 1
	if byte < 128:
		return byte
	var value: int = byte & 127
	var maximum: int = Portable.MAXIMUM_INTEGER
	for index in range(1, maximum_bytes):
		if _position >= _end:
			_fail("lengthMismatch", "")
			return 0
		byte = _bytes[_position]
		_position += 1
		if index == maximum_bytes - 1 and byte >= 128:
			_fail("invalidContainer", _VAR_TOO_LONG)
			return 0
		var bits: int = byte & 127
		var shift: int = 7 * index
		if bits != 0:
			if shift >= 53:
				_fail("oversizedOutput", "")
				return 0
			var scale: int = 1 << shift
			var product: int = bits * scale
			if product > maximum or value > maximum - product:
				_fail("oversizedOutput", "")
				return 0
			value += product
		if byte < 128:
			if byte == 0:
				_fail("invalidContainer", _VAR_MINIMAL)
				return 0
			return value
	_fail("invalidContainer", _VAR_TOO_LONG)
	return 0

func _count(minimum: int) -> int:
	var value: int = _read_var(10)
	if _fault != null:
		return 0
	var remaining: int = _end - _position
	if value > Big.idiv(remaining, minimum):
		_fail("lengthMismatch", "")
		return 0
	return value

func _frame(limit: int) -> bool:
	var length: int = _read_var(10)
	if _fault != null:
		return false
	if length > _end - _position:
		_fail("lengthMismatch", "")
		return false
	if length > limit:
		_fail("oversizedRecord", "")
		return false
	_string_start = _position
	_string_length = length
	_position += length
	return true

func _read_scalar(limit: int) -> String:
	if not _frame(limit):
		return ""
	var text: Variant = decode_utf8(_bytes, _string_start, _position)
	if Errors.is_error(text):
		_fault = text
		return ""
	var value: String = text
	if value.find("\n") >= 0 or value.find("\r") >= 0:
		_fail("invalidDocument", _SCALAR_BREAK)
		return ""
	return value

func _read_segment(limit: int) -> String:
	if not _frame(limit):
		return ""
	if _string_length == 0:
		return ""
	var text: Variant = decode_utf8(_bytes, _string_start, _position)
	if Errors.is_error(text):
		_fault = text
		return ""
	return text

func _read_number(form: int) -> float:
	if form == 1:
		var zigzag: int = _read_var(4)
		if _fault != null:
			return 0.0
		var whole: int = _unzigzag(zigzag)
		var numeric: float = 0.0
		numeric = whole
		return numeric
	if form == 2:
		if _end - _position < 4:
			_fail("lengthMismatch", "")
			return 0.0
		var narrow: float = _bytes.decode_float(_position)
		_position += 4
		if not is_finite(narrow):
			_fail("invalidDocument", _FINITE)
			return 0.0
		if _integer_in_range(narrow):
			_fail("invalidContainer", _NUMBER_FORM)
			return 0.0
		return narrow
	if _end - _position < 8:
		_fail("lengthMismatch", "")
		return 0.0
	var wide: float = _bytes.decode_double(_position)
	_position += 8
	if not is_finite(wide):
		_fail("invalidDocument", _FINITE)
		return 0.0
	if _integer_in_range(wide) or _float32_exact(wide):
		_fail("invalidContainer", _NUMBER_FORM)
		return 0.0
	return wide

func _fail(code: String, detail: String) -> Variant:
	if _fault == null:
		_fault = _error(code, detail)
	return _fault

static func _error(code: String, detail: String) -> Variant:
	var message: String = code if detail.is_empty() else code + ": " + detail
	return Errors.make(code, message, -1, detail)

static func _unzigzag(zigzag: int) -> int:
	var half: int = zigzag >> 1
	if (zigzag & 1) == 0:
		return half
	return -half - 1

static func _integer_in_range(value: float) -> bool:
	if not is_finite(value):
		return false
	if value < -134217728.0 or value > 134217727.0:
		return false
	return value == floor(value)

static func _float32_exact(value: float) -> bool:
	if is_nan(value):
		return false
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(4)
	bytes.encode_float(0, value)
	var back: float = bytes.decode_float(0)
	return back == value

static func _number_form(value: float) -> int:
	if _integer_in_range(value):
		return 1
	if _float32_exact(value):
		return 2
	return 3

static func _whole(value: float) -> int:
	var negative: bool = value < 0.0
	var magnitude: float = -value if negative else value
	var digits: int = int(magnitude)
	return -digits if negative else digits

static func _zigzag(value: float) -> int:
	var whole: int = _whole(value)
	if whole >= 0:
		return whole << 1
	return ((-whole) << 1) - 1

static func _var_size(value: int) -> int:
	var count: int = 1
	var rest: int = value
	while rest >= 128:
		rest = rest >> 7
		count += 1
	return count

static func _number_size(value: float, form: int) -> int:
	if form == 1:
		return _var_size(_zigzag(value))
	if form == 2:
		return 4
	return 8

static func _write_var(output: PackedByteArray, position: int, value: int) -> int:
	var rest: int = value
	while rest >= 128:
		output[position] = (rest & 127) | 128
		position += 1
		rest = rest >> 7
	output[position] = rest
	return position + 1

static func _write_number(output: PackedByteArray, position: int, value: float, form: int) -> int:
	if form == 1:
		return _write_var(output, position, _zigzag(value))
	if form == 2:
		output.encode_float(position, value)
		return position + 4
	output.encode_double(position, value)
	return position + 8

static func _add_string(strings: Array, text: String) -> void:
	strings.append(text.to_utf8_buffer())

static func _string_size_at(strings: Array, index: int) -> int:
	var encoded: PackedByteArray = strings[index]
	return _var_size(encoded.size()) + encoded.size()

static func _queue_size(strings: Array) -> int:
	var total: int = 0
	for encoded in strings:
		var bytes: PackedByteArray = encoded
		total += _var_size(bytes.size()) + bytes.size()
	return total

static func _write_queued(output: PackedByteArray, position: int, strings: Array, index: int) -> int:
	var encoded: PackedByteArray = strings[index]
	position = _write_var(output, position, encoded.size())
	for byte in encoded:
		output[position] = byte
		position += 1
	return position

static func _nonnegative_zero(value: float) -> float:
	if value == 0.0:
		return 0.0
	return value

static func _entries(source: Dictionary) -> Array:
	var entries: Array = []
	for key in source:
		entries.append([str(key), str(source[key])])
	return entries

static func _has_equivalent(entries: Array) -> bool:
	var non_ascii: bool = false
	for entry in entries:
		var key: String = str(entry[0])
		for index in key.length():
			if key.unicode_at(index) >= 128:
				non_ascii = true
				break
		if non_ascii:
			break
	if not non_ascii:
		return false
	var seen: Dictionary = {}
	for entry in entries:
		var normal: String = Portable.nfc(str(entry[0]))
		if seen.has(normal):
			return true
		seen[normal] = true
	return false

static func _merge(entries: Array) -> Array:
	var values: Dictionary = {}
	var spellings: Dictionary = {}
	var order: Array = []
	for entry in entries:
		var key: String = str(entry[0])
		var normal: String = Portable.nfc(key)
		var spelling: String = key
		if spellings.has(normal):
			spelling = str(spellings[normal])
		else:
			spellings[normal] = key
			order.append(key)
		values[spelling] = str(entry[1])
	var merged: Array = []
	for spelling in order:
		merged.append([str(spelling), str(values[spelling])])
	return merged

static func _sort_entries(entries: Array) -> Array:
	var ordered: Array = []
	for entry in entries:
		ordered.append(entry)
	for index in range(1, ordered.size()):
		var item: Array = ordered[index]
		var cursor: int = index
		while cursor > 0:
			var previous: Array = ordered[cursor - 1]
			if Unicode.compare(str(previous[0]), str(item[0])) <= 0:
				break
			ordered[cursor] = previous
			cursor -= 1
		ordered[cursor] = item
	return ordered

static func _ordered(source: Dictionary) -> Array:
	var entries: Array = _entries(source)
	if _has_equivalent(entries):
		entries = _merge(entries)
	if entries.size() > 1:
		return _sort_entries(entries)
	return entries

static func _reject_scalars(document: Object) -> Variant:
	if _has_break(str(document.version)) or _has_break(str(document.axis)):
		return _error("invalidDocument", _SCALAR_BREAK)
	if document.title != null and _has_break(str(document.title)):
		return _error("invalidDocument", _SCALAR_BREAK)
	for key in document.metadata:
		if _has_break(str(key)) or _has_break(str(document.metadata[key])):
			return _error("invalidDocument", _SCALAR_BREAK)
	for item in document.planes:
		if item.label != null and _has_break(str(item.label)):
			return _error("invalidDocument", _SCALAR_BREAK)
		for key in item.attributes:
			if _has_break(str(key)) or _has_break(str(item.attributes[key])):
				return _error("invalidDocument", _SCALAR_BREAK)
	return null

static func _has_break(text: String) -> bool:
	return text.find("\n") >= 0 or text.find("\r") >= 0

static func _axis_normalized(axis: String) -> bool:
	var ascii: bool = true
	var upper: bool = false
	for index in axis.length():
		var unit: int = axis.unicode_at(index)
		if unit >= 128:
			ascii = false
		elif unit >= 65 and unit <= 90:
			upper = true
	if not ascii:
		return Portable.trim(axis).to_lower() == axis
	if axis.is_empty():
		return true
	var first: int = axis.unicode_at(0)
	var last: int = axis.unicode_at(axis.length() - 1)
	return first != 32 and first != 9 and last != 32 and last != 9 and not upper

static func _metadata_key_valid(key: String) -> bool:
	var length: int = key.length()
	if length == 0:
		return true
	if key.find(":") >= 0:
		return false
	var first: int = key.unicode_at(0)
	var last: int = key.unicode_at(length - 1)
	if first == 35 or Portable.is_whitespace(first) or Portable.is_whitespace(last):
		return false
	var ascii: bool = true
	for index in length:
		if key.unicode_at(index) >= 128:
			ascii = false
			break
	if not ascii:
		return true
	if length < 3 or length > 5:
		return true
	var lower: String = key.to_lower()
	return lower != "3md" and lower != "axis" and lower != "title"

static func _attribute_key_valid(key: String) -> bool:
	if key.is_empty():
		return false
	var ascii: bool = true
	for index in key.length():
		var unit: int = key.unicode_at(index)
		if unit == 32 or unit == 9 or unit == 61:
			return false
		if unit >= 65 and unit <= 90:
			return false
		if unit >= 128:
			ascii = false
	if not ascii:
		var first: int = key.unicode_at(0)
		var last: int = key.unicode_at(key.length() - 1)
		if Portable.is_whitespace(first) or Portable.is_whitespace(last):
			return false
		return key == key.to_lower()
	if key == "z" or key == "x" or key == "y" or key == "label":
		return false
	return true

static func _equivalent(keys: Array) -> Variant:
	var non_ascii: bool = false
	for key in keys:
		var text: String = str(key)
		for index in text.length():
			if text.unicode_at(index) >= 128:
				non_ascii = true
				break
		if non_ascii:
			break
	if not non_ascii:
		return null
	var seen: Dictionary = {}
	for key in keys:
		var normal: String = Portable.nfc(str(key))
		if seen.has(normal):
			return _error("invalidDocument", _EQUIVALENT)
		seen[normal] = true
	return null

static func _unique_positions(positions: Array) -> Variant:
	var increasing: bool = true
	for index in range(1, positions.size()):
		var left: float = positions[index - 1]
		var right: float = positions[index]
		if not (left < right):
			increasing = false
			break
	if increasing:
		return null
	var sorted: Array = []
	for item in positions:
		sorted.append(item)
	sorted.sort()
	for index in range(1, sorted.size()):
		var earlier: float = sorted[index - 1]
		var later: float = sorted[index]
		if earlier == later:
			return _error("invalidDocument", _UNIQUE)
	return null

static func _check_segment(text: String, preamble: bool, final: bool) -> Variant:
	var length: int = text.length()
	if length == 0:
		if preamble:
			return _error("invalidDocument", _EMPTY_PREAMBLE)
		return null
	if text.unicode_at(length - 1) == 13:
		return _error("invalidDocument", _TRAILING_CR)
	var fence: int = 0
	var start: int = 0
	while true:
		var newline: int = text.find("\n", start)
		var end_index: int = length if newline < 0 else newline
		if start == 0 and _skip_whitespace(text, 0, end_index) == end_index:
			return _error("invalidDocument", _BLANK_EDGE)
		if end_index < length and end_index > 0 and text.unicode_at(end_index - 1) == 13:
			return _error("invalidDocument", _CRLF)
		if start < end_index:
			var first: int = text.unicode_at(start)
			if first == 96 or first == 126 or first == 64 or first == 32 or first == 9 or (first >= 160 and Portable.is_whitespace(first)):
				var trimmed: int = start
				if first != 96 and first != 126 and first != 64:
					trimmed = _skip_whitespace(text, start, end_index)
				if fence != 0:
					if end_index - trimmed >= 3 and text.unicode_at(trimmed) == fence and text.unicode_at(trimmed + 1) == fence and text.unicode_at(trimmed + 2) == fence:
						fence = 0
				elif _starts(text, trimmed, "```"):
					fence = 96
				elif _starts(text, trimmed, "~~~"):
					fence = 126
				elif first == 64 and _starts(text, start, "@plane") and (end_index - start == 6 or text.unicode_at(start + 6) == 32 or text.unicode_at(start + 6) == 9):
					return _error("invalidDocument", _DIRECTIVE_LINE)
		if end_index == length:
			if _skip_whitespace(text, start, end_index) == end_index:
				return _error("invalidDocument", _BLANK_EDGE)
			break
		start = end_index + 1
	if not final and fence != 0:
		return _error("invalidDocument", _OPEN_FENCE)
	return null

static func _skip_whitespace(text: String, index: int, end_index: int) -> int:
	while index < end_index:
		var unit: int = text.unicode_at(index)
		if unit != 32 and unit != 9 and (unit < 160 or not Portable.is_whitespace(unit)):
			break
		index += 1
	return index

static func _starts(text: String, index: int, prefix: String) -> bool:
	if index + prefix.length() > text.length():
		return false
	return text.substr(index, prefix.length()) == prefix

static func _directive_round_trip(z: float, x: Variant, y: Variant, label: Variant, keys: Array, values: Array) -> Variant:
	var attributes: Dictionary = {}
	for index in keys.size():
		attributes[str(keys[index])] = str(values[index])
	var line: String = "@plane z=" + Numbers.canonical(z)
	if label != null:
		line += " label=" + _quote(str(label))
	if x != null:
		var x_value: float = x
		line += " x=" + Numbers.canonical(x_value)
	if y != null:
		var y_value: float = y
		line += " y=" + Numbers.canonical(y_value)
	for key in Portable.canonical_keys(attributes):
		line += " " + str(key) + "=" + _quote(str(attributes[key]))
	var source: String = "---\n3md: \"1\"\naxis: \"a\"\n---\n\n" + line + "\n"
	var parsed: Variant = Parser.parse(source)
	if Errors.is_error(parsed) or parsed == null or parsed.planes.size() != 1:
		return _error("invalidDocument", _DIRECTIVE)
	var plane: Object = parsed.planes[0]
	if plane.z != z or not _same_optional(plane.x, x) or not _same_optional(plane.y, y) or plane.label != label:
		return _error("invalidDocument", _DIRECTIVE)
	if plane.attributes.size() != keys.size():
		return _error("invalidDocument", _DIRECTIVE)
	for index in keys.size():
		var key: String = str(keys[index])
		if not plane.attributes.has(key) or str(plane.attributes[key]) != str(values[index]):
			return _error("invalidDocument", _DIRECTIVE)
	return null

static func _same_optional(left: Variant, right: Variant) -> bool:
	if left == null or right == null:
		return left == null and right == null
	var left_value: float = left
	var right_value: float = right
	return left_value == right_value

static func _quote(text: String) -> String:
	return "\"" + text.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
