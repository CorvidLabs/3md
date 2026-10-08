class_name ThreeMDFileComposition
extends RefCounted

## Linked file composition. The caller supplies path and bytes.
## This script never opens a filesystem or network path.

const _Errors = preload("res://addons/threemd/error.gd")
const _Portable = preload("res://addons/threemd/portable.gd")
const _Storage = preload("res://addons/threemd/storage.gd")
const _Composition = preload("res://addons/threemd/composition.gd")

const _DISCOVERY_DEPTH: int = 64
const _LEDGER_OVERHEAD: int = 17

static func _fail(code: String, detail: Variant = null) -> ThreeMDError:
	var message: String = code if detail == null else code + ": " + str(detail)
	var detail_text: String = "" if detail == null else str(detail)
	return _Errors.make(code, message, -1, detail_text)

static func _canceled(token: Variant) -> bool:
	if token == null:
		return false
	if typeof(token) == TYPE_BOOL:
		return token
	if typeof(token) == TYPE_OBJECT and token.has_method("is_canceled"):
		return token.is_canceled() == true
	return false

static func _cancel() -> ThreeMDError:
	return _Errors.make("canceled", "The operation was canceled.", -1, "")

static func ledger(document: Object, token: Variant = null) -> Variant:
	if _canceled(token):
		return _cancel()
	var metadata: Dictionary = document.metadata
	if not metadata.has("3md-files"):
		return []
	var value: Variant = metadata["3md-files"]
	if typeof(value) != TYPE_STRING:
		return _fail("invalidLedger")
	var text: String = value
	var maximum: int = _Portable.MAXIMUM_INTEGER
	if text.length() > maximum or _Portable.utf8_length(text) > maximum:
		return _fail("inputLimit")
	var scanner := _LedgerScanner.new()
	scanner.source = text
	scanner.token = token
	return scanner.scan()

static func resolve_path(source: String, relative_to: Variant = null, token: Variant = null) -> Variant:
	if _canceled(token):
		return _cancel()
	var remaining: int = _Portable.MAXIMUM_INTEGER
	var spent: Variant = _path_bytes(source, remaining, token)
	if _Errors.is_error(spent):
		return spent
	remaining -= int(spent)
	if relative_to == null:
		return _normalized(source, _project_root(), token)
	var base_spent: Variant = _path_bytes(str(relative_to), remaining, token)
	if _Errors.is_error(base_spent):
		return base_spent
	var base_path: Variant = _normalized(str(relative_to), _project_root(), token)
	if _Errors.is_error(base_path):
		return base_path
	return _normalized(source, _containing(str(base_path)), token)

