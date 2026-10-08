class_name ThreeMDComposition
extends RefCounted

## Self-contained composition profile `3md-composition-1`.
## IDs are graph names, never filesystem paths. This script does not read files.
## A caller passes documents and reference dictionaries (`id`, `document`,
## `references` of `target_id` and `attributes`). Failures are ThreeMDError.

const _Errors = preload("res://addons/threemd/error.gd")
const _Documents = preload("res://addons/threemd/document.gd")
const _Planes = preload("res://addons/threemd/plane.gd")
const _Portable = preload("res://addons/threemd/portable.gd")
const _Storage = preload("res://addons/threemd/storage.gd")

const _DEFAULTS: Dictionary = {
	"maximumDefinitions": 1024,
	"maximumReferences": 16384,
	"maximumDepth": 64,
	"maximumDefinitionBytes": 16777216,
	"maximumTraversalOccurrences": 1000000,
	"maximumProfileBytes": 20971520,
	"maximumReferenceAttributes": 64,
	"maximumReferenceAttributeBytes": 16384,
}

var root_id: String = ""
var entries: Array = []

static func _fail(code: String, detail: Variant = null, target: Variant = null) -> ThreeMDError:
	var message: String = code
	var detail_text: String = ""
	if detail != null:
		detail_text = str(detail)
		message += ": " + detail_text
	if target != null:
		message += " -> " + str(target)
	return _Errors.make(code, message, -1, detail_text)

static func _cancel() -> ThreeMDError:
	return _Errors.make("canceled", "The operation was canceled.", -1, "")

static func _canceled(token: Variant) -> bool:
	if token == null:
		return false
	if typeof(token) == TYPE_BOOL:
		return token
	if typeof(token) == TYPE_OBJECT and token.has_method("is_canceled"):
		return token.is_canceled() == true
	return false

static func standard_limits() -> Dictionary:
	return _DEFAULTS.duplicate()

static func resolve_limits(options: Variant) -> Variant:
	var limits: Dictionary = _DEFAULTS.duplicate()
	if options == null:
		return limits
	if typeof(options) != TYPE_DICTIONARY:
		return _fail("invalidLimits", "limits")
	var provided: Dictionary = options
	for key in _DEFAULTS:
		if not provided.has(key):
			continue
		var value: Variant = provided[key]
		var number: int = 0
		if typeof(value) == TYPE_INT:
			number = value
		else:
			return _fail("invalidLimits", str(key))
		var minimum: int = 1
		if key == "maximumReferences" or key == "maximumReferenceAttributes" or key == "maximumReferenceAttributeBytes":
			minimum = 0
		if not _Portable.bounded_integer(number, minimum, int(_DEFAULTS[key])):
			return _fail("invalidLimits", str(key))
		limits[key] = number
	return limits

static func make(root_id: String, raw_entries: Array, limits: Variant = null, token: Variant = null) -> Variant:
	if _canceled(token):
		return _cancel()
	var resolved: Variant = resolve_limits(limits)
	if _Errors.is_error(resolved):
		return resolved
	var sources: Variant = _validate(root_id, raw_entries, resolved, token)
	if _Errors.is_error(sources):
		return sources
	var copies: Array = []
	for item in raw_entries:
		var entry: Dictionary = item
		copies.append(_copy_entry(entry))
	var created: Object = load("res://addons/threemd/composition.gd").new()
	created.root_id = root_id
	created.entries = _sort_entries(copies)
	return created

func find_entry(id: String) -> Variant:
	for item in entries:
		var entry: Dictionary = item
		if str(entry["id"]) == id:
			return entry
	return null

func root_entry() -> Variant:
	var found: Variant = find_entry(root_id)
	if found == null:
		return _fail("missingRoot", root_id)
	return found

static func is_composition(document: Object) -> bool:
	var metadata: Dictionary = document.metadata
	return str(metadata.get("profile", "")) == "3md-composition-1"

