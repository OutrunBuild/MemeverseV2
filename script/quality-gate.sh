#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

mode="${QUALITY_GATE_MODE:-staged}"

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
has_swap_src_sol=0
has_sol_tests=0
solidity_candidates=()
solidity_files=()
shell_candidates=()
shell_files=()

while IFS= read -r file; do
    [ -z "$file" ] && continue

    if [[ "$file" =~ ^src/swap/.*\.sol$ ]]; then
        has_src_sol=1
        has_swap_src_sol=1
        solidity_candidates+=("$file")
    elif [[ "$file" =~ ^src/.*\.sol$ ]]; then
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
    review_files="$(echo "$changed_files" | grep -E '^docs/reviews/.*\.md$' | grep -Ev '^docs/reviews/(README|TEMPLATE)\.md$' || true)"
    if [ -z "$review_files" ]; then
        echo "[quality-gate] ERROR: src Solidity changes require a review note under docs/reviews/*.md in this change set"
        echo "[quality-gate] Use docs/reviews/TEMPLATE.md and fill the required Impact, Docs, Tests, Verification, and Decision fields."
        exit 1
    fi
    behavior_change_declared=0

    while IFS= read -r review_file; do
        [ -z "$review_file" ] && continue
        bash ./script/check-review-note.sh "$review_file"

        behavior_change="$(awk '
            index($0, "- Behavior change:") == 1 {
                value = substr($0, length("- Behavior change:") + 1)
                sub(/^ /, "", value)
                print value
                exit
            }
        ' "$review_file")"

        if [ "$behavior_change" = "yes" ]; then
            behavior_change_declared=1
        fi
    done <<< "$review_files"

    if [ "$behavior_change_declared" -eq 1 ]; then
        docs_updates="$(echo "$changed_files" | grep -E '^docs/.*\.md$' | grep -Ev '^docs/(contracts|plans|reviews)/' || true)"
        if [ -z "$docs_updates" ]; then
            echo "[quality-gate] ERROR: behavior-changing src Solidity changes require at least one non-generated docs/*.md update"
            echo "[quality-gate] Excluded paths: docs/contracts/**, docs/plans/**, docs/reviews/**"
            exit 1
        fi

        if [ "$has_swap_src_sol" -eq 1 ]; then
            swap_docs_updates="$(echo "$changed_files" | grep -E '^docs/memeverse-swap/.*\.md$' || true)"
            if [ -z "$swap_docs_updates" ]; then
                echo "[quality-gate] ERROR: behavior-changing src/swap/**/*.sol changes require at least one docs/memeverse-swap/*.md update"
                exit 1
            fi
        fi
    fi
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
    echo "[quality-gate] npm run docs:check"
    npm run docs:check
fi

echo "[quality-gate] PASS"