static func resolve(root_path: String, sources: Array, limits: Variant = null, token: Variant = null, document_limits: Variant = null) -> Variant:
	if _canceled(token):
		return _cancel()
	var resolved_limits: Variant = _Composition.resolve_limits(limits)
	if _Errors.is_error(resolved_limits):
		return resolved_limits
	var limit_values: Dictionary = resolved_limits
	if sources.size() > int(limit_values["maximumDefinitions"]):
		return _fail("inputLimit")
	var path_budget: int = int(limit_values["maximumProfileBytes"])
	var root_spent: Variant = _path_bytes(root_path, path_budget, token)
	if _Errors.is_error(root_spent):
		return root_spent
	path_budget -= int(root_spent)
	for item in sources:
		if typeof(item) != TYPE_DICTIONARY:
			return _fail("invalidPath")
		var source: Dictionary = item
		var spent: Variant = _path_bytes(str(source.get("path", "")), path_budget, token)
		if _Errors.is_error(spent):
			return spent
		path_budget -= int(spent)
	var root: Variant = _normalized(root_path, _project_root(), token)
	if _Errors.is_error(root):
		return root
	var index: Dictionary = {}
	for item in sources:
		if _canceled(token):
			return _cancel()
		var indexed: Dictionary = item
		var normalized_path: Variant = _normalized(str(indexed.get("path", "")), _project_root(), token)
		if _Errors.is_error(normalized_path):
			return normalized_path
		if index.has(str(normalized_path)):
			return _fail("duplicatePath", str(normalized_path))
		index[str(normalized_path)] = indexed
	var state: Dictionary = {
		"limits": limit_values,
		"index": index,
		"files": {},
		"active": {},
		"encoded_bytes": 0,
		"definitions": 0,
		"references": 0,
		"token": token,
		"document_limits": document_limits,
	}
	var root_file: Variant = _visit(str(root), 0, state)
	if _Errors.is_error(root_file):
		return root_file
	var files: Dictionary = state["files"]
	var paths: Array = files.keys()
	paths.sort_custom(func(left: String, right: String) -> bool: return left < right)
	var assigned: Dictionary = {}
	var file_root_ids: Dictionary = {}
	var ordinal: int = 0
	for path_item in paths:
		if _canceled(token):
			return _cancel()
		var path: String = str(path_item)
		var file: Dictionary = files[path]
		var ids: Dictionary = {}
		var file_entries: Array = _sorted_entries(file["entries"])
		for entry_item in file_entries:
			var entry: Dictionary = entry_item
			ids[str(entry["id"])] = "file-%06d" % ordinal
			ordinal += 1
		assigned[path] = ids
		file_root_ids[path] = str(ids[str(file["root_id"])])
	var bundled: Array = []
	for path_item in paths:
		var bundle_path: String = str(path_item)
		var bundle_file: Dictionary = files[bundle_path]
		var bundle_ids: Dictionary = assigned[bundle_path]
		for entry_item in bundle_file["entries"]:
			if _canceled(token):
				return _cancel()
			var bundle_entry: Dictionary = entry_item
			var metadata: Dictionary = {}
			var original: Dictionary = bundle_entry["document"].metadata
			for key in original:
				if str(key) != "3md-files":
					metadata[key] = original[key]
			var document: Object = _Portable.canonical_document(bundle_entry["document"])
			document.metadata = metadata
			var edges: Array = []
			var raw_edges: Array = bundle_entry["references"]
			for edge_item in raw_edges:
				var edge: Dictionary = edge_item
				var target: String = str(bundle_ids[str(edge["target_id"])]) if edge.has("target_id") else str(bundle_ids[str(edge["targetID"])])
				edges.append({"target_id": target, "attributes": edge["attributes"]})
			var links: Dictionary = bundle_file["links"]
			var linked: Array = links.get(str(bundle_entry["id"]), [])
			for link_item in linked:
				if _canceled(token):
					return _cancel()
				var link: Dictionary = link_item
				edges.append({
					"target_id": str(file_root_ids[str(link["path"])]),
					"attributes": {"glyph": str(link["glyph"]), "source-file": str(link["path"])},
				})
			bundled.append({"id": str(bundle_ids[str(bundle_entry["id"])]), "document": document, "references": edges})
	var composition: Variant = _Composition.make(str(file_root_ids[str(root)]), bundled, limit_values, token)
	if _Errors.is_error(composition):
		return composition
	var encoded: Variant = _Composition.encode(composition, limit_values, token)
	if _Errors.is_error(encoded):
		return encoded
	if _canceled(token):
		return _cancel()
	return {
		"root_path": str(root),
		"composition": composition,
		"file_root_ids": file_root_ids,
		"resolved_paths": paths,
	}

