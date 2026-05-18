#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

zero_sha="0000000000000000000000000000000000000000"
event_name="${HARNESS_EVENT_NAME:-${GITHUB_EVENT_NAME:-}}"
base_sha="${HARNESS_EVENT_BASE_SHA:-}"
head_sha="${HARNESS_EVENT_HEAD_SHA:-${GITHUB_SHA:-HEAD}}"
runner_temp="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"

if [ -z "$event_name" ]; then
    echo "HARNESS_EVENT_NAME or GITHUB_EVENT_NAME is required" >&2
    exit 1
fi

if [ "$event_name" = "workflow_dispatch" ] || [ -z "$base_sha" ] || [ "$base_sha" = "$zero_sha" ]; then
    npm run gate:ci -- --all
    exit 0
fi

mkdir -p "$runner_temp"
changed_files_output="$(mktemp "$runner_temp/changed-files.XXXXXX")"
diff_output="$(mktemp "$runner_temp/changed-files.XXXXXX.diff")"
trap 'rm -f "$changed_files_output" "$diff_output"' EXIT

git diff --name-only "$base_sha" "$head_sha" >"$changed_files_output"
git diff --unified=0 "$base_sha" "$head_sha" >"$diff_output"

CHANGE_CLASSIFIER_DIFF_FILE="$diff_output" npm run gate:ci -- --changed-files "$changed_files_output"
