#!/bin/bash
# Runs the Godot interchange adapter. Protocol lines stay in the output file so
# the engine banner never enters the transcript.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
godot="${THREEMD_GODOT:-${GODOT:-godot}}"
input="$(mktemp)"
output="$(mktemp)"
errors="$(mktemp)"
trap 'rm -f "$input" "$output" "$errors"' EXIT
cat > "$input"
if ! "$godot" --headless --path "$root/gdscript" --script res://tools/interchange_adapter.gd -- "$input" "$output" >/dev/null 2>"$errors"; then
	cat "$errors" >&2
	exit 1
fi
if grep -q "SCRIPT ERROR" "$errors"; then
	cat "$errors" >&2
	exit 1
fi
cat "$output"
