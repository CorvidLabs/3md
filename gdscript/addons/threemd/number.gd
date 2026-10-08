class_name ThreeMDNumber
extends RefCounted

const _Big = preload("res://addons/threemd/big.gd")

## Correctly rounded decimal conversion for 3md coordinates.
## Godot's float() and String.num_scientific do not match Swift, JavaScript, or Rust
## on every finite double, so this uses integer arithmetic only.

const _LIMIT_HIGH: int = 0x430C6BF5
const _LIMIT_LOW: int = 0x26340000
const _SMALL_HIGH: int = 0x3F1A36E2
const _SMALL_LOW: int = 0xEB1C432D
const _POW53_HIGH: int = 0x43400000
const _POW53_LOW: int = 0

static var _powers_of_10: Array = []
static var _powers_of_5: Array = []
static var _canonical_cache: Dictionary = {}
static var _parse_cache: Dictionary = {}

const _CACHE_LIMIT: int = 4096

static func parse_finite(text: String) -> Variant:
	if _parse_cache.has(text):
		var cached: Variant = _parse_cache[text]
		if typeof(cached) != TYPE_ARRAY:
			return null
		var bits: Array = cached
		return _join(int(bits[0]), int(bits[1]))
	var pattern: Array = _parse_pattern(text)
	if pattern.is_empty() or ((int(pattern[0]) >> 20) & 0x7FF) == 0x7FF:
		if _parse_cache.size() < _CACHE_LIMIT:
			_parse_cache[text] = false
		return null
	if _parse_cache.size() < _CACHE_LIMIT:
		_parse_cache[text] = pattern
	return _join(int(pattern[0]), int(pattern[1]))

static func canonical(value: float) -> String:
	if is_nan(value):
		return "nan"
	if is_inf(value):
		return "-inf" if value < 0.0 else "inf"
	var pattern: Array = _split(value)
	var key: String = "%d:%d" % [int(pattern[0]), int(pattern[1])]
	if _canonical_cache.has(key):
		return str(_canonical_cache[key])
	var text: String = _format(int(pattern[0]), int(pattern[1]))
	if _canonical_cache.size() < _CACHE_LIMIT:
		_canonical_cache[key] = text
	return text

static func _decimal_exponent(text: String) -> int:
	var sign: int = 1
	var digits: String = text
	if digits.begins_with("+"):
		digits = digits.substr(1)
	elif digits.begins_with("-"):
		sign = -1
		digits = digits.substr(1)
	if digits.length() > 6:
		return sign * 1000000
	return sign * int(digits)

static func _pow10(exp: int) -> ThreeMDBig:
	while _powers_of_10.size() <= exp:
		if _powers_of_10.is_empty():
			_powers_of_10.append(_Big.from_int(1))
		else:
			var previous: ThreeMDBig = _powers_of_10[_powers_of_10.size() - 1]
			_powers_of_10.append(previous.mul_small(10))
	return _powers_of_10[exp]

static func _pow5(exp: int) -> ThreeMDBig:
	while _powers_of_5.size() <= exp:
		if _powers_of_5.is_empty():
			_powers_of_5.append(_Big.from_int(1))
		else:
			var previous: ThreeMDBig = _powers_of_5[_powers_of_5.size() - 1]
			_powers_of_5.append(previous.mul_small(5))
	return _powers_of_5[exp]

static func _split(value: float) -> Array:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	var low: int = bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24)
	var high: int = bytes[4] | (bytes[5] << 8) | (bytes[6] << 16) | (bytes[7] << 24)
	return [high, low]

static func _join(high: int, low: int) -> float:
	var bytes := PackedByteArray()
	bytes.resize(8)
	for index in 4:
		bytes[index] = (low >> (index * 8)) & 0xFF
		bytes[index + 4] = (high >> (index * 8)) & 0xFF
	return bytes.decode_double(0)

static func _grammar(text: String) -> bool:
	if text.is_empty():
		return false
	var index: int = 0
	var first: int = text.unicode_at(0)
	if first == 43 or first == 45:
		index = 1
	var digits: bool = false
	while index < text.length():
		var unit: int = text.unicode_at(index)
		if unit < 48 or unit > 57:
			break
		digits = true
		index += 1
	if index < text.length() and text.unicode_at(index) == 46:
		index += 1
		while index < text.length():
			var unit: int = text.unicode_at(index)
			if unit < 48 or unit > 57:
				break
			digits = true
			index += 1
	if not digits:
		return false
	if index < text.length() and (text.unicode_at(index) == 101 or text.unicode_at(index) == 69):
		index += 1
		if index < text.length() and (text.unicode_at(index) == 43 or text.unicode_at(index) == 45):
			index += 1
		var exponent_digits: bool = false
		while index < text.length():
			var unit: int = text.unicode_at(index)
			if unit < 48 or unit > 57:
				break
			exponent_digits = true
			index += 1
		if not exponent_digits:
			return false
	return index == text.length()

