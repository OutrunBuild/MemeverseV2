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

if ! grep -Fq "QUALITY_GATE_REVIEW_NOTE" "$workflow_file"; then
    echo "Expected CI workflow to provide QUALITY_GATE_REVIEW_NOTE"
    exit 1
fi

review_note_file="docs/reviews/CI_REVIEW_NOTE.md"

if [ ! -f "$review_note_file" ]; then
    echo "Expected tracked CI review note at $review_note_file"
    exit 1
fi

bash ./script/process/check-review-note.sh "$review_note_file"
