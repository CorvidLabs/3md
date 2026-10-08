class_name ThreeMDEditing
extends RefCounted

## Revision-checked document edits. A patch carries the canonical text it was
## built from. The addon returns a new snapshot or a ThreeMDError.

const _Errors = preload("res://addons/threemd/error.gd")
const _Storage = preload("res://addons/threemd/storage.gd")
const _Portable = preload("res://addons/threemd/portable.gd")
const _Documents = preload("res://addons/threemd/document.gd")
const _Planes = preload("res://addons/threemd/plane.gd")
const _Composition = preload("res://addons/threemd/composition.gd")

const _MAXIMUM_OPERATIONS: int = 1024

static func _fail(code: String, message: String, path: String = "") -> ThreeMDError:
	return _Errors.make(code, message, -1, path)

static func stable_id(value: Variant) -> Variant:
	var attributes: Dictionary = {}
	if typeof(value) == TYPE_DICTIONARY:
		var record: Dictionary = value
		if typeof(record.get("attributes", null)) != TYPE_DICTIONARY:
			return null
		attributes = record["attributes"]
	elif typeof(value) == TYPE_OBJECT and value != null:
		attributes = value.attributes
	else:
		return null
	if attributes.has("3md-id"):
		return str(attributes["3md-id"])
	return null

static func adopt_document(document: Object) -> Variant:
	var encoded: Variant = _Storage.encode_text(document)
	if _Errors.is_error(encoded):
		return _fail("invalidDocument", str(encoded.message))
	var identity: Variant = _validate_planes(document.planes, "")
	if _Errors.is_error(identity):
		return identity
	var adopted: Array = _adopt_planes(document.planes)
	var copy: Object = _copy_document(document, adopted)
	var checked: Variant = _Storage.encode_text(copy)
	if _Errors.is_error(checked):
		return _fail("invalidDocument", str(checked.message))
	return copy

static func snapshot(document: Object) -> Variant:
	var encoded: Variant = _Storage.encode_text(document)
	if _Errors.is_error(encoded):
		return _fail("invalidDocument", str(encoded.message))
	var identity: Variant = _validate_planes(document.planes, "")
	if _Errors.is_error(identity):
		return identity
	var bytes: PackedByteArray = encoded
	return {
		"document": _Portable.canonical_document(document),
		"revision": bytes.get_string_from_utf8(),
	}

static func apply(patch: Dictionary, snap: Dictionary) -> Variant:
	var operations: Array = patch["operations"]
	if operations.size() > _MAXIMUM_OPERATIONS:
		return _fail("operationLimit", "The transaction exceeds its operation limit.", "operations")
	var expected: String = str(patch["expected_revision"])
	if str(snap["revision"]) != expected:
		return _fail("staleRevision", "The document changed after this patch was prepared.", "expectedRevision")
	var current: Variant = snapshot(snap["document"])
	if _Errors.is_error(current):
		return current
	if str(current["revision"]) != str(snap["revision"]):
		return _fail("staleRevision", "Snapshot revision disagrees with its document.", "revision")
	var source: Object = snap["document"]
	var version: String = str(source.version)
	var axis: String = str(source.axis)
	var title: Variant = source.title
	var metadata: Dictionary = source.metadata.duplicate(true)
	var preamble: Variant = source.preamble
	var planes: Array = []
	for item in source.planes:
		planes.append(item)
	for index in operations.size():
		var operation: Dictionary = operations[index]
		var kind: String = str(operation["kind"])
		var path: String = "operations[" + str(index) + "]"
		if kind == "replaceHeader":
			var header: Dictionary = operation["header"]
			version = str(header["version"])
			axis = str(header["axis"])
			title = header.get("title", null)
			metadata = header["metadata"]
			preamble = header.get("preamble", null)
		elif kind == "insert":
			var at: int = int(operation["at"])
			if not _Portable.bounded_integer(at, 0, planes.size()):
				return _fail("invalidIndex", "Insertion index is outside the source-order list.", path)
			var inserted_id: Variant = stable_id(operation["plane"])
			if inserted_id == null:
				return _fail("missingIdentity", "An inserted plane needs a stable identity.", path)
			if not _Portable.valid_id(str(inserted_id)):
				return _fail("invalidIdentity", "An edit target must be a safe nonempty ASCII ID.", path)
			if _has_id(planes, str(inserted_id)):
				return _fail("duplicateIdentity", "An inserted plane identity is already used.", path)
			planes.insert(at, operation["plane"])
		elif kind == "remove":
			var removed: Variant = _locate(str(operation["id"]), planes, path)
			if _Errors.is_error(removed):
				return removed
			planes.remove_at(int(removed))
		elif kind == "replace":
			var replaced: Variant = _locate(str(operation["id"]), planes, path)
			if _Errors.is_error(replaced):
				return replaced
			if str(stable_id(operation["plane"])) != str(operation["id"]):
				return _fail("identityChanged", "Replacement must retain the target identity.", path)
			planes[int(replaced)] = operation["plane"]
		elif kind == "move":
			var moved: Variant = _locate(str(operation["id"]), planes, path)
			if _Errors.is_error(moved):
				return moved
			var destination: int = int(operation["to"])
			if not _Portable.bounded_integer(destination, 0, planes.size() - 1):
				return _fail("invalidIndex", "Move index is outside the final source-order list.", path)
			var plane: Object = planes[int(moved)]
			planes.remove_at(int(moved))
			planes.insert(destination, plane)
		else:
			return _fail("invalidDocument", "Unknown edit operation.", path)
	var positions: Array[float] = []
	for plane_index in planes.size():
		var z: float = planes[plane_index].z
		if is_nan(z):
			continue
		for prior in positions:
			if prior == z:
				return _fail("duplicatePosition", "Final plane positions must be unique.", "planes[" + str(plane_index) + "].z")
		positions.append(z)
	var result: Object = _copy_document_fields(version, axis, title, metadata, preamble, planes)
	var revised: Variant = snapshot(result)
	if _Errors.is_error(revised):
		return _fail("invalidDocument", str(revised.message))
	return revised

