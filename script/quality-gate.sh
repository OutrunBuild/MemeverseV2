#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

mode="${QUALITY_GATE_MODE:-staged}"
generated_docs_dir="docs/contracts"

load_file_list_from_ci() {
    if [ -n "${QUALITY_GATE_FILE_LIST:-}" ] && [ -f "${QUALITY_GATE_FILE_LIST}" ]; then
        cat "${QUALITY_GATE_FILE_LIST}"
        return
    fi

    if [ -n "${GITHUB_BASE_REF:-}" ]; then
        if ! git rev-parse --verify "origin/${GITHUB_BASE_REF}" >/dev/null 2>&1; then
            git fetch --no-tags --prune origin "${GITHUB_BASE_REF}:${GITHUB_BASE_REF}"
            git branch --set-upstream-to "origin/${GITHUB_BASE_REF}" "${GITHUB_BASE_REF}" >/dev/null 2>&1 || true
        fi
        git diff --name-only "origin/${GITHUB_BASE_REF}...HEAD"
        return
    fi

    if git rev-parse --verify HEAD~1 >/dev/null 2>&1; then
        git diff --name-only HEAD~1..HEAD
        return
    fi

    git ls-files
}

if [ "$mode" = "ci" ]; then
    changed_files="$(load_file_list_from_ci)"
else
    changed_files="$(git diff --cached --name-only --diff-filter=ACMR)"
fi

if [ -z "$changed_files" ]; then
    echo "[quality-gate] no files to check, skipping."
    exit 0
fi

has_src_sol=0
has_sol_tests=0
solidity_candidates=()
solidity_files=()
shell_candidates=()
shell_files=()

while IFS= read -r file; do
    [ -z "$file" ] && continue

    if [[ "$file" =~ ^src/.*\.sol$ ]]; then
        has_src_sol=1
        solidity_candidates+=("$file")
    elif [[ "$file" =~ ^test/.*\.t\.sol$ ]]; then
        has_sol_tests=1
        solidity_candidates+=("$file")
    elif [[ "$file" =~ ^test/.*\.sol$ ]]; then
        solidity_candidates+=("$file")
    fi

    if [[ "$file" =~ ^(script/.*\.sh|\.githooks/.*)$ ]]; then
        shell_candidates+=("$file")
    fi
done <<< "$changed_files"

for file in "${solidity_candidates[@]}"; do
    if [ -f "$file" ]; then
        solidity_files+=("$file")
    fi
done

for file in "${shell_candidates[@]}"; do
    if [ -f "$file" ]; then
        shell_files+=("$file")
    fi
done

if [ "$has_src_sol" -eq 1 ]; then
    review_files="$(echo "$changed_files" | grep -E '^docs/reviews/.*\.md$' || true)"
    if [ -z "$review_files" ]; then
        echo "[quality-gate] ERROR: src Solidity changes require a review note under docs/reviews/*.md in this change set"
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
    if [ "${#solidity_files[@]}" -gt 0 ]; then
        echo "[quality-gate] forge fmt --check (changed Solidity files only)"
        forge fmt --check "${solidity_files[@]}"
    fi

    echo "[quality-gate] forge build"
    forge build

    echo "[quality-gate] forge test -vvv"
    forge test -vvv
fi

if [ "${#shell_files[@]}" -gt 0 ]; then
    echo "[quality-gate] bash -n (changed shell scripts)"
    bash -n "${shell_files[@]}"
fi

if [ "$has_src_sol" -eq 1 ]; then
    echo "[quality-gate] npm run docs:gen"
    npm run docs:gen
    if [ "$mode" = "staged" ]; then
        if git check-ignore -q "$generated_docs_dir"; then
            echo "[quality-gate] ${generated_docs_dir} is ignored; skipping auto-stage."
        else
            git add "$generated_docs_dir"
        fi
    else
        if git check-ignore -q "$generated_docs_dir"; then
            echo "[quality-gate] ${generated_docs_dir} is ignored in git; skipping CI drift check."
        else
            if ! git diff --exit-code -- "$generated_docs_dir"; then
                echo "[quality-gate] ERROR: generated docs are stale. Run npm run docs:gen and include ${generated_docs_dir} updates."
                exit 1
            fi

            if [ -n "$(git ls-files --others --exclude-standard -- "$generated_docs_dir")" ]; then
                echo "[quality-gate] ERROR: generated docs under ${generated_docs_dir} include untracked files."
                git ls-files --others --exclude-standard -- "$generated_docs_dir"
                exit 1
            fi
        fi
    fi
fi

echo "[quality-gate] PASS"
