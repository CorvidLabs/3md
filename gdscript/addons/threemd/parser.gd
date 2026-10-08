class_name ThreeMDParser
extends RefCounted

## Text grammar 1.0. This mirrors the Swift and TypeScript parser: frontmatter,
## optional preamble, and @plane directives. Callers get a ThreeMDDocument or a
## ThreeMDError. The addon does not raise.

const _Errors = preload("res://addons/threemd/error.gd")
const _Documents = preload("res://addons/threemd/document.gd")
const _Planes = preload("res://addons/threemd/plane.gd")
const _Links = preload("res://addons/threemd/link.gd")
const _Edges = preload("res://addons/threemd/link_edge.gd")
const _Numbers = preload("res://addons/threemd/number.gd")
const _Portable = preload("res://addons/threemd/portable.gd")

const _RESERVED: Array[String] = ["z", "x", "y", "label"]

static func parse(source: String) -> Variant:
	var normalized: String = source.replace("\r\n", "\n")
	if normalized.length() > 0 and normalized.unicode_at(0) == 0xFEFF:
		normalized = normalized.substr(1)
	var lines: PackedStringArray = normalized.split("\n", true)
	var frontmatter: Variant = _extract_frontmatter(lines)
	if _Errors.is_error(frontmatter):
		return frontmatter
	var interpreted: Variant = _interpret_frontmatter(frontmatter["fields"])
	if _Errors.is_error(interpreted):
		return interpreted
	var body: Variant = _parse_body(frontmatter["body"], int(frontmatter["body_start_line"]))
	if _Errors.is_error(body):
		return body
	var document = _Documents.new()
	document.version = interpreted["version"]
	document.axis = interpreted["axis"]
	document.title = interpreted["title"]
	document.metadata = interpreted["metadata"]
	document.preamble = body["preamble"]
	document.planes = body["planes"]
	return document

static func serialize(document: Object) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("---")
	lines.append("3md: " + _quote(document.version))
	lines.append("axis: " + _quote(document.axis))
	if document.title != null:
		lines.append("title: " + _quote(str(document.title)))
	var metadata: Dictionary = _Portable.canonical_strings(document.metadata)
	for key in _Portable.canonical_keys(metadata):
		lines.append(key + ": " + _quote(str(metadata[key])))
	lines.append("---")
	if document.preamble != null:
		lines.append("")
		lines.append(str(document.preamble))
	for item in document.planes:
		lines.append("")
		lines.append(_directive(item))
		if str(item.body).length() > 0:
			lines.append(str(item.body))
	return "\n".join(lines) + "\n"

static func links(document: Object) -> Array:
	var result: Array = []
	var targets: Array = []
	for plane in document.planes:
		targets.append(plane.z)
	for plane in document.planes:
		var body: String = str(plane.body)
		var cursor: int = 0
		while cursor < body.length():
			var opening: int = body.find("[[z=", cursor)
			if opening < 0:
				break
			var start: int = opening + 4
			var delimiter: int = start
			while delimiter < body.length():
				var unit: int = body.unicode_at(delimiter)
				if unit == 124 or unit == 93:
					break
				delimiter += 1
			if delimiter == body.length():
				break
			if delimiter == start:
				cursor = start
				continue
			var closing: int = delimiter
			if body.unicode_at(delimiter) == 124:
				closing = body.find("]", delimiter + 1)
			if closing < 0:
				break
			var double_close: bool = closing + 1 < body.length() and body.unicode_at(closing + 1) == 93
			cursor = closing + (2 if double_close else 1)
			if not double_close:
				continue
			var target: Variant = _Numbers.parse_finite(body.substr(start, delimiter - start))
			if target == null:
				continue
			var link = _Links.new()
			link.source_z = plane.z
			link.target_z = target
			if body.unicode_at(delimiter) == 124:
				link.text = body.substr(delimiter + 1, closing - delimiter - 1)
			else:
				link.text = null
			link.target_exists = _has_z(targets, float(target))
			result.append(link)
	return result

static func dangling_links(document: Object) -> Array:
	var result: Array = []
	for link in links(document):
		if not link.target_exists:
			result.append(link)
	return result