static func adopt_composition(composition: Object) -> Variant:
	var entries: Array = []
	for item in composition.entries:
		var entry: Dictionary = item
		var identity: Variant = _validate_planes(entry["document"].planes, "")
		if _Errors.is_error(identity):
			return identity
		var references: Variant = _validate_references(entry["references"])
		if _Errors.is_error(references):
			return references
		var adopted_document: Variant = adopt_document(entry["document"])
		if _Errors.is_error(adopted_document):
			return adopted_document
		entries.append({
			"id": str(entry["id"]),
			"document": adopted_document,
			"references": _adopt_references(entry["references"]),
		})
	return _Composition.make(str(composition.root_id), entries)

static func composition_snapshot(composition: Object) -> Variant:
	var encoded: Variant = _Composition.encode(composition)
	if _Errors.is_error(encoded):
		return encoded
	var bytes: PackedByteArray = encoded
	return {
		"composition": composition,
		"revision": bytes.get_string_from_utf8(),
	}

static func apply_composition(patch: Dictionary, snap: Dictionary) -> Variant:
	var operations: Array = patch["operations"]
	if operations.size() > _MAXIMUM_OPERATIONS:
		return _fail("operationLimit", "The transaction exceeds its operation limit.", "operations")
	var expected: String = str(patch["expected_revision"])
	if str(snap["revision"]) != expected:
		return _fail("staleRevision", "The composition changed after this patch was prepared.", "expectedRevision")
	var current: Variant = composition_snapshot(snap["composition"])
	if _Errors.is_error(current):
		return current
	if str(current["revision"]) != str(snap["revision"]):
		return _fail("staleRevision", "Snapshot revision disagrees with its composition.", "revision")
	var source: Object = snap["composition"]
	var root_id: String = str(source.root_id)
	var entries: Array = []
	for item in source.entries:
		var existing: Dictionary = item
		entries.append(existing)
	for index in operations.size():
		var operation: Dictionary = operations[index]
		var kind: String = str(operation["kind"])
		var path: String = "operations[" + str(index) + "]"
		if kind != "replaceEntry":
			return _fail("invalidDocument", "Unknown edit operation.", path)
		var position: Variant = _locate_entry(str(operation["id"]), entries, path)
		if _Errors.is_error(position):
			return position
		var replacement: Dictionary = operation["entry"]
		if str(replacement["id"]) != str(operation["id"]):
			return _fail("identityChanged", "Replacement must retain its definition ID.", path)
		entries[int(position)] = replacement
	var made: Variant = _Composition.make(root_id, entries)
	if _Errors.is_error(made):
		return made
	return composition_snapshot(made)

