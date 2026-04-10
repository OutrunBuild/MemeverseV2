#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

changed_files_tmp="$(mktemp)"
trap 'rm -f "$changed_files_tmp"' EXIT

{
    git diff --cached --name-only --diff-filter=ACMRD
    git diff --name-only --diff-filter=ACMRD
    git ls-files --others --exclude-standard
} | awk 'NF && !seen[$0]++' > "$changed_files_tmp"

QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_tmp" \
    bash ./script/process/check-spec-reviewer-report.sh