static func _parse_pattern(text: String) -> Array:
	if not _grammar(text):
		return []
	var negative: bool = false
	var body: String = text
	var lead: int = body.unicode_at(0)
	if lead == 43 or lead == 45:
		negative = lead == 45
		body = body.substr(1)
	var split_at: int = -1
	for index in body.length():
		var unit: int = body.unicode_at(index)
		if unit == 101 or unit == 69:
			split_at = index
			break
	var mantissa: String = body if split_at < 0 else body.substr(0, split_at)
	var exponent: int = 0
	if split_at >= 0:
		exponent = _decimal_exponent(body.substr(split_at + 1))
	var point: int = mantissa.find(".")
	var digits: String = mantissa
	if point >= 0:
		exponent -= mantissa.length() - point - 1
		digits = mantissa.replace(".", "")
	# A double overflows or underflows long before 4096 decimal places.
	if exponent > 4096:
		var overflow: Array = [0x7FF00000, 0]
		if negative:
			overflow[0] = int(overflow[0]) | 0x80000000
		return overflow
	if exponent < -4096:
		return [0x80000000 if negative else 0, 0]
	var coeff: ThreeMDBig = _Big.from_decimal(digits)
	var num: ThreeMDBig
	var den: ThreeMDBig
	if exponent >= 0:
		num = _pow10(exponent).mul(coeff)
		den = _Big.from_int(1)
	else:
		num = coeff
		den = _pow10(-exponent)
	var pattern: Array = _positive_ratio(num, den)
	if pattern.is_empty():
		return []
	if negative:
		pattern[0] = int(pattern[0]) | 0x80000000
	return pattern

static func _floor_log(num: ThreeMDBig, den: ThreeMDBig) -> int:
	var log: int = num.bit_length() - den.bit_length()
	if log >= 0:
		if den.shl(log).compare(num) > 0:
			log -= 1
	elif num.shl(-log).compare(den) < 0:
		log -= 1
	return log

static func _round_big(quotient: ThreeMDBig, remainder: ThreeMDBig, den: ThreeMDBig) -> int:
	var q: int = quotient.to_int()
	var comparison: int = remainder.mul_small(2).compare(den)
	if comparison > 0 or (comparison == 0 and (q & 1) == 1):
		return q + 1
	return q

static func _pack_normal(exponent: int, quotient: int) -> Array:
	var fraction: int = quotient - (1 << 52)
	var field: int = exponent + 1023
	var bits: int = (field << 52) | fraction
	return [bits >> 32, bits & 0xFFFFFFFF]

static func _positive_ratio(num: ThreeMDBig, den: ThreeMDBig) -> Array:
	if num.is_zero():
		return [0, 0]
	if den.is_zero():
		return []
	var log: int = _floor_log(num, den)
	if log > 1023:
		return [0x7FF00000, 0]
	if log >= -1022:
		var shift: int = 52 - log
		var scaled: ThreeMDBig
		var used: ThreeMDBig
		if shift >= 0:
			scaled = num.shl(shift)
			used = den
		else:
			scaled = num
			used = den.shl(-shift)
		var split: Array = scaled.divmod(used)
		var quotient: int = _round_big(split[0], split[1], used)
		if quotient == (1 << 53):
			quotient >>= 1
			log += 1
		if log > 1023:
			return [0x7FF00000, 0]
		return _pack_normal(log, quotient)
	var scaled_sub: ThreeMDBig = num.shl(1074)
	var split_sub: Array = scaled_sub.divmod(den)
	var subnormal: int = _round_big(split_sub[0], split_sub[1], den)
	if subnormal == 0:
		return [0, 0]
	if subnormal >= (1 << 52):
		return [1 << 20, 0]
	# The fraction occupies 52 bits across both 32-bit words. 2^32 and above
	# do not fit in the low word.
	return [subnormal >> 32, subnormal & 0xFFFFFFFF]

static func _is_integer(high: int, low: int) -> bool:
	var field: int = (high >> 20) & 0x7FF
	var fraction: int = ((high & 0xFFFFF) << 32) | low
	if field == 0x7FF:
		return false
	if field == 0:
		return fraction == 0
	var unbiased: int = field - 1023
	if unbiased >= 52:
		return true
	if unbiased < 0:
		return false
	var mask: int = (1 << (52 - unbiased)) - 1
	return (fraction & mask) == 0

static func _below(high: int, low: int, other_high: int, other_low: int) -> bool:
	var magnitude: int = high & 0x7FFFFFFF
	if magnitude != other_high:
		return magnitude < other_high
	return low < other_low

