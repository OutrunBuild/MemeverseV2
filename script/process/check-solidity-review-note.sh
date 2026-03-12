#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

find_latest_review_note() {
    local review_dir
    review_dir="$(node ./script/process/read-process-config.js policy quality_gate.review_note_directory)"

    if [ ! -d "$review_dir" ]; then
        return 1
    fi

    find "$review_dir" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' ! -name 'TEMPLATE.md' -printf '%T@ %p\n' \
        | sort -nr \
        | head -n 1 \
        | cut -d' ' -f2-
}

review_note="${QUALITY_GATE_REVIEW_NOTE:-}"

if [ -z "$review_note" ]; then
    review_note="$(find_latest_review_note || true)"
fi

if [ -z "$review_note" ] || [ ! -f "$review_note" ]; then
    echo "[check-solidity-review-note] ERROR: review note not found. Set QUALITY_GATE_REVIEW_NOTE or add one under the configured review note directory."
    exit 1
fi

bash ./script/process/check-review-note.sh "$review_note"
