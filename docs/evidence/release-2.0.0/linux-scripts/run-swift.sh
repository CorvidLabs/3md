#!/bin/bash
set -u
echo "== uname"; uname -a
echo "== os"; cat /etc/os-release | head -3
echo "== versions"; swift --version
cd /work
echo "== swift build"; swift build; echo "EXIT swift-build=$?"
echo "== swift test"; swift test; echo "EXIT swift-test=$?"
