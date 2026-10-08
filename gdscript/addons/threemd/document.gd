class_name ThreeMDDocument
extends RefCounted

## A parsed 3md document. Optional title, preamble, and plane fields use null
## when the source omitted them. An empty string is a present empty value.

var version: String = ""
var axis: String = "layer"
var title: Variant = null
var metadata: Dictionary = {}
var preamble: Variant = null
var planes: Array = []

func to_dictionary() -> Dictionary:
	var encoded: Array = []
	for item in planes:
		encoded.append(item.to_dictionary())
	return {
		"version": version,
		"axis": axis,
		"title": title,
		"metadata": metadata,
		"preamble": preamble,
		"planes": encoded,
	}
