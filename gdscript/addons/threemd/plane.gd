class_name ThreeMDPlane
extends RefCounted

## One slice of a document on the Z axis.

var z: float = 0.0
var label: Variant = null
var x: Variant = null
var y: Variant = null
var attributes: Dictionary = {}
var body: String = ""

func to_dictionary() -> Dictionary:
	return {
		"z": z,
		"label": label,
		"x": x,
		"y": y,
		"attributes": attributes,
		"body": body,
	}