static func to_document(composition: Object, limits: Variant = null, token: Variant = null) -> Variant:
	if _canceled(token):
		return _cancel()
	var resolved: Variant = resolve_limits(limits)
	if _Errors.is_error(resolved):
		return resolved
	var limit_values: Dictionary = resolved
	var sources: Variant = _validate(str(composition.root_id), composition.entries, limit_values, token)
	if _Errors.is_error(sources):
		return sources
	var encoded_sources: Dictionary = sources
	var writer := _Writer.new()
	writer.maximum = int(limit_values["maximumProfileBytes"])
	writer.append("{\n  \"entries\": [")
	var ordered: Array = _sort_entries(composition.entries)
	for index in ordered.size():
		if _canceled(token):
			return _cancel()
		var entry: Dictionary = ordered[index]
		writer.append("\n" if index == 0 else ",\n")
		writer.append("    {\n      \"id\": ")
		writer.quoted(str(entry["id"]))
		writer.append(",\n      \"references\": [")
		var references: Array = entry["references"]
		for reference_index in references.size():
			var reference: Dictionary = references[reference_index]
			writer.append("\n" if reference_index == 0 else ",\n")
			writer.append("        {\"attributes\": {")
			var attributes: Dictionary = _Portable.canonical_strings(reference["attributes"])
			var keys: PackedStringArray = _Portable.canonical_keys(attributes)
			for attribute_index in keys.size():
				var key: String = keys[attribute_index]
				writer.append("" if attribute_index == 0 else ", ")
				writer.quoted(key)
				writer.append(": ")
				writer.quoted(str(attributes[key]))
			writer.append("}, \"targetID\": ")
			writer.quoted(str(reference["target_id"]))
			writer.append("}")
		if references.is_empty():
			writer.append("],\n      \"source\": ")
		else:
			writer.append("\n      ],\n      \"source\": ")
		var source: Variant = encoded_sources.get(str(entry["id"]), null)
		if not (source is PackedByteArray):
			return _fail("invalidProfile", "definition source missing")
		var source_bytes: PackedByteArray = source
		writer.quoted(source_bytes.get_string_from_utf8())
		writer.append("\n    }")
	writer.append("\n  ],\n  \"rootID\": ")
	writer.quoted(str(composition.root_id))
	writer.append(",\n  \"schema\": \"3md-composition-1\"\n}")
	if writer.problem != null:
		return writer.problem
	var document = _Documents.new()
	document.version = "0.1"
	document.axis = "layer"
	document.title = null
	document.preamble = null
	document.metadata = {"profile": "3md-composition-1"}
	var plane = _Planes.new()
	plane.z = 0.0
	plane.label = "Composition"
	plane.x = null
	plane.y = null
	plane.attributes = {}
	plane.body = "```json\n" + writer.finish() + "\n```"
	document.planes = [plane]
	var checked: Variant = _bounded_text(document, limit_values)
	if _Errors.is_error(checked):
		return checked
	return document

static func encode(composition: Object, limits: Variant = null, token: Variant = null) -> Variant:
	var document: Variant = to_document(composition, limits, token)
	if _Errors.is_error(document):
		return document
	var resolved: Variant = resolve_limits(limits)
	if _Errors.is_error(resolved):
		return resolved
	return _bounded_text(document, resolved)

