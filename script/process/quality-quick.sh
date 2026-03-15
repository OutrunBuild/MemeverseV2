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
    echo "[quality-quick] no files to check, skipping."
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
src_solidity_candidates=()
test_solidity_candidates=()
solidity_files=()
src_solidity_files=()
changed_test_files=()
shell_candidates=()
shell_files=()

while IFS= read -r file; do
    [ -z "$file" ] && continue

    if [[ "$file" =~ $swap_src_sol_pattern ]]; then
        has_src_sol=1
        has_swap_src_sol=1
        src_solidity_candidates+=("$file")
    elif [[ "$file" =~ $src_sol_pattern ]]; then
        has_src_sol=1
        src_solidity_candidates+=("$file")
    elif [[ "$file" =~ $test_tsol_pattern ]]; then
        has_sol_tests=1
        test_solidity_candidates+=("$file")
        changed_test_files+=("$file")
    elif [[ "$file" =~ $test_sol_pattern ]]; then
        test_solidity_candidates+=("$file")
    fi

    if [[ "$file" =~ $shell_pattern ]]; then
        shell_candidates+=("$file")
    fi
done <<< "$changed_files"

for file in "${src_solidity_candidates[@]}" "${test_solidity_candidates[@]}"; do
    [ -z "$file" ] && continue
    if [ -f "$file" ]; then
        solidity_files+=("$file")
    fi
done

for file in "${src_solidity_candidates[@]}"; do
    [ -z "$file" ] && continue
    if [ -f "$file" ]; then
        src_solidity_files+=("$file")
    fi
done

for file in "${shell_candidates[@]}"; do
    [ -z "$file" ] && continue
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
        echo "[quality-quick] forge fmt --check (changed Solidity files only)"
        forge fmt --check "${solidity_files[@]}"
    fi

    if [ "$has_src_sol" -eq 1 ] && [ "${#src_solidity_files[@]}" -gt 0 ]; then
        echo "[quality-quick] bash ./script/process/check-natspec.sh (changed src Solidity files only)"
        bash ./script/process/check-natspec.sh "${src_solidity_files[@]}"
    fi

    echo "[quality-quick] forge build"
    forge build
fi

targeted_tests=()
for file in "${changed_test_files[@]}"; do
    if [ -f "$file" ]; then
        targeted_tests+=("$file")
    fi
done

if [ "$has_swap_src_sol" -eq 1 ]; then
    while IFS= read -r mapped_test; do
        [ -z "$mapped_test" ] && continue
        if [ -f "$mapped_test" ]; then
            targeted_tests+=("$mapped_test")
        fi
    done < <(
        CHANGED_FILES="$changed_files" node - <<'EOF'
const fs = require('fs');
const path = require('path');

const changedFiles = (process.env.CHANGED_FILES || '').split(/\r?\n/).filter(Boolean);
const ruleMapPath = process.env.PROCESS_RULE_MAP_FILE || 'docs/process/rule-map.json';
const ruleMap = JSON.parse(fs.readFileSync(path.resolve(ruleMapPath), 'utf8'));
const seen = new Set();
const tests = [];

const rules = Array.isArray(ruleMap.rules) ? ruleMap.rules : [];
const version = ruleMap.version || 1;

for (const rule of rules) {
  let triggered = false;

  if (version === 1) {
    triggered = changedFiles.some((file) => file.startsWith(rule.path_prefix || ''));
    if (!triggered) continue;
    for (const test of rule.required_test_patterns || []) {
      if (!seen.has(test)) {
        seen.add(test);
        tests.push(test);
      }
    }
    continue;
  }

  const triggerPaths = rule.triggers?.any_of || [];
  triggered = triggerPaths.some((candidate) => changedFiles.includes(candidate));
  if (!triggered) continue;

  for (const test of rule.change_requirement?.tests || []) {
    if (!seen.has(test)) {
      seen.add(test);
      tests.push(test);
    }
  }
}

for (const test of tests) {
  process.stdout.write(`${test}\n`);
}
EOF
    )
fi

if [ "${#targeted_tests[@]}" -gt 0 ]; then
    mapfile -t deduped_targeted_tests < <(printf '%s\n' "${targeted_tests[@]}" | awk '!seen[$0]++')
    for test_file in "${deduped_targeted_tests[@]}"; do
        echo "[quality-quick] forge test --match-path $test_file"
        forge test --match-path "$test_file"
    done
else
    echo "[quality-quick] no targeted Solidity tests selected."
fi

if [ "${#shell_files[@]}" -gt 0 ]; then
    echo "[quality-quick] bash -n (changed shell scripts)"
    bash -n "${shell_files[@]}"
fi

echo "[quality-quick] PASS (quick only, final verification still requires npm run quality:gate)"
