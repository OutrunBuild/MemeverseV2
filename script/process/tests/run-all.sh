#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

test_dir="${PROCESS_SELFTEST_RUN_ALL_TEST_DIR:-script/process/tests}"
required_scripts=()

if [ -n "${PROCESS_SELFTEST_RUN_ALL_REQUIRED_TOP_LEVEL:-}" ]; then
    while IFS= read -r script_name; do
        [ -n "$script_name" ] && required_scripts+=("$script_name")
    done < <(printf '%s\n' "${PROCESS_SELFTEST_RUN_ALL_REQUIRED_TOP_LEVEL}")
else
    required_scripts=(
        "brief-templates.sh"
        "change-classifier.sh"
        "check-coverage.sh"
        "check-docs.sh"
        "check-gas-report.sh"
        "check-local-doc-artifacts-ignore.sh"
        "check-natspec.sh"
        "check-pr-body.sh"
        "check-slither.sh"
        "check-solidity-review-note.sh"
        "ci-workflow.sh"
        "codex-review.sh"
        "logic-reviewer-contract.sh"
        "pre-push-quality-gate.sh"
        "process-policy.sh"
        "quality-gate-coverage.sh"
        "quality-gate-stale-remediation.sh"
        "quality-gates.sh"
        "quality-quick-coverage.sh"
        "quality-quick.sh"
        "rule-map-gate.sh"
        "run-all-required-guard.sh"
        "stale-evidence-loop.sh"
    )
fi

missing_required_scripts=()
for script_name in "${required_scripts[@]}"; do
    if [ ! -f "$test_dir/$script_name" ]; then
        missing_required_scripts+=("$script_name")
    fi
done

if [ "${#missing_required_scripts[@]}" -gt 0 ]; then
    printf -v missing_summary '%s, ' "${missing_required_scripts[@]}"
    missing_summary="${missing_summary%, }"
    echo "[process-selftest] missing required top-level selftests: $missing_summary"
    exit 1
fi

while IFS= read -r test_script; do
    echo "[process-selftest] running $test_script"
    bash "$test_script"
done < <(find "$test_dir" -maxdepth 1 -type f -name '*.sh' ! -name 'run-all.sh' | sort)

echo "[process-selftest] PASS"
