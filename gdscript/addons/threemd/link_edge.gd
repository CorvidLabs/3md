class_name ThreeMDLinkEdge
extends RefCounted

## One directed edge in a document's cross-plane link graph.

var source_z: float = 0.0
var target_z: float = 0.0
var target_exists: bool = false
var count: int = 0

func to_dictionary() -> Dictionary:
	return {
		"sourceZ": source_z,
		"targetZ": target_z,
		"targetExists": target_exists,
		"count": count,
	}
