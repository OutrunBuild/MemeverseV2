#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

codex_bin="${CODEX_REVIEW_BIN:-codex}"

if ! command -v "$codex_bin" >/dev/null 2>&1; then
    echo "[run-codex-review] ERROR: codex binary not found: $codex_bin"
    exit 1
fi

"$codex_bin" review --uncommitted "$@"
