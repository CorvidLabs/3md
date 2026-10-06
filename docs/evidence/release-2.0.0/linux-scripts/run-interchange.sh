#!/bin/bash
set -u
echo "== uname"; uname -a
echo "== os"; grep PRETTY /etc/os-release
echo "== versions"; swift --version; node --version; bun --version; rustc --version; cargo --version
cd /work/js
echo "== bun install --frozen-lockfile"; bun install --frozen-lockfile; echo "EXIT bun-install=$?"
echo "== bun run build"; bun run build; echo "EXIT js-build=$?"
cd /work/rust
echo "== cargo build --example interchange --locked"; cargo build --example interchange --locked; echo "EXIT cargo-build-example=$?"
ls -la target/debug/examples/interchange; file target/debug/examples/interchange 2>/dev/null || true
cd /work
echo "== swift run threemd-interchange"
start=$(date +%s.%N)
swift run threemd-interchange > /out/interchange-stdout.txt 2> /out/interchange-stderr.txt; rc=$?
end=$(date +%s.%N)
echo "EXIT swift-run-threemd-interchange=$rc"
echo "elapsed_seconds=$(echo "$end - $start" | bc 2>/dev/null || python3 -c "print($end-$start)")"
tail -n 20 /out/interchange-stderr.txt
cat /out/interchange-stdout.txt
evidence=$(sed -n 's/^Interchange evidence: //p' /out/interchange-stdout.txt)
if [ -n "$evidence" ] && [ -d "$evidence" ]; then cp -R "$evidence" /out/evidence-dir; ls /out/evidence-dir | head; fi
