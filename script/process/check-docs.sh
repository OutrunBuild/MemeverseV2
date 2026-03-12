#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

bash ./script/process/generate-docs.sh

if [ -d "docs/contracts/src" ]; then
    echo "Unexpected nested docs directory: docs/contracts/src"
    exit 1
fi

if [ ! -d "docs/contracts/common" ]; then
    echo "Expected docs directory missing: docs/contracts/common"
    exit 1
fi

if [ ! -f "docs/contracts/SUMMARY.md" ]; then
    echo "Expected docs summary missing: docs/contracts/SUMMARY.md"
    exit 1
fi
