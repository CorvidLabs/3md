class_name ThreeMDBig
extends RefCounted

## Non-negative integer, base 2^30, least-significant limb first.
## Used for correctly rounded double conversion. GDScript int multiplication
## wraps at 64 bits, and Godot's float parser is not correctly rounded.

const BASE: int = 1 << 30
const MASK: int = BASE - 1

## Godot 4.7 treats // as a comment. Float division is exact enough for the
## numerators this file builds (under 2^61) once the quotient is corrected.
## The product of that correction stays inside a signed 64-bit int.
static func idiv(numerator: int, denominator: int) -> int:
	if denominator <= 0 or numerator <= 0:
		return 0
	var quotient: int = int(float(numerator) / float(denominator))
	var product: int = quotient * denominator
	while product > numerator:
		quotient -= 1
		product -= denominator
	while numerator - product >= denominator:
		quotient += 1
		product += denominator
	return quotient

static func imod(numerator: int, denominator: int) -> int:
	return numerator - idiv(numerator, denominator) * denominator

var limbs: Array[int] = []

static func from_int(value: int) -> ThreeMDBig:
	var result := ThreeMDBig.new()
	var rest: int = value
	while rest > 0:
		result.limbs.append(rest & MASK)
		rest >>= 30
	return result

## Decimal digits can exceed a signed 64-bit int. Fixed-point spellings such as
## 100000000000000000000.0 show up in other languages' legacy text.
static func from_decimal(text: String) -> ThreeMDBig:
	var result := ThreeMDBig.new()
	for index in text.length():
		var digit: int = text.unicode_at(index) - 48
		result = result.mul_small(10)
		if digit != 0:
			result = result.add_small(digit)
	return result

func clone() -> ThreeMDBig:
	var copy := ThreeMDBig.new()
	copy.limbs = limbs.duplicate()
	return copy

func trim() -> void:
	while limbs.size() > 0 and limbs[limbs.size() - 1] == 0:
		limbs.remove_at(limbs.size() - 1)

func _significant() -> int:
	var count: int = limbs.size()
	while count > 0 and limbs[count - 1] == 0:
		count -= 1
	return count

func is_zero() -> bool:
	return _significant() == 0

func bit_length() -> int:
	var count: int = _significant()
	if count == 0:
		return 0
	var top: int = limbs[count - 1]
	var bits: int = 0
	while top > 0:
		top >>= 1
		bits += 1
	return (count - 1) * 30 + bits

func compare(other: ThreeMDBig) -> int:
	var left: int = _significant()
	var right: int = other._significant()
	if left != right:
		return 1 if left > right else -1
	for index in range(left - 1, -1, -1):
		if limbs[index] != other.limbs[index]:
			return 1 if limbs[index] > other.limbs[index] else -1
	return 0

func add(other: ThreeMDBig) -> ThreeMDBig:
	var result := ThreeMDBig.new()
	var carry: int = 0
	var count: int = maxi(limbs.size(), other.limbs.size())
	for index in count:
		var total: int = carry
		if index < limbs.size():
			total += limbs[index]
		if index < other.limbs.size():
			total += other.limbs[index]
		result.limbs.append(total & MASK)
		carry = total >> 30
	if carry > 0:
		result.limbs.append(carry)
	return result

func add_small(value: int) -> ThreeMDBig:
	return add(from_int(value))

func sub(other: ThreeMDBig) -> ThreeMDBig:
	var result := ThreeMDBig.new()
	var borrow: int = 0
	for index in limbs.size():
		var value: int = limbs[index] - borrow
		if index < other.limbs.size():
			value -= other.limbs[index]
		if value < 0:
			value += BASE
			borrow = 1
		else:
			borrow = 0
		result.limbs.append(value & MASK)
	return result

func mul_small(factor: int) -> ThreeMDBig:
	if factor == 0 or is_zero():
		return ThreeMDBig.new()
	var result := ThreeMDBig.new()
	var carry: int = 0
	for limb in limbs:
		var value: int = limb * factor + carry
		result.limbs.append(value & MASK)
		carry = value >> 30
	while carry > 0:
		result.limbs.append(carry & MASK)
		carry >>= 30
	return result

func mul(other: ThreeMDBig) -> ThreeMDBig:
	if is_zero() or other.is_zero():
		return ThreeMDBig.new()
	var result := ThreeMDBig.new()
	var width: int = other._significant()
	for index in width:
		var limb: int = other.limbs[index]
		if limb == 0:
			continue
		result = result.add(mul_small(limb).shl_limbs(index))
	return result

