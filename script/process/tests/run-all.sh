#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

test_dir="${PROCESS_SELFTEST_RUN_ALL_TEST_DIR:-script/process/tests}"
required_scripts=()
filter_pattern=""
isolated_env_vars=(
    "CHANGE_CLASSIFIER_DIFF_FILE"
    "CHANGE_CLASSIFIER_FORCE"
    "FOLLOW_UP_BRIEF_OUTPUT_DIR"
    "FORCE_CODEX_REVIEW"
    "PROCESS_POLICY_FILE"
    "PROCESS_RULE_MAP_FILE"
    "QUALITY_GATE_FILE_LIST"
    "QUALITY_GATE_MODE"
    "QUALITY_GATE_REVIEW_NOTE"
    "REMEDIATION_LOOP_DATE"
)

while [ "$#" -gt 0 ]; do
    case "$1" in
        --filter)
            if [ "$#" -lt 2 ] || [ -z "${2:-}" ]; then
                echo "[process-selftest] --filter requires a non-empty pattern" >&2
                exit 1
            fi
            filter_pattern="$2"
            shift 2
            ;;
        *)
            echo "[process-selftest] unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

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

run_selftest() {
    local test_script="$1"
    local -a env_cmd=("env")
    local env_var

    # Strip process-control env inherited from outer gates while preserving
    # per-test explicit fixtures set inside the selftest scripts themselves.
    for env_var in "${isolated_env_vars[@]}"; do
        env_cmd+=("-u" "$env_var")
    done

    "${env_cmd[@]}" bash "$test_script"
}

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

matched_scripts=0
while IFS= read -r test_script; do
    if [ -n "$filter_pattern" ]; then
        test_script_name="$(basename "$test_script")"
        if [[ "$test_script" != *"$filter_pattern"* ]] && [[ "$test_script_name" != *"$filter_pattern"* ]]; then
            continue
        fi
    fi

    matched_scripts=1
    echo "[process-selftest] running $test_script"
    run_selftest "$test_script"
done < <(find "$test_dir" -maxdepth 1 -type f -name '*.sh' ! -name 'run-all.sh' | sort)

if [ "$matched_scripts" -eq 0 ]; then
    echo "[process-selftest] no selftests matched filter: $filter_pattern" >&2
    exit 1
fi

echo "[process-selftest] PASS"
