#!/usr/bin/env bash
# Disposable fixture checks use the real engine, without inventing review/approval.
set -euo pipefail
engine="${SPECSYNC_BIN:-specsync}"
engine="$(command -v "$engine")"
repo="$(pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export SPECSYNC_BIN="$engine"
git -C "$tmp" init -q
"$engine" init --root "$tmp" >/dev/null
cp .specsync/sdd.json "$tmp/.specsync/sdd.json"
git -C "$tmp" add .
git -C "$tmp" -c user.name=fixture -c user.email=fixture@example.invalid commit -qm 'Empty fixture, no human approval claims'
cd "$tmp"
check() { bash "$repo/scripts/check-specsync-lifecycle.sh" >"$tmp/result" 2>&1; }
fail_for() {
  if check; then echo "unexpected pass: $1" >&2; exit 1; fi
  grep -F "$1" "$tmp/result" >/dev/null || { cat "$tmp/result"; exit 1; }
  echo "PASS negative: $1"
}
check || { cat "$tmp/result"; exit 1; }
echo 'PASS clean fixture (no active change or fabricated acceptance)'
cat > "$tmp/wrong-engine" <<'STUB'
#!/bin/sh
printf 'specsync 6.1.0\n'
STUB
chmod +x "$tmp/wrong-engine"
SPECSYNC_BIN="$tmp/wrong-engine" fail_for 'expected specsync 6.1.1'
for flag in enabled require_change_for_meaningful_files; do
  cp "$repo/.specsync/sdd.json" .specsync/sdd.json
  python3 - "$flag" <<'PY'
import json,sys
p='.specsync/sdd.json'; d=json.load(open(p)); d[sys.argv[1]]=False; open(p,'w').write(json.dumps(d))
PY
  fail_for "required policy disabled: $flag"
done
for path in Sources/ Tests/ AGENTS.md gdscript/ apps/sculpt/ .agents/; do
  cp "$repo/.specsync/sdd.json" .specsync/sdd.json
  python3 - "$path" <<'PY'
import json,sys
p='.specsync/sdd.json'; d=json.load(open(p)); d['meaningful_paths'].remove(sys.argv[1]); open(p,'w').write(json.dumps(d))
PY
  fail_for "missing meaningful paths: $path"
done
cp "$repo/.specsync/sdd.json" .specsync/sdd.json
mkdir -p .specsync/changes/unfinished
# An empty orphan directory must also be rejected even when native audit ignores it.
fail_for 'unfinished active workspaces:'
rmdir .specsync/changes/unfinished
mkdir -p .specsync/archive
printf 'Fixture history placeholder; no approval or review asserted.\n' > .specsync/archive/fixture-note.md
check || { cat "$tmp/result"; exit 1; }
echo 'PASS archive-only fixture; authentic review/finalize remain manual'

# Native audit must independently reject an unapproved meaningful change.
"$engine" change new "Fixture unfinished operation" --kind operations --path scripts/ --no-spec-change --rationale "Disposable negative control" --json > "$tmp/new.json"
mkdir -p scripts
printf '# fixture source change\n' > scripts/fixture.sh
if check; then echo 'unexpected native audit pass' >&2; exit 1; fi
grep -E 'incomplete|not covered|unapproved' "$tmp/result" >/dev/null || { cat "$tmp/result"; exit 1; }
echo 'PASS native audit: unapproved meaningful change'
