class_name ThreeMDError
extends RefCounted

## A structured failure from the addon. GDScript has no exceptions, so parsers
## and codecs return one of these instead of raising.

var threemd_error: bool = true
var code: String = ""
var message: String = ""
var line: int = -1
var detail: String = ""

static func make(code: String, message: String, line: int = -1, detail: String = "") -> ThreeMDError:
	var error := ThreeMDError.new()
	error.code = code
	error.message = message
	error.line = line
	error.detail = detail
	return error

static func is_error(value: Variant) -> bool:
	if typeof(value) != TYPE_OBJECT or value == null:
		return false
	return value.get("threemd_error") == true