static func decode(input: Variant, limits: Variant = null, token: Variant = null) -> Variant:
	if _canceled(token):
		return _cancel()
	var resolved: Variant = resolve_limits(limits)
	if _Errors.is_error(resolved):
		return resolved
	var limit_values: Dictionary = resolved
	var document: Object
	if input is PackedByteArray:
		var data: PackedByteArray = input
		if data.size() > int(limit_values["maximumProfileBytes"]):
			return _fail("profileBytesExceeded")
		var decoded: Variant = _Storage.decode(data)
		if _Errors.is_error(decoded) or decoded == null or not (decoded is Object):
			if _Errors.is_error(decoded):
				var storage_code: String = str(decoded.code)
				if storage_code == "oversizedInput" or storage_code == "oversizedOutput" or storage_code == "oversizedRecord":
					return _fail("profileBytesExceeded")
				return decoded
			return _fail("invalidProfile", "JSON fields have invalid types or values")
		document = decoded
	elif typeof(input) == TYPE_OBJECT and input != null and not _Errors.is_error(input):
		document = input
	else:
		return _fail("invalidProfile", "JSON fields have invalid types or values")
	var checked: Variant = _bounded_text(document, limit_values)
	if _Errors.is_error(checked):
		return checked
	if not is_composition(document):
		var metadata: Dictionary = document.metadata
		var profile: String = "missing"
		if metadata.has("profile"):
			profile = str(metadata["profile"])
		return _fail("unsupportedProfile", profile)
	var planes: Array = document.planes
	if planes.is_empty():
		return _fail("invalidProfile", "unexpected composition envelope")
	var plane: Object = planes[0]
	var metadata_size: int = document.metadata.size()
	var attributes: Dictionary = plane.attributes
	var body: String = str(plane.body)
	if str(document.version) != "0.1" or str(document.axis) != "layer" or document.title != null or document.preamble != null:
		return _fail("invalidProfile", "unexpected composition envelope")
	if metadata_size != 1 or planes.size() != 1 or not _is_positive_zero(float(plane.z)):
		return _fail("invalidProfile", "unexpected composition envelope")
	if plane.label != "Composition" or plane.x != null or plane.y != null or attributes.size() != 0:
		return _fail("invalidProfile", "unexpected composition envelope")
	if not body.begins_with("```json\n") or not body.ends_with("\n```"):
		return _fail("invalidProfile", "unexpected composition envelope")
	var json: String = body.substr(8, body.length() - 12)
	var scanner := _Scanner.new()
	scanner.source = json
	scanner.limits = limit_values
	scanner.token = token
	var scanned: Variant = scanner.scan()
	if _Errors.is_error(scanned):
		return scanned
	var parsed: Variant = JSON.parse_string(json)
	if typeof(parsed) != TYPE_DICTIONARY:
		return _fail("invalidProfile", "JSON fields have invalid types or values")
	var manifest: Variant = _object(parsed, ["schema", "rootID", "entries"])
	if _Errors.is_error(manifest):
		return manifest
	var record: Dictionary = manifest
	var schema: Variant = _string_field(record["schema"])
	if _Errors.is_error(schema):
		return schema
	if str(schema) != "3md-composition-1":
		return _fail("unsupportedProfile", str(schema))
	var root_field: Variant = _string_field(record["rootID"])
	if _Errors.is_error(root_field):
		return root_field
	var raw_entries: Variant = _array_field(record["entries"])
	if _Errors.is_error(raw_entries):
		return raw_entries
	var entry_values: Array = raw_entries
	if entry_values.size() > int(limit_values["maximumDefinitions"]):
		return _fail("tooManyDefinitions")
	var total: int = 0
	var built: Array = []
	for raw_entry in entry_values:
		if _canceled(token):
			return _cancel()
		var entry_object: Variant = _object(raw_entry, ["id", "source", "references"])
		if _Errors.is_error(entry_object):
			return entry_object
		var entry_record: Dictionary = entry_object
		var source_field: Variant = _string_field(entry_record["source"])
		if _Errors.is_error(source_field):
			return source_field
		var source_text: String = str(source_field)
		var source_size: int = _Portable.utf8_length(source_text)
		if source_size > int(limit_values["maximumDefinitionBytes"]) - total:
			return _fail("definitionBytesExceeded")
		total += source_size
		var source_bytes: PackedByteArray = source_text.to_utf8_buffer()
		if _is_binary(source_bytes):
			return _fail("invalidProfile", "embedded definitions must be text 3md")
		var embedded: Variant = _Storage.decode(source_bytes)
		if _Errors.is_error(embedded) or embedded == null:
			return embedded if _Errors.is_error(embedded) else _fail("invalidProfile", "JSON fields have invalid types or values")
		var raw_references: Variant = _array_field(entry_record["references"])
		if _Errors.is_error(raw_references):
			return raw_references
		var reference_values: Array = raw_references
		var references: Array = []
		for raw_reference in reference_values:
			var reference_object: Variant = _object(raw_reference, ["targetID", "attributes"])
			if _Errors.is_error(reference_object):
				return reference_object
			var reference_record: Dictionary = reference_object
			var target_field: Variant = _string_field(reference_record["targetID"])
			if _Errors.is_error(target_field):
				return target_field
			var attribute_object: Variant = _object(reference_record["attributes"], [])
			if _Errors.is_error(attribute_object):
				return attribute_object
			var attribute_record: Dictionary = attribute_object
			var copied_attributes: Dictionary = {}
			for key in attribute_record:
				var attribute_value: Variant = _string_field(attribute_record[key])
				if _Errors.is_error(attribute_value):
					return attribute_value
				copied_attributes[str(key)] = str(attribute_value)
			references.append({"target_id": str(target_field), "attributes": copied_attributes})
		var id_field: Variant = _string_field(entry_record["id"])
		if _Errors.is_error(id_field):
			return id_field
		built.append({"id": str(id_field), "document": embedded, "references": references})
	return make(str(root_field), built, limit_values, token)

