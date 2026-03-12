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

swap_src_sol_pattern="$(node ./script/process/read-process-config.js policy quality_gate.swap_src_sol_pattern)"
src_sol_pattern="$(node ./script/process/read-process-config.js policy quality_gate.src_sol_pattern)"
test_tsol_pattern="$(node ./script/process/read-process-config.js policy quality_gate.test_tsol_pattern)"
test_sol_pattern="$(node ./script/process/read-process-config.js policy quality_gate.test_sol_pattern)"
shell_pattern="$(node ./script/process/read-process-config.js policy quality_gate.shell_pattern)"

has_src_sol=0
has_swap_src_sol=0
has_sol_tests=0
solidity_candidates=()
solidity_files=()
shell_candidates=()
shell_files=()

while IFS= read -r file; do
    [ -z "$file" ] && continue

    if [[ "$file" =~ $swap_src_sol_pattern ]]; then
        has_src_sol=1
        has_swap_src_sol=1
        solidity_candidates+=("$file")
    elif [[ "$file" =~ $src_sol_pattern ]]; then
        has_src_sol=1
        solidity_candidates+=("$file")
    elif [[ "$file" =~ $test_tsol_pattern ]]; then
        has_sol_tests=1
        solidity_candidates+=("$file")
    elif [[ "$file" =~ $test_sol_pattern ]]; then
        solidity_candidates+=("$file")
    fi

    if [[ "$file" =~ $shell_pattern ]]; then
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
    review_note_pattern="$(node ./script/process/read-process-config.js policy quality_gate.review_note_path_pattern)"
    review_note_exclude_pattern="$(node ./script/process/read-process-config.js policy quality_gate.review_note_exclude_pattern)"
    review_files="$(echo "$changed_files" | grep -E "$review_note_pattern" | grep -Ev "$review_note_exclude_pattern" || true)"
    if [ -z "$review_files" ]; then
        echo "[quality-gate] ERROR: src Solidity changes require a review note under docs/reviews/*.md in this change set"
        echo "[quality-gate] Use docs/reviews/TEMPLATE.md and fill the required Impact, Docs, Tests, Verification, and Decision fields."
        exit 1
    fi
    behavior_change_declared=0

    while IFS= read -r review_file; do
        [ -z "$review_file" ] && continue
        bash ./script/process/check-review-note.sh "$review_file"

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
        non_generated_docs_pattern="$(node ./script/process/read-process-config.js policy quality_gate.non_generated_docs_pattern)"
        non_generated_docs_exclude_pattern="$(node ./script/process/read-process-config.js policy quality_gate.non_generated_docs_exclude_pattern)"
        behavior_docs_required_message="$(node ./script/process/read-process-config.js policy quality_gate.behavior_docs_required_message)"
        behavior_docs_excluded_message="$(node ./script/process/read-process-config.js policy quality_gate.behavior_docs_excluded_message)"
        docs_updates="$(echo "$changed_files" | grep -E "$non_generated_docs_pattern" | grep -Ev "$non_generated_docs_exclude_pattern" || true)"
        if [ -z "$docs_updates" ]; then
            echo "[quality-gate] ERROR: ${behavior_docs_required_message}"
            echo "[quality-gate] ${behavior_docs_excluded_message}"
            exit 1
        fi

        if [ "$has_swap_src_sol" -eq 1 ]; then
            swap_docs_pattern="$(node ./script/process/read-process-config.js policy quality_gate.swap_docs_pattern)"
            swap_docs_required_message="$(node ./script/process/read-process-config.js policy quality_gate.swap_docs_required_message)"
            swap_docs_updates="$(echo "$changed_files" | grep -E "$swap_docs_pattern" || true)"
            if [ -z "$swap_docs_updates" ]; then
                echo "[quality-gate] ERROR: ${swap_docs_required_message}"
                exit 1
            fi
        fi
    fi

    changed_files_tmp="$(mktemp)"
    printf '%s\n' "$changed_files" > "$changed_files_tmp"
    bash ./script/process/check-rule-map.sh "$changed_files_tmp" $review_files
    rm -f "$changed_files_tmp"
fi

if [ "$has_src_sol" -eq 1 ] || [ "$has_sol_tests" -eq 1 ]; then
    if [ "${#solidity_files[@]}" -gt 0 ]; then
        echo "[quality-gate] forge fmt --check (changed Solidity files only)"
        forge fmt --check "${solidity_files[@]}"
    fi

    if [ "$has_src_sol" -eq 1 ] && [ "${#solidity_files[@]}" -gt 0 ]; then
        echo "[quality-gate] bash ./script/process/check-natspec.sh (changed src Solidity files only)"
        bash ./script/process/check-natspec.sh "${solidity_files[@]}"
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
