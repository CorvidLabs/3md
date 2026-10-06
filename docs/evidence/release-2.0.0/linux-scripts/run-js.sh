#!/bin/bash
set -u
echo "== uname"; uname -a
echo "== os"; cat /etc/os-release | head -3
echo "== versions"; bun --version; node --version 2>/dev/null || echo "node: not present"
cd /work/js
echo "== bun install --frozen-lockfile"; bun install --frozen-lockfile; echo "EXIT bun-install=$?"
echo "== tsc version"; ./node_modules/.bin/tsc --version
echo "== bun run typecheck"; bun run typecheck; echo "EXIT typecheck=$?"
echo "== bun run build"; bun run build; echo "EXIT build=$?"
ls -la dist | head -20
echo "== bun test"; bun test; echo "EXIT bun-test=$?"
