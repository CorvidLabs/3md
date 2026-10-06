#!/bin/bash
# Usage: cases.sh <threemd binary> <fixtures dir>. Prints one block per case: stdout, stderr, exit code.
B="$1"; F="$2"
run() { label="$1"; shift
  out=$(mktemp); err=$(mktemp)
  "$@" >"$out" 2>"$err" </dev/null; rc=$?
  echo "### $label exit=$rc"; echo "--- stdout"; cat "$out"; echo "--- stderr"; cat "$err"; rm -f "$out" "$err"; }
run "no-args" "$B"
run "help" "$B" help
run "unknown" "$B" bogus
for sub in validate info links check-links html; do
  run "$sub valid" "$B" $sub "$F/valid.3md"
  run "$sub missing" "$B" $sub "$F/missing.3md"
  run "$sub invalid" "$B" $sub "$F/invalid.3md"
  run "$sub dangling" "$B" $sub "$F/dangling.3md"
done
for sub in validate info links check-links; do
  run "$sub --json missing" "$B" $sub --json "$F/missing.3md"
  run "$sub --json invalid" "$B" $sub --json "$F/invalid.3md"
done
run "validate no file" "$B" validate
run "stdin valid" bash -c "\"$B\" validate - < \"$F/valid.3md\""
# Standard error unavailable: exit codes must be preserved.
for args in "bogus" "validate $F/missing.3md" "check-links $F/dangling.3md" "validate $F/invalid.3md"; do
  bash -c "\"$B\" $args >/dev/null 2>&-"; echo "### closed-stderr [$args] exit=$?"
done
bash -c "trap '' PIPE; \"$B\" check-links \"$F/dangling.3md\" 2>&1 | (exec 0<&-; sleep 0.3)"; echo "### broken-pipe-sigpipe-ignored check-links exit(pipe last)=$?"
bash -c "trap '' PIPE; set -o pipefail; \"$B\" check-links \"$F/dangling.3md\" 2>&1 | (exec 0<&-; sleep 0.3)"; echo "### broken-pipe-sigpipe-ignored check-links pipefail exit=$?"