static func _visit(path: String, active_depth: int, state: Dictionary) -> Variant:
	if _canceled(state["token"]):
		return _cancel()
	var active: Dictionary = state["active"]
	if active.has(path):
		return _Composition._fail("cycle", path)
	var files: Dictionary = state["files"]
	if files.has(path):
		var prior: Dictionary = files[path]
		if active_depth >= _DISCOVERY_DEPTH or int(prior["depth"]) > _DISCOVERY_DEPTH - active_depth:
			return _Composition._fail("depthExceeded")
		return prior
	if active_depth >= _DISCOVERY_DEPTH:
		return _Composition._fail("depthExceeded")
	var index: Dictionary = state["index"]
	if not index.has(path):
		return _fail("missingFile", path)
	var source: Dictionary = index[path]
	var data: PackedByteArray = source["data"]
	var limits: Dictionary = state["limits"]
	var encoded_bytes: int = int(state["encoded_bytes"])
	if data.size() > int(limits["maximumProfileBytes"]) - encoded_bytes:
		return _fail("inputLimit")
	state["encoded_bytes"] = encoded_bytes + data.size()
	var decoded: Variant = _Storage.decode(data)
	if _Errors.is_error(decoded) or decoded == null:
		return decoded if _Errors.is_error(decoded) else _fail("invalidLedger")
	var document: Object = decoded
	var composition: Variant = null
	if _Composition.is_composition(document):
		composition = _Composition.decode(document, limits, state["token"])
		if _Errors.is_error(composition):
			return composition
	var entries: Array = []
	var root_id: String = "root"
	if composition != null:
		entries = composition.entries
		root_id = str(composition.root_id)
		if state["document_limits"] != null:
			for limited_item in entries:
				var limited_entry: Dictionary = limited_item
				var limited: Variant = _Storage.enforce_document_limits(limited_entry["document"], state["document_limits"])
				if _Errors.is_error(limited):
					return limited
	else:
		if state["document_limits"] != null:
			var plain_limited: Variant = _Storage.enforce_document_limits(document, state["document_limits"])
			if _Errors.is_error(plain_limited):
				return plain_limited
		entries = [{"id": "root", "document": document, "references": []}]
	var definitions: int = int(state["definitions"])
	if entries.size() > int(limits["maximumDefinitions"]) - definitions:
		return _Composition._fail("tooManyDefinitions")
	state["definitions"] = definitions + entries.size()
	active[path] = true
	var links: Dictionary = {}
	var depth: int = 1
	if _canceled(state["token"]):
		return _cancel()
	var owner: Dictionary = _containing(path)
	var targets: Dictionary = {}
	for entry_item in _sorted_entries(entries):
		if _canceled(state["token"]):
			return _cancel()
		var entry: Dictionary = entry_item
		var ledger_value: Variant = ledger(entry["document"], state["token"])
		if _Errors.is_error(ledger_value):
			return ledger_value
		var ledger_entries: Array = ledger_value
		var raw_references: Array = entry["references"]
		var count: int = raw_references.size() + ledger_entries.size()
		var references: int = int(state["references"])
		if count > int(limits["maximumReferences"]) - references:
			return _Composition._fail("tooManyReferences")
		state["references"] = references + count
		var resolved_links: Array = []
		for reference_item in ledger_entries:
			if _canceled(state["token"]):
				return _cancel()
			var reference: Dictionary = reference_item
			var child: Variant = targets.get(str(reference["source"]), null)
			if child == null:
				var child_path: Variant = _resolve_reference(str(reference["source"]), owner, int(limits["maximumReferenceAttributeBytes"]), state["token"])
				if _Errors.is_error(child_path):
					return child_path
				child = _visit(str(child_path), active_depth + 1, state)
				if _Errors.is_error(child):
					return child
				targets[str(reference["source"])] = child
			var child_file: Dictionary = child
			var next_depth: int = int(child_file["depth"]) + 1
			if next_depth > depth:
				depth = next_depth
			if depth > _DISCOVERY_DEPTH:
				return _Composition._fail("depthExceeded")
			resolved_links.append({"glyph": str(reference["glyph"]), "path": str(child_file["path"])})
		links[str(entry["id"])] = resolved_links
	var result: Dictionary = {
		"path": path,
		"root_id": root_id,
		"entries": entries,
		"links": links,
		"depth": depth,
	}
	files[path] = result
	active.erase(path)
	return result

static func _resolve_reference(source: String, owner: Dictionary, maximum_attribute_bytes: int, token: Variant) -> Variant:
	if _canceled(token):
		return _cancel()
	var maximum: int = _Portable.MAXIMUM_INTEGER
	var spent: Variant = _path_bytes(source, maximum, token)
	if _Errors.is_error(spent):
		return spent
	var remaining: int = maximum - int(spent)
	if int(owner["bytes"]) > remaining:
		return _fail("inputLimit")
	var room: int = maximum_attribute_bytes - _LEDGER_OVERHEAD
	if room < 0:
		room = 0
	return _normalized(source, owner, token, room)

static func _path_bytes(path: String, remaining: int, token: Variant) -> Variant:
	if _canceled(token):
		return _cancel()
	if path.length() > remaining or _Portable.utf8_length(path) > remaining:
		return _fail("inputLimit")
	return _Portable.utf8_length(path)

static func _project_root() -> Dictionary:
	return {"path": "", "bytes": 0, "directory_ends": [], "directory_byte_ends": []}

static func _containing(path: String) -> Dictionary:
	var directory_ends: Array[int] = []
	var directory_byte_ends: Array[int] = []
	var bytes: int = 0
	for index in path.length():
		var unit: int = path.unicode_at(index)
		if unit == 47:
			directory_ends.append(index)
			directory_byte_ends.append(bytes)
		if unit < 0x80:
			bytes += 1
		elif unit < 0x800:
			bytes += 2
		elif unit < 0x10000:
			bytes += 3
		else:
			bytes += 4
	return {
		"path": path,
		"bytes": bytes,
		"directory_ends": directory_ends,
		"directory_byte_ends": directory_byte_ends,
	}

