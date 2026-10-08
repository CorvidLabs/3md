class_name ThreeMDChecksum
extends RefCounted

## CRC-32/ISO-HDLC for the version 1 binary container.
## Reflected polynomial 0xEDB88320, initial and final XOR 0xFFFFFFFF.
## The check value of ASCII "123456789" is 0xCBF43926.

const _STRIDE: int = 65536

static func crc32(bytes: PackedByteArray) -> int:
	return _finish(_update(0xFFFFFFFF, bytes, 0, bytes.size()))

static func container_checksum(container: PackedByteArray) -> int:
	var end: int = container.size()
	var value: int = _update(0xFFFFFFFF, container, 0, mini(36, end))
	var start: int = 40
	while start < end:
		var stop: int = mini(start + _STRIDE, end)
		value = _update(value, container, start, stop)
		start = stop
	return _finish(value)

static func _finish(value: int) -> int:
	return (value ^ 0xFFFFFFFF) & 0xFFFFFFFF

static func _update(crc: int, bytes: PackedByteArray, start: int, end: int) -> int:
	var value: int = crc & 0xFFFFFFFF
	for index in range(start, end):
		value = (value ^ bytes[index]) & 0xFFFFFFFF
		for _bit in 8:
			if (value & 1) != 0:
				value = (value >> 1) ^ 0xEDB88320
			else:
				value = value >> 1
			value = value & 0xFFFFFFFF
	return value