static func _bounded_text(document: Object, limits: Dictionary) -> Variant:
	var encoded: Variant = _Storage.encode_text(document)
	if _Errors.is_error(encoded):
		var code: String = str(encoded.code)
		if code == "oversizedInput" or code == "oversizedOutput" or code == "oversizedRecord":
			return _fail("profileBytesExceeded")
		return encoded
	if not (encoded is PackedByteArray):
		return _fail("invalidProfile", "definition source missing")
	var bytes: PackedByteArray = encoded
	if bytes.size() > int(limits["maximumProfileBytes"]):
		return _fail("profileBytesExceeded")
	return bytes

static func _validate(root_id: String, raw_entries: Array, limits: Dictionary, token: Variant) -> Variant:
	if _canceled(token):
		return _cancel()
	if not _Portable.valid_id(root_id):
		return _fail("invalidID", root_id)
	if raw_entries.size() > int(limits["maximumDefinitions"]):
		return _fail("tooManyDefinitions")
	var indices: Dictionary = {}
	var sources: Dictionary = {}
	var references: int = 0
	var source_bytes: int = 0
	for index in raw_entries.size():
		if _canceled(token):
			return _cancel()
		if typeof(raw_entries[index]) != TYPE_DICTIONARY:
			return _fail("invalidProfile", "JSON fields have invalid types or values")
		var entry: Dictionary = raw_entries[index]
		if not entry.has("id") or not entry.has("document") or not entry.has("references"):
			return _fail("invalidProfile", "JSON fields have invalid types or values")
		var entry_id: String = str(entry["id"])
		if not _Portable.valid_id(entry_id):
			return _fail("invalidID", entry_id)
		if indices.has(entry_id):
			return _fail("duplicateID", entry_id)
		indices[entry_id] = index
		if typeof(entry["references"]) != TYPE_ARRAY:
			return _fail("invalidProfile", "JSON fields have invalid types or values")
		var entry_references: Array = entry["references"]
		if entry_references.size() > int(limits["maximumReferences"]) - references:
			return _fail("tooManyReferences")
		references += entry_references.size()
		for raw_reference in entry_references:
			if _canceled(token):
				return _cancel()
			if typeof(raw_reference) != TYPE_DICTIONARY:
				return _fail("invalidProfile", "JSON fields have invalid types or values")
			var reference: Dictionary = raw_reference
			var target_id: String = str(reference["target_id"]) if reference.has("target_id") else str(reference.get("targetID", ""))
			if not _Portable.valid_id(target_id):
				return _fail("invalidID", target_id)
			if typeof(reference["attributes"]) != TYPE_DICTIONARY:
				return _fail("invalidProfile", "JSON fields have invalid types or values")
			var attributes: Dictionary = reference["attributes"]
			if attributes.size() > int(limits["maximumReferenceAttributes"]):
				return _fail("referenceAttributesExceeded")
			var attribute_bytes: int = 0
			var budget: int = int(limits["maximumReferenceAttributeBytes"])
			for key in attributes:
				var attribute_key: String = str(key)
				var attribute_value: Variant = attributes[key]
				if typeof(attribute_value) != TYPE_STRING:
					return _fail("invalidProfile", "JSON fields have invalid types or values")
				for text in [attribute_key, str(attribute_value)]:
					var count: int = _Portable.utf8_length(text)
					if count > budget - attribute_bytes:
						return _fail("referenceAttributesExceeded")
					attribute_bytes += count
		var remaining: int = int(limits["maximumDefinitionBytes"]) - source_bytes
		if remaining <= 0:
			return _fail("definitionBytesExceeded")
		if typeof(entry["document"]) != TYPE_OBJECT or entry["document"] == null:
			return _fail("invalidProfile", "JSON fields have invalid types or values")
		var encoded: Variant = _Storage.encode_text(entry["document"])
		if _Errors.is_error(encoded):
			var code: String = str(encoded.code)
			if code == "oversizedInput" or code == "oversizedOutput" or code == "oversizedRecord":
				if remaining <= _Portable.MAXIMUM_INTEGER:
					return _fail("definitionBytesExceeded")
			return encoded
		if not (encoded is PackedByteArray):
			return _fail("invalidProfile", "definition source missing")
		var packed: PackedByteArray = encoded
		if packed.size() > remaining:
			return _fail("definitionBytesExceeded")
		source_bytes += packed.size()
		sources[entry_id] = packed
	if not indices.has(root_id):
		return _fail("missingRoot", root_id)
	for item in raw_entries:
		var linked_entry: Dictionary = item
		var linked_id: String = str(linked_entry["id"])
		var linked_references: Array = linked_entry["references"]
		for linked_raw in linked_references:
			if _canceled(token):
				return _cancel()
			var linked_reference: Dictionary = linked_raw
			var linked_target: String = str(linked_reference["target_id"]) if linked_reference.has("target_id") else str(linked_reference.get("targetID", ""))
			if not indices.has(linked_target):
				return _fail("missingTarget", linked_id, linked_target)
	var walk: Dictionary = {
		"entries": raw_entries,
		"indices": indices,
		"limits": limits,
		"states": [],
		"depths": [],
		"occurrences": [],
		"token": token,
	}
	var states: Array[int] = []
	var depths: Array[int] = []
	var occurrences: Array[int] = []
	states.resize(raw_entries.size())
	depths.resize(raw_entries.size())
	occurrences.resize(raw_entries.size())
	walk["states"] = states
	walk["depths"] = depths
	walk["occurrences"] = occurrences
	for walk_index in raw_entries.size():
		var visited: Variant = _visit(walk_index, 0, walk)
		if _Errors.is_error(visited):
			return visited
	return sources