static func _normalized(source: String, base: Dictionary, token: Variant, maximum_bytes: int = -1) -> Variant:
	if _canceled(token):
		return _cancel()
	if source.is_empty() or source.begins_with("/"):
		return _fail("invalidPath", source)
	for index in source.length():
		if index % 4096 == 0 and _canceled(token):
			return _cancel()
		var unit: int = source.unicode_at(index)
		if unit <= 31 or unit == 127 or unit == 92 or unit == 58:
			return _fail("invalidPath", source)
	var kept: int = base["directory_ends"].size()
	var segments: Array[String] = []
	var normalized: String = _Portable.nfc(source)
	var parts: PackedStringArray = normalized.split("/", true)
	for segment in parts:
		if _canceled(token):
			return _cancel()
		if segment.is_empty():
			return _fail("invalidPath", source)
		if segment == ".":
			continue
		if segment == "..":
			if segments.size() > 0:
				segments.remove_at(segments.size() - 1)
			elif kept > 0:
				kept -= 1
			else:
				return _fail("invalidPath", source)
		else:
			segments.append(segment)
	if kept == 0 and segments.is_empty():
		return _fail("invalidPath", source)
	if maximum_bytes >= 0:
		var length: int = 0
		if kept > 0:
			var byte_ends: Array = base["directory_byte_ends"]
			length = int(byte_ends[kept - 1])
		for segment in segments:
			var separator: int = 1 if length > 0 else 0
			length += separator + _Portable.utf8_length(segment)
		if length > maximum_bytes:
			return _Composition._fail("referenceAttributesExceeded")
	var prefix: String = ""
	if kept > 0:
		var ends: Array = base["directory_ends"]
		prefix = str(base["path"]).substr(0, int(ends[kept - 1]))
	if segments.is_empty():
		return prefix
	var joined: String = "/".join(segments)
	if prefix.is_empty():
		return joined
	return prefix + "/" + joined

static func _sorted_entries(raw_entries: Array) -> Array:
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


class _LedgerScanner:
	const _Errors = preload("res://addons/threemd/error.gd")

	var index: int = 0
	var source: String = ""
	var token: Variant = null
	var problem: Variant = null

	func scan() -> Variant:
		var references: Array = []
		var keys: Dictionary = {}
		_whitespace()
		if problem != null:
			return problem
		if not _consume("{"):
			return _invalid()
		_whitespace()
		if not _consume("}"):
			while true:
				if problem != null:
					return problem
				var glyph: Variant = _string()
				if problem != null:
					return problem
				var glyph_text: String = str(glyph)
				var unit: int = glyph_text.unicode_at(0) if glyph_text.length() == 1 else -1
				if glyph_text.length() != 1 or unit < 33 or unit > 126:
					problem = _Errors.make("invalidGlyph", "invalidGlyph: " + glyph_text, -1, glyph_text)
					return problem
				if keys.has(glyph_text):
					return _invalid()
				keys[glyph_text] = true
				_whitespace()
				if not _consume(":"):
					return _invalid()
				_whitespace()
				var filename: Variant = _string()
				if problem != null:
					return problem
				references.append({"glyph": glyph_text, "source": str(filename)})
				_whitespace()
				if _consume("}"):
					break
				if not _consume(","):
					return _invalid()
				_whitespace()
		_whitespace()
		if index != source.length():
			return _invalid()
		var sorted: Array = []
		for item in references:
			var reference: Dictionary = item
			var placed: bool = false
			for position in sorted.size():
				var existing: Dictionary = sorted[position]
				if str(reference["glyph"]) < str(existing["glyph"]):
					sorted.insert(position, reference)
					placed = true
					break
			if not placed:
				sorted.append(reference)
		return sorted

	func _invalid() -> Variant:
		if problem == null:
			problem = _Errors.make("invalidLedger", "invalidLedger", -1, "")
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

	func _string() -> Variant:
		if not _consume("\""):
			return _invalid()
		var start: int = index - 1
		while index < source.length():
			if index % 4096 == 0 and _stop():
				return null
			var unit: int = source.unicode_at(index)
			index += 1
			if unit == 34:
				var raw: String = source.substr(start, index - start)
				var parsed: Variant = JSON.parse_string(raw)
				if typeof(parsed) != TYPE_STRING:
					if _stop():
						return null
					return _invalid()
				return str(parsed)
			if unit < 32:
				return _invalid()
			if unit == 92:
				if index >= source.length():
					return _invalid()
				var escaped: String = source.substr(index, 1)
				index += 1
				if escaped == "u":
					if index + 4 > source.length() or not _hex4(source.substr(index, 4)):
						return _invalid()
					index += 4
				elif "\"\\/bfnrt".find(escaped) < 0:
					return _invalid()
		return _invalid()

	func _hex4(text: String) -> bool:
		if text.length() != 4:
			return false
		for position in 4:
			var unit: int = text.unicode_at(position)
			var hex: bool = (unit >= 48 and unit <= 57) or (unit >= 65 and unit <= 70) or (unit >= 97 and unit <= 102)
			if not hex:
				return false
		return true
