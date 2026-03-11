#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

staged_files="$(git diff --cached --name-only --diff-filter=ACMR)"

if [ -z "$staged_files" ]; then
    echo "[quality-gate] no staged files, skipping."
    exit 0
fi

has_src_sol=0
has_sol_tests=0

if echo "$staged_files" | grep -Eq '^src/.*\.sol$'; then
    has_src_sol=1
fi

if echo "$staged_files" | grep -Eq '^test/.*\.t\.sol$'; then
    has_sol_tests=1
fi

if [ "$has_src_sol" -eq 1 ]; then
    review_files="$(echo "$staged_files" | grep -E '^docs/reviews/.*\.md$' || true)"
    if [ -z "$review_files" ]; then
        echo "[quality-gate] ERROR: staged src Solidity changes require a staged review note under docs/reviews/*.md"
        echo "[quality-gate] Use docs/reviews/TEMPLATE.md and include findings, simplification, verification, and decision."
        exit 1
    fi

    required_sections=(
        "## Scope"
        "## Findings"
        "## Simplification"
        "## Verification"
        "## Decision"
    )

    while IFS= read -r review_file; do
        [ -z "$review_file" ] && continue
        for section in "${required_sections[@]}"; do
            if ! grep -qF "$section" "$review_file"; then
                echo "[quality-gate] ERROR: $review_file is missing required section: $section"
                exit 1
            fi
        done
    done <<< "$review_files"
fi

if [ "$has_src_sol" -eq 1 ] || [ "$has_sol_tests" -eq 1 ]; then
    echo "[quality-gate] forge fmt --check"
    forge fmt --check

    echo "[quality-gate] forge build --sizes"
    forge build --sizes

    echo "[quality-gate] forge test -vvv"
    forge test -vvv
fi

if [ "$has_src_sol" -eq 1 ]; then
    echo "[quality-gate] npm run docs:gen"
    npm run docs:gen
    git add docs/src
fi

echo "[quality-gate] PASS"