static func _visit(index: int, active_depth: int, walk: Dictionary) -> Variant:
	if _canceled(walk["token"]):
		return _cancel()
	var entries: Array = walk["entries"]
	var states: Array = walk["states"]
	var depths: Array = walk["depths"]
	var occurrences: Array = walk["occurrences"]
	var indices: Dictionary = walk["indices"]
	var limits: Dictionary = walk["limits"]
	if index < 0 or index >= entries.size():
		return _fail("invalidProfile", "missing graph entry")
	if int(states[index]) == 1:
		var active: Dictionary = entries[index]
		return _fail("cycle", str(active["id"]))
	if int(states[index]) == 2:
		return null
	if active_depth >= int(limits["maximumDepth"]):
		return _fail("depthExceeded")
	states[index] = 1
	var entry: Dictionary = entries[index]
	var depth: int = 1
	var count: int = 1
	var entry_references: Array = entry["references"]
	for raw_reference in entry_references:
		var reference: Dictionary = raw_reference
		var target_id: String = str(reference["target_id"]) if reference.has("target_id") else str(reference.get("targetID", ""))
		if not indices.has(target_id):
			return _fail("missingTarget", str(entry["id"]), target_id)
		var target: int = int(indices[target_id])
		var child: Variant = _visit(target, active_depth + 1, walk)
		if _Errors.is_error(child):
			return child
		var child_depth: int = int(depths[target]) + 1
		if child_depth > depth:
			depth = child_depth
		if depth > int(limits["maximumDepth"]):
			return _fail("depthExceeded")
		var added: int = int(occurrences[target])
		if added > int(limits["maximumTraversalOccurrences"]) - count:
			return _fail("traversalOccurrencesExceeded")
		count += added
	states[index] = 2
	depths[index] = depth
	occurrences[index] = count
	return null

static func _copy_entry(source: Dictionary) -> Dictionary:
	var references: Array = []
	var raw_references: Array = source["references"]
	for item in raw_references:
		references.append(_copy_reference(item))
	return {
		"id": str(source["id"]),
		"document": _Portable.canonical_document(source["document"]),
		"references": references,
	}

static func _copy_reference(source: Dictionary) -> Dictionary:
	var attributes: Dictionary = {}
	var raw_attributes: Dictionary = source["attributes"]
	for key in raw_attributes:
		attributes[str(key)] = str(raw_attributes[key])
	var target_id: String = str(source["target_id"]) if source.has("target_id") else str(source.get("targetID", ""))
	return {"target_id": target_id, "attributes": _Portable.canonical_strings(attributes)}

