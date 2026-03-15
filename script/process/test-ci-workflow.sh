#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

workflow_file=".github/workflows/test.yml"

if ! grep -Fq "actions/setup-python@v5" "$workflow_file"; then
    echo "Expected CI workflow to set up Python before installing slither"
    exit 1
fi

if ! grep -Fq "slither-analyzer" "$workflow_file"; then
    echo "Expected CI workflow to install slither-analyzer"
    exit 1
fi

if ! grep -Fq 'echo "$HOME/.local/bin" >> "$GITHUB_PATH"' "$workflow_file"; then
    echo "Expected CI workflow to expose user-installed Python binaries on PATH"
    exit 1
fi

if ! grep -Fq "slither --version" "$workflow_file"; then
    echo "Expected CI workflow to verify the slither installation"
    exit 1
fi