func mul_int(value: int) -> ThreeMDBig:
	var result := ThreeMDBig.new()
	var rest: int = value
	var shift: int = 0
	while rest > 0:
		var chunk: int = rest & MASK
		if chunk != 0:
			result = result.add(mul_small(chunk).shl(shift))
		rest >>= 30
		shift += 30
	return result

func shl(bits: int) -> ThreeMDBig:
	if bits == 0 or is_zero():
		return clone()
	var words: int = idiv(bits, 30)
	var result := shl_limbs(words)
	var rem: int = imod(bits, 30)
	if rem == 0:
		return result
	var shifted := ThreeMDBig.new()
	var carry: int = 0
	for limb in result.limbs:
		var value: int = (limb << rem) + carry
		shifted.limbs.append(value & MASK)
		carry = value >> 30
	if carry > 0:
		shifted.limbs.append(carry)
	return shifted

func shl_limbs(count: int) -> ThreeMDBig:
	var result := ThreeMDBig.new()
	for _index in count:
		result.limbs.append(0)
	for limb in limbs:
		result.limbs.append(limb)
	return result

func shr(bits: int) -> ThreeMDBig:
	if bits == 0:
		return clone()
	if bits >= bit_length():
		return ThreeMDBig.new()
	var word: int = idiv(bits, 30)
	var rem: int = imod(bits, 30)
	var result := ThreeMDBig.new()
	var carry: int = 0
	for index in range(limbs.size() - 1, word - 1, -1):
		var value: int = limbs[index]
		var next: int = (value << (30 - rem)) & MASK if rem != 0 else 0
		result.limbs.push_front(((value >> rem) | carry) & MASK)
		carry = next if rem != 0 else 0
	result.trim()
	return result

func divmod_small(divisor: int) -> Array:
	var result := ThreeMDBig.new()
	result.limbs.resize(limbs.size())
	var rest: int = 0
	for index in range(limbs.size() - 1, -1, -1):
		var current: int = rest * BASE + limbs[index]
		result.limbs[index] = idiv(current, divisor)
		rest = imod(current, divisor)
	result.trim()
	return [result, rest]

func divmod(den: ThreeMDBig) -> Array:
	var divisor := den.clone()
	divisor.trim()
	var dividend := clone()
	dividend.trim()
	if divisor.is_zero():
		return [ThreeMDBig.new(), ThreeMDBig.new()]
	if dividend.compare(divisor) < 0:
		return [ThreeMDBig.new(), dividend]
	var shift: int = 0
	var top: int = divisor.limbs[divisor.limbs.size() - 1]
	while top < (BASE >> 1):
		top <<= 1
		shift += 1
	var remain := dividend.shl(shift)
	var normalized := divisor.shl(shift)
	var quotient := ThreeMDBig.new()
	var width: int = remain.limbs.size() - normalized.limbs.size()
	quotient.limbs.resize(width + 1)
	for place in range(width, -1, -1):
		var high_index: int = place + normalized.limbs.size()
		var rem_high: int = remain._limb(high_index)
		var rem_next: int = remain._limb(high_index - 1)
		var estimate: int = idiv(rem_high * BASE + rem_next, normalized.limbs[normalized.limbs.size() - 1])
		if estimate > MASK:
			estimate = MASK
		while estimate > 0 and remain.compare(normalized.mul_small(estimate).shl_limbs(place)) < 0:
			estimate -= 1
		if estimate > 0:
			remain = remain.sub(normalized.mul_small(estimate).shl_limbs(place))
		quotient.limbs[place] = estimate
	quotient.trim()
	return [quotient, remain.shr(shift)]

func to_int() -> int:
	var value: int = 0
	for index in range(limbs.size() - 1, -1, -1):
		value = (value << 30) | limbs[index]
	return value

func decimal() -> String:
	if is_zero():
		return "0"
	var chunks: PackedStringArray = PackedStringArray()
	var current := clone()
	while not current.is_zero():
		var split: Array = current.divmod_small(1000000000)
		current = split[0]
		var chunk: int = split[1]
		chunks.append("%09d" % chunk)
	var text: String = chunks[chunks.size() - 1]
	var trimmed: String = text
	while trimmed.begins_with("0") and trimmed.length() > 1:
		trimmed = trimmed.substr(1)
	var body: String = trimmed
	for index in range(chunks.size() - 2, -1, -1):
		body += chunks[index]
	return body

func _limb(index: int) -> int:
	if index < 0 or index >= limbs.size():
		return 0
	return limbs[index]
