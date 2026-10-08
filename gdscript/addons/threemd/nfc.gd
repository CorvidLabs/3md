class_name ThreeMDUnicode
extends RefCounted

## Unicode 17 NFC, matching Node and Bun String.normalize("NFC").
## Hangul and every other canonical pair live in the generated table.

const _Data = preload("res://addons/threemd/nfc_data.gd")
const _Big = preload("res://addons/threemd/big.gd")

const _SBASE: int = 0xAC00
const _LBASE: int = 0x1100
const _VBASE: int = 0x1161
const _TBASE: int = 0x11A7
const _LCOUNT: int = 19
const _VCOUNT: int = 21
const _TCOUNT: int = 28
const _NCOUNT: int = 588
const _SCOUNT: int = 11172

static var _ready: bool = false
static var _ok: bool = false
static var _ccc: Dictionary = {}
static var _decomp: Dictionary = {}
static var _comp: Dictionary = {}

static func nfc(text: String) -> String:
	if text.is_empty():
		return text
	var ascii: bool = true
	for index in text.length():
		if text.unicode_at(index) >= 128:
			ascii = false
			break
	if ascii:
		return text
	_ensure()
	var chars: Array = []
	for index in text.length():
		_append_nfd(text.unicode_at(index), chars)
	_reorder(chars)
	return _from_codes(_compose(chars))

static func compare(left: String, right: String) -> int:
	var count: int = mini(left.length(), right.length())
	for index in count:
		var x: int = left.unicode_at(index)
		var y: int = right.unicode_at(index)
		if x != y:
			return -1 if x < y else 1
	if left.length() == right.length():
		return 0
	return 1 if left.length() > right.length() else -1

static func _ensure() -> void:
	if _ready:
		return
	_ready = true
	var raw: PackedByteArray = Marshalls.base64_to_raw(_Data.BLOB)
	if raw.size() != _Data.SIZE:
		return
	if raw.size() < 4 or raw.decode_u32(0) != 0x3143464E:
		return
	var offset: int = 4
	var combining_count: int = raw.decode_u32(offset)
	offset += 4
	for _index in combining_count:
		_ccc[raw.decode_u32(offset)] = raw.decode_u32(offset + 4)
		offset += 8
	var decomp_count: int = raw.decode_u32(offset)
	offset += 4
	for _index in decomp_count:
		var codepoint: int = raw.decode_u32(offset)
		var length: int = raw.decode_u32(offset + 4)
		offset += 8
		var parts: Array = []
		for _part in length:
			parts.append(raw.decode_u32(offset))
			offset += 4
		_decomp[codepoint] = parts
	var pair_count: int = raw.decode_u32(offset)
	offset += 4
	for _index in pair_count:
		var left: int = raw.decode_u32(offset)
		var right: int = raw.decode_u32(offset + 4)
		var composed: int = raw.decode_u32(offset + 8)
		offset += 12
		_comp[(left << 21) | right] = composed
	_ok = offset == raw.size()

static func _class_of(codepoint: int) -> int:
	if _ccc.has(codepoint):
		return int(_ccc[codepoint])
	return 0

static func _hangul_parts(codepoint: int) -> Array:
	if codepoint < _SBASE or codepoint >= _SBASE + _SCOUNT:
		return []
	var index: int = codepoint - _SBASE
	var lead: int = _LBASE + _Big.idiv(index, _NCOUNT)
	var vowel: int = _VBASE + _Big.idiv(_Big.imod(index, _NCOUNT), _TCOUNT)
	var trail: int = _TBASE + _Big.imod(index, _TCOUNT)
	if trail == _TBASE:
		return [lead, vowel]
	return [lead, vowel, trail]

static func _hangul_pair(left: int, right: int) -> int:
	if left >= _LBASE and left < _LBASE + _LCOUNT and right >= _VBASE and right < _VBASE + _VCOUNT:
		return _SBASE + ((left - _LBASE) * _VCOUNT + (right - _VBASE)) * _TCOUNT
	if left >= _SBASE and left < _SBASE + _SCOUNT and _Big.imod(left - _SBASE, _TCOUNT) == 0:
		if right > _TBASE and right < _TBASE + _TCOUNT:
			return left + (right - _TBASE)
	return -1

static func _append_nfd(codepoint: int, out: Array) -> void:
	var hangul: Array = _hangul_parts(codepoint)
	if not hangul.is_empty():
		for part in hangul:
			out.append(int(part))
		return
	if _decomp.has(codepoint):
		var parts: Array = _decomp[codepoint]
		for part in parts:
			_append_nfd(int(part), out)
	else:
		out.append(codepoint)

static func _reorder(chars: Array) -> void:
	var changed: bool = true
	while changed:
		changed = false
		var last: int = chars.size() - 1
		for index in last:
			var right: int = _class_of(int(chars[index + 1]))
			if right > 0 and _class_of(int(chars[index])) > right:
				var swap: int = int(chars[index])
				chars[index] = chars[index + 1]
				chars[index + 1] = swap
				changed = true

static func _compose(chars: Array) -> Array:
	if chars.is_empty():
		return chars
	var out: Array = [chars[0]]
	var starter: int = 0
	var last: int = _class_of(int(chars[0]))
	if last != 0:
		last = 256
	for index in range(1, chars.size()):
		var codepoint: int = int(chars[index])
		var klass: int = _class_of(codepoint)
		var composite: int = -1
		if last < klass or (last == 0 and klass == 0):
			composite = _composed(int(out[starter]), codepoint)
			if composite < 0:
				composite = _hangul_pair(int(out[starter]), codepoint)
		if composite >= 0:
			out[starter] = composite
		else:
			out.append(codepoint)
			if klass == 0:
				starter = out.size() - 1
				last = 0
			else:
				last = klass
	return out

static func _composed(left: int, right: int) -> int:
	var key: int = (left << 21) | right
	if _comp.has(key):
		return int(_comp[key])
	return -1

static func _from_codes(chars: Array) -> String:
	var text := ""
	for item in chars:
		text += String.chr(int(item))
	return text
