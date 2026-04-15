#!/usr/bin/env bash
set -euo pipefail

input="$(cat || true)"
file_path="$(printf '%s' "$input" | jq -r '.file_path // empty' 2>/dev/null || true)"

if [ -z "$file_path" ]; then
    exit 0
fi

repo_root=""
dir="$(cd "$(dirname "$file_path")" 2>/dev/null && pwd 2>/dev/null || echo "/")"
while [ "$dir" != "/" ]; do
    if [ -f "$dir/.harness/policy.json" ]; then
        repo_root="$dir"
        break
    fi
    dir="$(dirname "$dir")"
done

if [ -z "$repo_root" ]; then
    exit 0
fi

echo "[harness] This repo has .harness/policy.json. You MUST follow the Harness Dispatch Procedure: classify via policy.json -> dispatch subagent -> review -> verify. Do NOT edit files directly in the main session."
exit 0
