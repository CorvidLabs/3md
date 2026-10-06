#!/bin/bash
set -u
echo "== uname"; uname -a
echo "== os"; cat /etc/os-release | head -3
echo "== versions"; rustc --version; cargo --version
cd /work/rust
echo "== cargo test --all-targets --locked"
cargo test --all-targets --locked; echo "EXIT cargo-test-all-targets=$?"
echo "== cargo test --doc --locked"
cargo test --doc --locked; echo "EXIT cargo-test-doc=$?"