static func _validate_planes(planes: Array, path_prefix: String) -> Variant:
	var ids: Dictionary = {}
	for index in planes.size():
		var id: Variant = stable_id(planes[index])
		if id == null:
			continue
		var path: String = path_prefix + "planes[" + str(index) + "].attributes[3md-id]"
		if not _Portable.valid_id(str(id)):
			return _fail("invalidIdentity", "Plane identity must be a safe nonempty ASCII ID.", path)
		if ids.has(str(id)):
			return _fail("duplicateIdentity", "Plane identity is already used in this document.", path)
		ids[str(id)] = true
	return null

static func _adopt_planes(planes: Array) -> Array:
	var ids: Dictionary = {}
	for item in planes:
		var existing: Variant = stable_id(item)
		if existing != null:
			ids[str(existing)] = true
	var next: int = 1
	var adopted: Array = []
	for item in planes:
		var existing_id: Variant = stable_id(item)
		if existing_id != null:
			adopted.append(item)
			continue
		while ids.has("plane-" + str(next)):
			next += 1
		var assigned: String = "plane-" + str(next)
		ids[assigned] = true
		next += 1
		var plane: Object = _copy_plane(item)
		var attributes: Dictionary = plane.attributes.duplicate(true)
		attributes["3md-id"] = assigned
		plane.attributes = attributes
		adopted.append(plane)
	return adopted

static func _has_id(planes: Array, id: String) -> bool:
	for item in planes:
		var existing: Variant = stable_id(item)
		if existing != null and str(existing) == id:
			return true
	return false

static func _validate_references(references: Array) -> Variant:
	var ids: Dictionary = {}
	for index in references.size():
		var id: Variant = stable_id(references[index])
		if id == null:
			continue
		var path: String = "references[" + str(index) + "].attributes[3md-id]"
		if not _Portable.valid_id(str(id)):
			return _fail("invalidIdentity", "Reference identity must be a safe nonempty ASCII ID.", path)
		if ids.has(str(id)):
			return _fail("duplicateIdentity", "Reference identity is already used by this owner.", path)
		ids[str(id)] = true
	return null

static func _adopt_references(references: Array) -> Array:
	var ids: Dictionary = {}
	for item in references:
		var existing: Variant = stable_id(item)
		if existing != null:
			ids[str(existing)] = true
	var next: int = 1
	var adopted: Array = []
	for item in references:
		var reference: Dictionary = item
		var existing_id: Variant = stable_id(reference)
		var attributes: Dictionary = reference["attributes"].duplicate(true)
		if existing_id == null:
			while ids.has("reference-" + str(next)):
				next += 1
			var assigned: String = "reference-" + str(next)
			ids[assigned] = true
			next += 1
			attributes["3md-id"] = assigned
		adopted.append({
			"target_id": str(reference["target_id"]) if reference.has("target_id") else str(reference.get("targetID", "")),
			"attributes": attributes,
		})
	return adopted

static func _locate_entry(id: String, entries: Array, path: String) -> Variant:
	if not _Portable.valid_id(id):
		return _fail("invalidIdentity", "An edit target must be a safe nonempty ASCII ID.", path)
	for index in entries.size():
		var entry: Dictionary = entries[index]
		if str(entry["id"]) == id:
			return index
	return _fail("missingTarget", "The owning definition does not exist.", path)

static func _locate(id: String, planes: Array, path: String) -> Variant:
	if not _Portable.valid_id(id):
		return _fail("invalidIdentity", "An edit target must be a safe nonempty ASCII ID.", path)
	for index in planes.size():
		var existing: Variant = stable_id(planes[index])
		if existing != null and str(existing) == id:
			return index
	return _fail("missingTarget", "The target plane identity does not exist.", path)

static func _copy_plane(source: Object) -> Object:
	var plane = _Planes.new()
	plane.z = source.z
	plane.x = source.x
	plane.y = source.y
	plane.label = source.label
	plane.body = source.body
	plane.attributes = source.attributes.duplicate(true)
	return plane

static func _copy_document(source: Object, planes: Array) -> Object:
	return _copy_document_fields(str(source.version), str(source.axis), source.title, source.metadata, source.preamble, planes)

static func _copy_document_fields(version: String, axis: String, title: Variant, metadata: Dictionary, preamble: Variant, planes: Array) -> Object:
	var document = _Documents.new()
	document.version = version
	document.axis = axis
	document.title = title
	document.metadata = metadata.duplicate(true)
	document.preamble = preamble
	document.planes = planes
	return document