static func link_graph(document: Object) -> Array:
	var edges: Array = []
	var index_by_key: Dictionary = {}
	for link in links(document):
		var key: String = _float_key(link.source_z) + "/" + _float_key(link.target_z)
		if index_by_key.has(key):
			var index: int = int(index_by_key[key])
			edges[index].count += 1
		else:
			index_by_key[key] = edges.size()
			var edge = _Edges.new()
			edge.source_z = link.source_z
			edge.target_z = link.target_z
			edge.target_exists = link.target_exists
			edge.count = 1
			edges.append(edge)
	return edges

static func _extract_frontmatter(lines: PackedStringArray) -> Variant:
	var index: int = 0
	while index < lines.size() and _Portable.trim(lines[index]) == "":
		index += 1
	if index >= lines.size() or _Portable.trim(lines[index]) != "---":
		return _Errors.make("missingFrontmatter", "3md documents must begin with a '---' frontmatter block.")
	index += 1
	var fields: Array = []
	while index < lines.size():
		var trimmed: String = _Portable.trim(lines[index])
		if trimmed == "---":
			var body: PackedStringArray = PackedStringArray()
			for body_index in range(index + 1, lines.size()):
				body.append(lines[body_index])
			return {"fields": fields, "body_start_line": index + 2, "body": body}
		if trimmed != "" and not trimmed.begins_with("#"):
			var separator: int = trimmed.find(":")
			if separator < 0:
				var detail: String = "expected 'key: value', found '%s'" % trimmed
				return _Errors.make("invalidFrontmatter", "Invalid frontmatter: " + detail, -1, detail)
			var key: String = _Portable.trim(trimmed.substr(0, separator))
			var raw: String = _Portable.trim(trimmed.substr(separator + 1))
			fields.append({"key": key, "value": _unquote(raw)})
		index += 1
	var unclosed: String = "frontmatter block was not closed with '---'"
	return _Errors.make("invalidFrontmatter", "Invalid frontmatter: " + unclosed, -1, unclosed)

static func _interpret_frontmatter(fields: Array) -> Variant:
	var version: Variant = null
	var axis: String = "layer"
	var title: Variant = null
	var metadata: Dictionary = {}
	var spellings: Dictionary = {}
	for item in fields:
		var field: Dictionary = item
		var key: String = str(field["key"])
		var lowered: String = key.to_lower()
		if lowered == "3md":
			version = str(field["value"])
		elif lowered == "axis":
			axis = _Portable.trim(str(field["value"])).to_lower()
		elif lowered == "title":
			title = str(field["value"])
		else:
			_assign(metadata, spellings, key, str(field["value"]))
	if version == null or str(version).is_empty():
		return _Errors.make("missingVersion", "Frontmatter is missing the required '3md' version key.")
	return {"version": str(version), "axis": axis, "title": title, "metadata": metadata}

static func _parse_body(lines: PackedStringArray, body_start_line: int) -> Variant:
	var seen: Array = []
	var planes: Array = []
	var pending_line: int = -1
	var pending_attributes: Dictionary = {}
	var pending_body: Array = []
	var has_pending: bool = false
	var preamble_lines: Array = []
	var fence: String = ""
	for offset in lines.size():
		var raw: String = lines[offset]
		var line_number: int = body_start_line + offset
		var trimmed: String = _Portable.trim(raw)
		var is_directive: bool = false
		if fence != "":
			if trimmed.begins_with(fence.repeat(3)):
				fence = ""
		else:
			var opened: String = _fence_character(trimmed)
			if opened != "":
				fence = opened
			elif raw.length() > 0 and raw.unicode_at(0) != 32 and raw.unicode_at(0) != 9 and _first_token(raw) == "@plane":
				is_directive = true
		if not is_directive:
			if has_pending:
				pending_body.append(raw)
			else:
				preamble_lines.append(raw)
			continue
		if has_pending:
			var flushed: Variant = _make_plane(pending_line, pending_attributes, pending_body)
			if _Errors.is_error(flushed):
				return flushed
			if _has_z(seen, flushed.z):
				return _duplicate(flushed.z)
			seen.append(flushed.z)
			planes.append(flushed)
		var attributes: Variant = _parse_directive(trimmed, line_number)
		if _Errors.is_error(attributes):
			return attributes
		pending_line = line_number
		pending_attributes = attributes
		pending_body = []
		has_pending = true
	if has_pending:
		var last: Variant = _make_plane(pending_line, pending_attributes, pending_body)
		if _Errors.is_error(last):
			return last
		if _has_z(seen, last.z):
			return _duplicate(last.z)
		seen.append(last.z)
		planes.append(last)
	var preamble: Variant = _collapse(preamble_lines)
	if planes.is_empty():
		if preamble == null:
			return {"preamble": null, "planes": []}
		var shorthand = _Planes.new()
		shorthand.z = 0.0
		shorthand.label = null
		shorthand.x = null
		shorthand.y = null
		shorthand.attributes = {}
		shorthand.body = str(preamble)
		return {"preamble": null, "planes": [shorthand]}
	return {"preamble": preamble, "planes": planes}

