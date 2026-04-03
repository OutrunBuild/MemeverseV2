#!/usr/bin/env bash
# run-codex-review.sh — AI code review wrapper
# Supports OpenAI Codex (codex) and Claude Code (claude).
#
# Backend selection (first match wins):
#   1. CODEX_REVIEW_BIN  — explicit binary path (any name)
#   2. CODEX_REVIEW_BACKEND=claude|codex — pick backend by name
#   3. Auto-detect from PATH (default: codex)
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

# ── 1. Determine backend ──

override_bin="${CODEX_REVIEW_BIN:-}"
if [ -n "$override_bin" ]; then
    # Hard override: detect mode from binary name
    case "$(basename "$override_bin")" in
        claude*) review_mode="claude" ;;
        *)       review_mode="codex" ;;
    esac
    review_bin="$override_bin"
else
    # Backend selector: default to codex for backward compatibility
    review_backend="${CODEX_REVIEW_BACKEND:-codex}"
    case "$review_backend" in
        claude)
            if ! command -v claude >/dev/null 2>&1; then
                echo "[run-codex-review] ERROR: CODEX_REVIEW_BACKEND=claude but 'claude' not found on PATH"
                exit 1
            fi
            review_mode="claude"
            review_bin="claude"
            ;;
        codex)
            if ! command -v codex >/dev/null 2>&1; then
                echo "[run-codex-review] ERROR: 'codex' not found on PATH"
                echo "[run-codex-review] Hint: set CODEX_REVIEW_BACKEND=claude or install codex"
                exit 1
            fi
            review_mode="codex"
            review_bin="codex"
            ;;
        *)
            echo "[run-codex-review] ERROR: unknown CODEX_REVIEW_BACKEND=$review_backend (expected: claude|codex)"
            exit 1
            ;;
    esac
fi

# ── 2. Run review ──

if [ "$review_mode" = "claude" ]; then
    echo "[run-codex-review] Using Claude Code for review ($review_bin)"

    # Check for uncommitted changes
    has_changes=0
    if ! git diff --cached --quiet 2>/dev/null; then has_changes=1; fi
    if ! git diff --quiet 2>/dev/null; then has_changes=1; fi

    if [ "$has_changes" -eq 0 ]; then
        echo "[claude-review] No uncommitted changes to review."
        exit 0
    fi

    # Run Claude Code in non-interactive mode
    # Claude automatically loads CLAUDE.md and project context
    "$review_bin" -p "$(cat <<'PROMPT'
You are a senior Solidity code reviewer performing an AI-assisted review of uncommitted changes.

Focus on:
1. **Correctness**: logic errors, state transition bugs, edge cases, accounting errors
2. **Security**: reentrancy, access control, integer overflow, external call risks, trust boundaries
3. **Gas**: hot-path optimization opportunities
4. **Code quality**: NatSpec completeness, naming conventions, structural clarity

For each finding:
- Classify severity as **high** / **medium** / **low** / **info**
- Reference the specific file and function
- Explain the issue and suggest a fix

End with an overall assessment and list of residual risks.

Examine the uncommitted changes using Read, Grep, Glob, and Bash(git diff *) tools.
Do NOT modify any files — this is a read-only review.
PROMPT
)" 2>&1

else
    echo "[run-codex-review] Using Codex for review ($review_bin)"
    "$review_bin" review --uncommitted "$@"
fi
