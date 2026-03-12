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
    changed_files_tmp="$(mktemp)"
    printf '%s\n' "$changed_files" > "$changed_files_tmp"
    bash ./script/process/check-rule-map.sh "$changed_files_tmp"
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

if [ "$has_src_sol" -eq 1 ] && [ "${#solidity_files[@]}" -gt 0 ]; then
    echo "[quality-gate] bash ./script/process/check-slither.sh"
    bash ./script/process/check-slither.sh "${solidity_files[@]}"

    echo "[quality-gate] bash ./script/process/check-gas-snapshot.sh"
    bash ./script/process/check-gas-snapshot.sh
fi

if [ "$mode" != "ci" ] && [ "$has_src_sol" -eq 1 ]; then
    echo "[quality-gate] bash ./script/process/check-solidity-review-note.sh"
    bash ./script/process/check-solidity-review-note.sh
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
