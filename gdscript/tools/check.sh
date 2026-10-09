#!/bin/bash
# Headless Godot checks for the ThreeMD addon.
# GODOT overrides the binary. The addon stays on Godot 4.7.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
godot="${GODOT:-godot}"
version="$("$godot" --version)"
case "$version" in
	4.7.*) ;;
	*)
		echo "Godot $version is not 4.7.x. Refusing Godot 3 and Godot 4.8." >&2
		exit 1
		;;
esac

project="$root/gdscript"

# A --script check does not import, and it cannot see class_name until an
# editor scan has written the global script class cache. Import first with
# the ThreeMD plugin enabled, write a kind-2 .3mdb with this addon, import
# again so that file becomes a ThreeMDDocumentAsset, then load() both paths.
echo "== import"
"$godot" --headless --path "$project" --import

echo "== res://examples/write_grove_kind2.gd"
"$godot" --headless --path "$project" --script res://examples/write_grove_kind2.gd

echo "== import kind 2"
"$godot" --headless --path "$project" --import

echo "== res://examples/load_imported.gd"
"$godot" --headless --path "$project" --script res://examples/load_imported.gd

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
	"$godot" --headless --path "$project" --script "$script"
done