static func _make_plane(line: int, attributes: Dictionary, body_lines: Array) -> Variant:
	if not attributes.has("z"):
		return _Errors.make(
			"missingPlanePosition",
			"The @plane directive on line %d is missing a 'z' position." % line,
			line
		)
	var z_raw: String = str(attributes["z"])
	var z: Variant = _Numbers.parse_finite(z_raw)
	if z == null:
		var z_detail: String = "z must be a finite decimal number, found '%s'" % z_raw
		return _Errors.make("invalidPlaneDirective", "Invalid @plane directive on line %d: %s" % [line, z_detail], line, z_detail)
	var x: Variant = _optional_number(attributes, "x", line)
	if _Errors.is_error(x):
		return x
	var y: Variant = _optional_number(attributes, "y", line)
	if _Errors.is_error(y):
		return y
	var plane = _Planes.new()
	plane.z = z
	plane.x = null if x == null else float(x)
	plane.y = null if y == null else float(y)
	plane.label = attributes["label"] if attributes.has("label") else null
	var extras: Dictionary = {}
	for key in attributes:
		var name: String = str(key)
		if not _RESERVED.has(name):
			extras[name] = attributes[key]
	plane.attributes = extras
	var body: Variant = _collapse(body_lines)
	plane.body = "" if body == null else str(body)
	return plane

static func _optional_number(attributes: Dictionary, key: String, line: int) -> Variant:
	if not attributes.has(key):
		return null
	var raw: String = str(attributes[key])
	var parsed: Variant = _Numbers.parse_finite(raw)
	if parsed == null:
		var detail: String = "%s must be a finite decimal number, found '%s'" % [key, raw]
		return _Errors.make("invalidPlaneDirective", "Invalid @plane directive on line %d: %s" % [line, detail], line, detail)
	return parsed

static func _parse_directive(trimmed: String, line: int) -> Variant:
	var remainder: String = _Portable.trim(trimmed.substr("@plane".length()))
	var result: Dictionary = {}
	var spellings: Dictionary = {}
	var tokens: Variant = _tokenize(remainder, line)
	if _Errors.is_error(tokens):
		return tokens
	for item in tokens:
		var token: String = str(item)
		var separator: int = token.find("=")
		if separator < 0:
			var detail: String = "expected key=value, found '%s'" % token
			return _Errors.make("invalidPlaneDirective", "Invalid @plane directive on line %d: %s" % [line, detail], line, detail)
		var key: String = _Portable.trim(token.substr(0, separator)).to_lower()
		var value: String = _unquote(_Portable.trim(token.substr(separator + 1)))
		if key.is_empty():
			var empty_detail: String = "empty attribute key in '%s'" % token
			return _Errors.make(
				"invalidPlaneDirective",
				"Invalid @plane directive on line %d: %s" % [line, empty_detail],
				line,
				empty_detail
			)
		_assign(result, spellings, key, value)
	return result

