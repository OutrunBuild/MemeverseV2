#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_file_list="$(mktemp)"
empty_tree="$(git hash-object -t tree /dev/null)"

cleanup() {
    rm -f "$tmp_file_list"
}
trap cleanup EXIT

append_diff_range() {
    local base_sha="$1"
    local head_sha="$2"

    if [ -z "$head_sha" ] || [ "$head_sha" = "0000000000000000000000000000000000000000" ]; then
        return 0
    fi

    if ! git cat-file -e "${head_sha}^{commit}" >/dev/null 2>&1; then
        return 0
    fi

    if [ -z "$base_sha" ] || [ "$base_sha" = "0000000000000000000000000000000000000000" ]; then
        git diff --name-only "$empty_tree" "$head_sha" >> "$tmp_file_list"
        return 0
    fi

    if git cat-file -e "${base_sha}^{commit}" >/dev/null 2>&1; then
        git diff --name-only "$base_sha" "$head_sha" >> "$tmp_file_list"
        return 0
    fi

    git diff --name-only "$empty_tree" "$head_sha" >> "$tmp_file_list"
}

if [ -n "${PRE_PUSH_FILE_LIST_OVERRIDE:-}" ]; then
    if [ ! -f "${PRE_PUSH_FILE_LIST_OVERRIDE}" ]; then
        echo "[run-pre-push-quality-gate] ERROR: PRE_PUSH_FILE_LIST_OVERRIDE does not exist: ${PRE_PUSH_FILE_LIST_OVERRIDE}"
        exit 1
    fi
    cat "${PRE_PUSH_FILE_LIST_OVERRIDE}" > "$tmp_file_list"
else
    saw_ref_update=0
    while read -r local_ref local_sha remote_ref remote_sha; do
        [ -z "${local_ref}${local_sha}${remote_ref}${remote_sha}" ] && continue
        saw_ref_update=1
        append_diff_range "$remote_sha" "$local_sha"
    done

    if [ "$saw_ref_update" -eq 0 ]; then
        if git rev-parse --verify '@{upstream}' >/dev/null 2>&1; then
            git diff --name-only '@{upstream}...HEAD' > "$tmp_file_list"
        elif git rev-parse --verify HEAD~1 >/dev/null 2>&1; then
            git diff --name-only HEAD~1..HEAD > "$tmp_file_list"
        else
            git ls-files > "$tmp_file_list"
        fi
    fi
fi

sort -u "$tmp_file_list" -o "$tmp_file_list"

if ! grep -q '[^[:space:]]' "$tmp_file_list"; then
    echo "[run-pre-push-quality-gate] no files to check, skipping."
    exit 0
fi

echo "[run-pre-push-quality-gate] running quality gate for the push diff..."
QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$tmp_file_list" npm run quality:gate
