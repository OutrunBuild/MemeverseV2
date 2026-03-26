#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <changed-files-list>"
    exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

changed_files_list="$1"
if [ ! -f "$changed_files_list" ]; then
    echo "[check-coverage] ERROR: changed files list not found: $changed_files_list"
    exit 1
fi

read_policy_value() {
    local key="$1"
    local default_value="$2"
    local value

    if value="$(node ./script/process/read-process-config.js policy "$key" 2>/dev/null)"; then
        printf '%s' "$value"
        return
    fi

    printf '%s' "$default_value"
}

coverage_enabled="$(read_policy_value quality_gate.coverage.enabled false)"
if [ "$coverage_enabled" != "true" ]; then
    echo "[check-coverage] coverage gate disabled, skipping."
    exit 0
fi

forge_bin="${FORGE_BIN:-forge}"
report_file="$(read_policy_value quality_gate.coverage.report_file 'coverage/lcov.info')"
exclude_tests="$(read_policy_value quality_gate.coverage.exclude_tests true)"
ir_minimum="$(read_policy_value quality_gate.coverage.ir_minimum false)"

mkdir -p "$(dirname "$report_file")"

coverage_command=("$forge_bin" coverage --report lcov --report-file "$report_file")
if [ "$exclude_tests" = "true" ]; then
    coverage_command+=(--exclude-tests)
fi
if [ "$ir_minimum" = "true" ]; then
    coverage_command+=(--ir-minimum)
fi

echo "[check-coverage] ${coverage_command[*]}"
"${coverage_command[@]}"

node ./script/process/check-coverage.js "$changed_files_list" "$report_file"
