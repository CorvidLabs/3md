extends SceneTree

const Unicode = preload("res://addons/threemd/nfc.gd")

func _init() -> void:
	var cafe: String = Unicode.nfc("e" + String.chr(0x0301))
	if cafe != String.chr(0x00E9):
		print("FAIL cafe ", cafe.unicode_at(0))
		quit(1)
		return
	if Unicode.nfc(String.chr(0x212B)) != String.chr(0x00C5):
		print("FAIL angstrom")
		quit(1)
		return
	var path: String = ProjectSettings.globalize_path("res://").path_join("tests/nfc_vectors.bin")
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		print("FAIL open vectors")
		quit(1)
		return
	var offset: int = 0
	var count: int = bytes.decode_u32(offset)
	offset += 4
	var mismatches: int = 0
	for _index in count:
		var input := ""
		var input_count: int = bytes.decode_u32(offset)
		offset += 4
		for _part in input_count:
			input += String.chr(bytes.decode_u32(offset))
			offset += 4
		var expected := ""
		var output_count: int = bytes.decode_u32(offset)
		offset += 4
		for _part in output_count:
			expected += String.chr(bytes.decode_u32(offset))
			offset += 4
		var got: String = Unicode.nfc(input)
		if got != expected:
			mismatches += 1
			if mismatches <= 8:
				print("FAIL nfc ", input, " got ", got, " expected ", expected)
	print("NFC ", count, " MISMATCH ", mismatches)
	quit(0 if mismatches == 0 else 2)
