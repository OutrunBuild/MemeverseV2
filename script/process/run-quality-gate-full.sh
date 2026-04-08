#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_file_list="$(mktemp)"
trap 'rm -f "$tmp_file_list"' EXIT

git ls-files > "$tmp_file_list"

QUALITY_GATE_MODE=ci \
QUALITY_GATE_FILE_LIST="$tmp_file_list" \
QUALITY_GATE_FAST=0 \
QUALITY_GATE_ERRORS_ONLY=1 \
QUALITY_GATE_HIDE_PASS=1 \
FORGE_TEST_VERBOSITY="${FORGE_TEST_VERBOSITY:--vv}" \
bash ./script/process/quality-gate.sh
