#!/usr/bin/env bash
# run-codex-review.sh — AI code review wrapper
# Supports OpenAI Codex (codex) and Claude Code (claude).
#
# Usage:
#   run-codex-review.sh [--files path1,path2,...] [-- ...extra codex args]
#
# --files  Comma-separated list of paths to scope the review to.
#          Without --files, reviews all uncommitted changes.
#
# Backend selection (first match wins):
#   1. CODEX_REVIEW_BIN  — explicit binary path (any name)
#   2. CODEX_REVIEW_BACKEND=claude|codex — pick backend by name
#   3. Auto-detect from PATH (default: codex)
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

# ── 0. Parse --files argument ──

review_files=""
pass_through_args=()
while [ $# -gt 0 ]; do
    case "$1" in
        --files)
            if [ $# -lt 2 ]; then
                echo "[run-codex-review] ERROR: --files requires a comma-separated list of paths"
                exit 1
            fi
            review_files="$2"
            shift 2
            ;;
        *)
            pass_through_args+=("$1")
            shift
            ;;
    esac
done
set -- "${pass_through_args[@]+"${pass_through_args[@]}"}"

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

    # Check for uncommitted changes (scoped or full)
    has_changes=0
    if [ -n "$review_files" ]; then
        # Convert comma-separated list to space-separated for iteration
        IFS=',' read -ra file_array <<< "$review_files"
        for f in "${file_array[@]}"; do
            if ! git diff --cached --quiet -- "$f" 2>/dev/null; then has_changes=1; break; fi
            if ! git diff --quiet -- "$f" 2>/dev/null; then has_changes=1; break; fi
        done
    else
        if ! git diff --cached --quiet 2>/dev/null; then has_changes=1; fi
        if ! git diff --quiet 2>/dev/null; then has_changes=1; fi
    fi

    if [ "$has_changes" -eq 0 ]; then
        echo "[claude-review] No uncommitted changes to review."
        exit 0
    fi

    # Build scoped-file hint line
    files_hint=""
    if [ -n "$review_files" ]; then
        files_hint="

Only review changes in the following files: $review_files"
    fi

    # Run Claude Code in non-interactive mode
    # Claude automatically loads CLAUDE.md and project context
    "$review_bin" -p "$(cat <<PROMPT
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
Do NOT modify any files — this is a read-only review.${files_hint}
PROMPT
)" 2>&1

else
    echo "[run-codex-review] Using Codex for review ($review_bin)"

    if [ -n "$review_files" ]; then
        # Codex review --uncommitted does not support file scoping.
        # Use prompt-based approach: generate scoped diff and feed it.
        IFS=',' read -ra file_array <<< "$review_files"

        scoped_diff="$(git diff --cached -- "${file_array[@]}" 2>/dev/null; git diff -- "${file_array[@]}" 2>/dev/null)" || true

        if [ -z "$scoped_diff" ]; then
            echo "[codex-review] No uncommitted changes in specified files."
            exit 0
        fi

        "$review_bin" -p "$(cat <<PROMPT
You are a senior Solidity code reviewer performing an AI-assisted review.

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

Review the following diff (files: $review_files):

\`\`\`diff
$scoped_diff
\`\`\`
PROMPT
)" 2>&1
    else
        "$review_bin" review --uncommitted "$@"
    fi
fi
