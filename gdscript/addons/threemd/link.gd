class_name ThreeMDLink
extends RefCounted

## A [[z=N]] or [[z=N|text]] reference inside a plane body.

var source_z: float = 0.0
var target_z: float = 0.0
var text: Variant = null
var target_exists: bool = false

func to_dictionary() -> Dictionary:
	return {
		"sourceZ": source_z,
		"targetZ": target_z,
		"text": text,
		"targetExists": target_exists,
	}