static func _sort_entries(raw_entries: Array) -> Array:
	var sorted: Array = []
	for item in raw_entries:
		var entry: Dictionary = item
		var placed: bool = false
		for index in sorted.size():
			var existing: Dictionary = sorted[index]
			if str(entry["id"]) < str(existing["id"]):
				sorted.insert(index, entry)
				placed = true
				break
		if not placed:
			sorted.append(entry)
	return sorted

static func _object(value: Variant, keys: Array) -> Variant:
	if typeof(value) != TYPE_DICTIONARY:
		return _fail("invalidProfile", "JSON fields have invalid types or values")
	var record: Dictionary = value
	if keys.is_empty():
		return record
	if record.size() != keys.size():
		return _fail("invalidProfile", "missing or unknown JSON record keys")
	for key in keys:
		if not record.has(str(key)):
			return _fail("invalidProfile", "missing or unknown JSON record keys")
	return record

static func _string_field(value: Variant) -> Variant:
	if typeof(value) != TYPE_STRING:
		return _fail("invalidProfile", "JSON fields have invalid types or values")
	return value

static func _array_field(value: Variant) -> Variant:
	if typeof(value) != TYPE_ARRAY:
		return _fail("invalidProfile", "JSON fields have invalid types or values")
	return value

static func _is_binary(data: PackedByteArray) -> bool:
	if data.size() < 8:
		return false
	var magic: PackedByteArray = PackedByteArray([0x33, 0x6d, 0x64, 0x62, 0x69, 0x6e, 0x0d, 0x0a])
	for index in 8:
		if data[index] != magic[index]:
			return false
	return true

static func _is_positive_zero(value: float) -> bool:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	for index in 8:
		if bytes[index] != 0:
			return false
	return true


class _Writer:
	const _Errors = preload("res://addons/threemd/error.gd")

	var maximum: int = 0
	var used: int = 0
	var chunks: PackedStringArray = PackedStringArray()
	var problem: Variant = null

	func append(text: String) -> void:
		if problem != null:
			return
		var count: int = text.to_utf8_buffer().size()
		if count > maximum - used:
			problem = _Errors.make("profileBytesExceeded", "profileBytesExceeded", -1, "")
			return
		used += count
		chunks.append(text)

	func quoted(text: String) -> void:
		append("\"")
		var start: int = 0
		for index in text.length():
			var unit: int = text.unicode_at(index)
			var escape: String = ""
			if unit == 34:
				escape = "\\\""
			elif unit == 92:
				escape = "\\\\"
			elif unit < 32:
				if unit == 8:
					escape = "\\b"
				elif unit == 9:
					escape = "\\t"
				elif unit == 10:
					escape = "\\n"
				elif unit == 12:
					escape = "\\f"
				elif unit == 13:
					escape = "\\r"
				else:
					escape = "\\u%04x" % unit
			if escape != "":
				append(text.substr(start, index - start))
				append(escape)
				start = index + 1
		append(text.substr(start, text.length() - start))
		append("\"")

	func finish() -> String:
		return "".join(chunks)