static func _exact(high: int, low: int) -> Array:
	var negative: bool = (high & 0x80000000) != 0
	var sign: String = "-" if negative else ""
	var field: int = (high >> 20) & 0x7FF
	var fraction: int = ((high & 0xFFFFF) << 32) | low
	if field == 0 and fraction == 0:
		return ["0", 0, sign]
	var mant: int
	var exp2: int
	if field == 0:
		mant = fraction
		exp2 = -1074
	else:
		mant = fraction | (1 << 52)
		exp2 = field - 1075
	if exp2 >= 0:
		var digits: String = _Big.from_int(mant).shl(exp2).decimal()
		return [digits, digits.length(), sign]
	var scale: int = -exp2
	var digits_frac: String = _pow5(scale).mul_int(mant).decimal()
	return [digits_frac, digits_frac.length() - scale, sign]

static func _round_digits(digits: String, precision: int) -> Array:
	if precision >= digits.length():
		return [digits, 0]
	var head: String = digits.substr(0, precision)
	var follower: String = digits.substr(precision, 1)
	var rest: String = digits.substr(precision + 1)
	var carry: bool = false
	if follower > "5":
		carry = true
	elif follower == "5":
		var nonzero: bool = false
		for index in rest.length():
			if rest.unicode_at(index) != 48:
				nonzero = true
				break
		if nonzero or (int(head.substr(head.length() - 1, 1)) % 2 == 1):
			carry = true
	if not carry:
		return [head, 0]
	var bumped: String = str(int(head) + 1)
	if bumped.length() > head.length():
		return [bumped.substr(0, precision), 1]
	while bumped.length() < precision:
		bumped = "0" + bumped
	return [bumped, 0]

static func _pad(value: int, width: int) -> String:
	var text: String = str(value)
	while text.length() < width:
		text = "0" + text
	return text

static func _normalize_sci(sign: String, digits: String, exponent: int) -> String:
	var mantissa: String = digits if digits.length() == 1 else digits.substr(0, 1) + "." + digits.substr(1)
	var marker: String = "-" if exponent < 0 else "+"
	var width: String = _pad(absi(exponent), 2)
	return "%s%se%s%s" % [sign, mantissa, marker, width]

static func _format(high: int, low: int) -> String:
	if (high & 0x7FFFFFFF) == 0 and low == 0:
		return "0"
	if ((high >> 20) & 0x7FF) == 0x7FF:
		if ((high & 0xFFFFF) != 0) or low != 0:
			return "nan"
		return "-inf" if (high & 0x80000000) != 0 else "inf"
	var exact: Array = _exact(high, low)
	var digits: String = exact[0]
	var first_exp: int = exact[1]
	var sign: String = exact[2]
	var integer: bool = _is_integer(high, low)
	if integer and _below(high, low, _LIMIT_HIGH, _LIMIT_LOW):
		if first_exp <= 0:
			return "0"
		return sign + digits.substr(0, first_exp)
	var below_small: bool = _below(high, low, _SMALL_HIGH, _SMALL_LOW)
	var above_pow: bool = not _below(high, low, _POW53_HIGH, _POW53_LOW) and not _equal_mag(high, low, _POW53_HIGH, _POW53_LOW)
	var scientific: bool = ((high & 0x7FFFFFFF) != 0 or low != 0) and (below_small or above_pow)
	var limit: int = mini(17, digits.length())
	for precision in range(1, limit + 1):
		var rounded_pair: Array = _round_digits(digits, precision)
		var rounded: String = rounded_pair[0]
		var extra: int = rounded_pair[1]
		var options: Array = [[rounded, first_exp + extra]]
		if precision == rounded.length():
			var bumped_int: int = int(rounded) + 1
			var bumped: String = str(bumped_int)
			if bumped.length() == rounded.length():
				options.append([bumped, first_exp + extra])
			else:
				options.append([bumped.substr(0, precision), first_exp + extra + 1])
			if int(rounded) > 0:
				var dropped: String = _pad(int(rounded) - 1, rounded.length())
				if dropped.length() == rounded.length() and not dropped.begins_with("0"):
					options.append([dropped, first_exp + extra])
		for item in options:
			var candidate: Array = item
			var spelling: String = _spell(sign, candidate[0], candidate[1], scientific, integer)
			var parsed: Array = _parse_pattern(spelling)
			if parsed.size() == 2 and int(parsed[0]) == high and int(parsed[1]) == low:
				return spelling
	return sign + digits

static func _equal_mag(high: int, low: int, other_high: int, other_low: int) -> bool:
	return (high & 0x7FFFFFFF) == other_high and low == other_low

static func _spell(sign: String, rounded: String, exponent: int, scientific: bool, integer: bool) -> String:
	if scientific:
		return _normalize_sci(sign, rounded, exponent - 1)
	if exponent <= 0:
		return sign + "0." + "0".repeat(-exponent) + rounded
	if exponent >= rounded.length():
		var text: String = sign + rounded + "0".repeat(exponent - rounded.length())
		if integer:
			return text + ".0"
		return text
	return sign + rounded.substr(0, exponent) + "." + rounded.substr(exponent)
