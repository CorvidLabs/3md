extends SceneTree

const Numbers = preload("res://addons/threemd/number.gd")
const BigScript = preload("res://addons/threemd/big.gd")

func fail(message: String) -> void:
	print("FAIL ", message)
	quit(1)

func check(condition: bool, message: String) -> void:
	if not condition:
		fail(message)

func _init() -> void:
	var hundred: ThreeMDBig = BigScript.from_int(100)
	var split: Array = hundred.divmod(BigScript.from_int(7))
	check(split[0].decimal() == "14", "quot " + split[0].decimal())
	check(split[1].decimal() == "2", "rem " + split[1].decimal())
	var power: ThreeMDBig = BigScript.from_int(1)
	for _index in 20:
		power = power.mul_small(10)
	check(power.decimal() == "1" + "0".repeat(20), "pow10 " + power.decimal())
	check(str(Numbers.parse_finite("0.5")) == "0.5", "parse 0.5")
	check(Numbers.canonical(0.5) == "0.5", "canon 0.5 got " + Numbers.canonical(0.5))
	check(Numbers.canonical(1.0) == "1", "canon 1 got " + Numbers.canonical(1.0))
	check(Numbers.canonical(0.1) == "0.1", "canon 0.1 got " + Numbers.canonical(0.1))
	var negative_zero: float = Numbers.parse_finite("-0")
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, negative_zero)
	check(bytes.hex_encode() == "0000000000000080", "neg0 " + bytes.hex_encode())
	check(Numbers.canonical(negative_zero) == "0", "canon -0")
	var tiny: float = Numbers.parse_finite("5e-324")
	check(Numbers.canonical(tiny) == "5e-324", "canon tiny " + Numbers.canonical(tiny))
	print("SMOKE_OK")
	var path: String = ProjectSettings.globalize_path("res://").path_join("../conformance/extensions/numeric-powers.json")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		fail("open " + path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	var data: Dictionary = parsed
	var vectors: Array = data["vectors"]
	var mismatches: int = 0
	var shown: int = 0
	for item in vectors:
		var vector: Dictionary = item
		var spelling: String = vector["formatted"]
		var value: Variant = Numbers.parse_finite(spelling)
		if value == null:
			mismatches += 1
			if shown < 8:
				print("PARSE ", vector["name"], " ", spelling)
				shown += 1
			continue
		var got: String = Numbers.canonical(value)
		if got != spelling:
			mismatches += 1
			if shown < 8:
				print("FORMAT ", vector["name"], " expected ", spelling, " got ", got)
				shown += 1
	print("TOTAL ", vectors.size(), " MISMATCH ", mismatches)
	quit(0 if mismatches == 0 else 2)