class _Scanner:
	const _Errors = preload("res://addons/threemd/error.gd")
	const _Portable = preload("res://addons/threemd/portable.gd")

	var index: int = 0
	var array_elements: int = 0
	var objects: int = 0
	var source: String = ""
	var limits: Dictionary = {}
	var token: Variant = null
	var problem: Variant = null

	func scan() -> Variant:
		_value(0)
		if problem != null:
			return problem
		_whitespace()
		if problem != null:
			return problem
		if index != source.length():
			return _invalid("trailing JSON input")
		return null

	func _invalid(message: String) -> Variant:
		if problem == null:
			problem = _Errors.make("invalidProfile", "invalidProfile: " + message, -1, message)
		return problem

	func _stop() -> bool:
		if token == null:
			return false
		var stop: bool = false
		if typeof(token) == TYPE_BOOL:
			stop = token
		elif typeof(token) == TYPE_OBJECT and token.has_method("is_canceled"):
			stop = token.is_canceled() == true
		if stop and problem == null:
			problem = _Errors.make("canceled", "The operation was canceled.", -1, "")
		return stop

	func _whitespace() -> void:
		while index < source.length() and " \t\r\n".find(source.substr(index, 1)) >= 0:
			if index % 4096 == 0 and _stop():
				return
			index += 1

	func _consume(character: String) -> bool:
		if index >= source.length() or source.substr(index, 1) != character:
			return false
		index += 1
		return true

	func _value(depth: int) -> void:
		if problem != null or _stop():
			return
		if depth > 12:
			_invalid("excessive JSON nesting")
			return
		_whitespace()
		if problem != null:
			return
		var character: String = source.substr(index, 1)
		if character == "{":
			_object(depth + 1)
		elif character == "[":
			_array(depth + 1)
		elif character == "\"":
			_string(false)
		elif character == "t":
			_literal("true")
		elif character == "f":
			_literal("false")
		elif character == "n":
			_literal("null")
		elif character != "" and "-0123456789".find(character) >= 0:
			_invalid("numeric JSON fields are not part of this profile")
		else:
			_invalid("invalid or truncated JSON value")

	func _object(depth: int) -> void:
		objects += 1
		var cap: int = 1 + int(limits["maximumDefinitions"]) + 2 * int(limits["maximumReferences"])
		if objects > cap:
			_invalid("too many JSON records")
			return
		index += 1
		_whitespace()
		if problem != null:
			return
		if _consume("}"):
			return
		var keys: Dictionary = {}
		while true:
			if problem != null:
				return
			var key: Variant = _string(true)
			if problem != null:
				return
			var text: String = str(key)
			var norm: String = _Portable.nfc(text)
			if keys.has(norm):
				_invalid("duplicate JSON object key")
				return
			keys[norm] = true
			var attr_cap: int = int(limits["maximumReferenceAttributes"])
			if attr_cap < 3:
				attr_cap = 3
			if keys.size() > attr_cap:
				problem = _Errors.make("referenceAttributesExceeded", "referenceAttributesExceeded", -1, "")
				return
			_whitespace()
			if not _consume(":"):
				_invalid("missing JSON colon")
				return
			_value(depth)
			if problem != null:
				return
			_whitespace()
			if _consume("}"):
				return
			if not _consume(","):
				_invalid("missing JSON comma")
				return
			_whitespace()

	func _array(depth: int) -> void:
		index += 1
		_whitespace()
		if problem != null:
			return
		if _consume("]"):
			return
		while true:
			if problem != null:
				return
			array_elements += 1
			var element_cap: int = int(limits["maximumDefinitions"]) + int(limits["maximumReferences"])
			if array_elements > element_cap:
				_invalid("too many JSON array elements")
				return
			_value(depth)
			if problem != null:
				return
			_whitespace()
			if _consume("]"):
				return
			if not _consume(","):
				_invalid("missing JSON comma")
				return
			_whitespace()

	func _string(is_key: bool) -> Variant:
		if not _consume("\""):
			_invalid("JSON key must be a string")
			return null
		var start: int = index - 1
		while index < source.length():
			if index % 4096 == 0 and _stop():
				return null
			var unit: int = source.unicode_at(index)
			index += 1
			if unit == 34:
				if not is_key:
					return null
				var raw: String = source.substr(start, index - start)
				var budget: int = 6 * int(limits["maximumReferenceAttributeBytes"]) + 256
				if raw.to_utf8_buffer().size() > budget:
					problem = _Errors.make("referenceAttributesExceeded", "referenceAttributesExceeded", -1, "")
					return null
				var parsed: Variant = JSON.parse_string(raw)
				if typeof(parsed) != TYPE_STRING:
					if _stop():
						return null
					_invalid("invalid JSON key escape")
					return null
				return str(parsed)
			if unit < 32:
				_invalid("unescaped JSON control character")
				return null
			if unit == 92:
				if index >= source.length():
					_invalid("invalid JSON escape")
					return null
				var escaped: String = source.substr(index, 1)
				index += 1
				if escaped == "u":
					if index + 4 > source.length() or not _hex4(source.substr(index, 4)):
						_invalid("invalid Unicode escape")
						return null
					index += 4
				elif "\"\\/bfnrt".find(escaped) < 0:
					_invalid("invalid JSON escape")
					return null
		_invalid("unterminated JSON string")
		return null

	func _literal(text: String) -> void:
		if source.substr(index, text.length()) != text:
			_invalid("invalid JSON literal")
			return
		index += text.length()

	func _hex4(text: String) -> bool:
		if text.length() != 4:
			return false
		for position in 4:
			var unit: int = text.unicode_at(position)
			var hex: bool = (unit >= 48 and unit <= 57) or (unit >= 65 and unit <= 70) or (unit >= 97 and unit <= 102)
			if not hex:
				return false
		return true
