#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

codex_bin="${CODEX_REVIEW_BIN:-codex}"
prompt="${CODEX_REVIEW_PROMPT:-Review the current uncommitted changes after the writer and specialist review pass. Focus on logic bugs, missed edge cases, unsafe assumptions, state/accounting mistakes, authorization issues, gas improvement opportunities, and simplification candidates. Return findings first; if there are no findings, state that explicitly.}"

if ! command -v "$codex_bin" >/dev/null 2>&1; then
    echo "[run-codex-review] ERROR: codex binary not found: $codex_bin"
    exit 1
fi

if [ -n "${prompt}" ]; then
    echo "[run-codex-review] INFO: current codex CLI rejects --uncommitted with a positional prompt; CODEX_REVIEW_PROMPT is ignored." >&2
fi

"$codex_bin" review --uncommitted "$@"
