#!/bin/bash
# Headless Godot checks for the ThreeMD addon. Godot 4 must be on PATH.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
godot="${GODOT:-godot}"
scripts=(
	res://tests/number_check.gd
	res://tests/nfc_check.gd
	res://tests/text_check.gd
	res://tests/binary_check.gd
	res://tests/composition_check.gd
	res://tests/file_check.gd
	res://tests/edit_check.gd
	res://examples/play_layers.gd
	res://examples/showcase.gd
)

for script in "${scripts[@]}"; do
	echo "== $script"
	"$godot" --headless --path "$root/gdscript" --script "$script"
done
