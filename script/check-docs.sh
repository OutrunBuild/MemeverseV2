#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

forge doc

git diff --exit-code -- docs/src

if [ -n "$(git ls-files --others --exclude-standard -- docs/src)" ]; then
    echo "Generated docs under docs/src are not fully tracked."
    git ls-files --others --exclude-standard -- docs/src
    exit 1
fi
