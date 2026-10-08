class_name ThreeMDFiles
extends RefCounted

## Reads project files the game already chose. The parser, storage, and
## composition scripts never call this. Paths are project or absolute paths.

const _Errors = preload("res://addons/threemd/error.gd")
const _Storage = preload("res://addons/threemd/storage.gd")
const _Composition = preload("res://addons/threemd/composition.gd")
const _Linked = preload("res://addons/threemd/file_composition.gd")

static func load_document(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return _Errors.make("missingFile", "missingFile: " + path, -1, path)
	return _Storage.decode(FileAccess.get_file_as_bytes(path))

## `root_path` is relative to `folder`, for example `scene.3md` inside `res://village`.
## Ledger filenames stay relative to that same folder. The result is the linked
## composition, or a ThreeMDError.
static func load_linked(root_path: String, folder: String) -> Variant:
	var pending: Array[String] = [root_path]
	var seen: Dictionary = {}
	var sources: Array = []
	while not pending.is_empty():
		var relative: String = pending.pop_back()
		if seen.has(relative):
			continue
		seen[relative] = true
		var absolute: String = folder.path_join(relative)
		if not FileAccess.file_exists(absolute):
			continue
		var data: PackedByteArray = FileAccess.get_file_as_bytes(absolute)
		sources.append({"path": relative, "data": data})
		var decoded: Variant = _Storage.decode(data)
		if _Errors.is_error(decoded) or decoded == null:
			return decoded if _Errors.is_error(decoded) else _Errors.make("invalidText", "invalidText", -1, relative)
		var documents: Array = []
		if _Composition.is_composition(decoded):
			var composition: Variant = _Composition.decode(decoded)
			if _Errors.is_error(composition):
				return composition
			for item in composition.entries:
				var entry: Dictionary = item
				documents.append(entry["document"])
		else:
			documents.append(decoded)
		for document in documents:
			var ledger: Variant = _Linked.ledger(document)
			if _Errors.is_error(ledger):
				return ledger
			for item in ledger:
				var reference: Dictionary = item
				var resolved: Variant = _Linked.resolve_path(str(reference["source"]), relative)
				if _Errors.is_error(resolved):
					return resolved
				var next_path: String = str(resolved)
				if not seen.has(next_path):
					pending.append(next_path)
	return _Linked.resolve(root_path, sources)