static func _tokenize(input: String, line: int) -> Variant:
	var tokens: Array = []
	var current := ""
	var active_quote := ""
	var escaped: bool = false
	for index in input.length():
		var character: String = input.substr(index, 1)
		if active_quote != "":
			current += character
			if escaped:
				escaped = false
			elif character == "\\":
				escaped = true
			elif character == active_quote:
				active_quote = ""
		elif character == "\"" or character == "'":
			active_quote = character
			current += character
		elif character == " " or character == "\t":
			if current.length() > 0:
				tokens.append(current)
				current = ""
		else:
			current += character
	if active_quote != "":
		var detail: String = "unterminated quote in '%s'" % input
		return _Errors.make("invalidPlaneDirective", "Invalid @plane directive on line %d: %s" % [line, detail], line, detail)
	if current.length() > 0:
		tokens.append(current)
	return tokens

static func _unquote(value: String) -> String:
	if value.length() < 2:
		return value
	var first: String = value.substr(0, 1)
	var last: String = value.substr(value.length() - 1, 1)
	if (first == "\"" and last == "\"") or (first == "'" and last == "'"):
		return _unescape(value.substr(1, value.length() - 2))
	return value

static func _unescape(value: String) -> String:
	var result := ""
	var escaping: bool = false
	for index in value.length():
		var character: String = value.substr(index, 1)
		if escaping:
			result += character
			escaping = false
		elif character == "\\":
			escaping = true
		else:
			result += character
	if escaping:
		result += "\\"
	return result

static func _fence_character(trimmed: String) -> String:
	if trimmed.begins_with("```"):
		return "`"
	if trimmed.begins_with("~~~"):
		return "~"
	return ""

static func _first_token(line: String) -> String:
	var current := ""
	for index in line.length():
		var unit: int = line.unicode_at(index)
		if unit == 32 or unit == 9:
			if current.length() > 0:
				return current
		else:
			current += line.substr(index, 1)
	return current

static func _collapse(lines: Array) -> Variant:
	var start: int = 0
	var end: int = lines.size()
	while start < end and _Portable.trim(str(lines[start])) == "":
		start += 1
	while end > start and _Portable.trim(str(lines[end - 1])) == "":
		end -= 1
	if start >= end:
		return null
	var parts := PackedStringArray()
	for index in range(start, end):
		parts.append(str(lines[index]))
	return "\n".join(parts)

static func _assign(values: Dictionary, spellings: Dictionary, key: String, value: String) -> void:
	var normalized: String = _Portable.nfc(key)
	var spelling: String = key
	if spellings.has(normalized):
		spelling = str(spellings[normalized])
	else:
		spellings[normalized] = key
	values[spelling] = value

static func _has_z(seen: Array, z: float) -> bool:
	for item in seen:
		if float(item) == z:
			return true
	return false

static func _duplicate(z: float) -> Variant:
	var rendered: String = _Numbers.canonical(z)
	return _Errors.make("duplicatePlane", "Two planes share the same z position: " + rendered, -1, rendered)

static func _float_key(value: float) -> String:
	if value == 0.0:
		return "0"
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return bytes.hex_encode()

static func _directive(plane: Object) -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append("@plane")
	parts.append("z=" + _Numbers.canonical(float(plane.z)))
	if plane.label != null:
		parts.append("label=" + _quote(str(plane.label), true))
	if plane.x != null:
		parts.append("x=" + _Numbers.canonical(float(plane.x)))
	if plane.y != null:
		parts.append("y=" + _Numbers.canonical(float(plane.y)))
	var attributes: Dictionary = _Portable.canonical_strings(plane.attributes)
	for key in _Portable.canonical_keys(attributes):
		parts.append(key + "=" + _quote(str(attributes[key]), true))
	return " ".join(parts)

static func _quote(value: String, force: bool = false) -> String:
	var needs: bool = force or value.is_empty()
	if value.find(" ") >= 0 or value.find("\t") >= 0 or value.find("\"") >= 0 or value.find("\\") >= 0:
		needs = true
	if value.length() >= 2 and value.begins_with("'") and value.ends_with("'"):
		needs = true
	if value.length() > 0:
		var first: int = value.unicode_at(0)
		var last: int = value.unicode_at(value.length() - 1)
		if _Portable.is_whitespace(first) or _Portable.is_whitespace(last):
			needs = true
	if not needs:
		return value
	return "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
