#!/usr/bin/env bash
# Run from the repository root. This gate never writes lifecycle state.
set -euo pipefail
engine="${SPECSYNC_BIN:-specsync}"
test "$("$engine" --version)" = 'specsync 6.1.1' || { echo 'lifecycle: expected specsync 6.1.1' >&2; exit 1; }
python3 - <<'PY'
import json
from pathlib import Path
p=json.loads(Path('.specsync/sdd.json').read_text())
for flag in ('enabled','require_change_for_meaningful_files'):
    if p.get(flag) is not True: raise SystemExit('lifecycle: required policy disabled: '+flag)
required=('src/ tests/ site/ .github/ Cargo.toml Cargo.lock action.yml package.json bun.lock package-lock.json pnpm-lock.yaml yarn.lock Package.swift Package.resolved go.mod go.sum pyproject.toml uv.lock requirements.txt .specsync/sdd.json .specsync/config.toml .specsync/config.json .specsync/version Sources/ Tests/ Examples/ conformance/ editor/ element/ js/ rust/ uitests/ web/ scripts/ README.md ROADMAP.md CHANGELOG.md SECURITY.md CONTRIBUTING.md docs/ docs.3md specs/ SPEC.md fledge.toml .trust.toml .augur.toml .attest.json AGENTS.md CLAUDE.md .claude/ .codex/ .cursor/ .gemini/ gdscript/ apps/sculpt/ .agents/').split()
missing=set(required)-set(p.get('meaningful_paths',[]))
if missing: raise SystemExit('lifecycle: missing meaningful paths: '+', '.join(sorted(missing)))
# This repository has no exclusions. Refuse masking future coverage with one.
if p.get('ignored_paths') != []: raise SystemExit('lifecycle: unexpected ignored paths')
PY
"$engine" change audit --strict
python3 - <<'PY'
from pathlib import Path
active=Path('.specsync/changes')
remaining=sorted(str(p) for p in active.iterdir() if p.is_dir()) if active.exists() else []
if remaining: raise SystemExit('lifecycle: unfinished active workspaces: '+', '.join(remaining))
print('lifecycle: exact engine, required coverage, strict audit and archive gate passed')
PY
