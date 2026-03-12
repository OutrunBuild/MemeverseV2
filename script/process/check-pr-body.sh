#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <pr-body-file>"
    exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

body_file="$1"

if [ ! -f "$body_file" ]; then
    echo "[check-pr-body] ERROR: PR body file not found: $body_file"
    exit 1
fi

mapfile -t required_sections < <(node ./script/process/read-process-config.js policy pull_request.required_sections --lines)

missing_sections=()

for section in "${required_sections[@]}"; do
    if ! grep -qF "$section" "$body_file"; then
        missing_sections+=("$section")
    fi
done

if [ "${#missing_sections[@]}" -gt 0 ]; then
    echo "[check-pr-body] ERROR: PR body is missing required sections:"
    printf '%s\n' "${missing_sections[@]}"
    exit 1
fi
