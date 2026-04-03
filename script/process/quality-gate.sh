#!/usr/bin/env bash
set -euo pipefail

run_stale_evidence_remediation() {
    local remediation_command="$1"
    local remediation_output
    local remediation_status

    echo "[quality-gate] stale evidence detected; running remediation loop: $remediation_command"

    set +e
    remediation_output="$(
        env \
            QUALITY_GATE_MODE="$mode" \
            QUALITY_GATE_FILE_LIST="${QUALITY_GATE_FILE_LIST:-}" \
            QUALITY_GATE_REVIEW_NOTE="${QUALITY_GATE_REVIEW_NOTE:-}" \
            FOLLOW_UP_BRIEF_OUTPUT_DIR="${FOLLOW_UP_BRIEF_OUTPUT_DIR:-}" \
            REMEDIATION_LOOP_DATE="${REMEDIATION_LOOP_DATE:-}" \
            bash -lc "$remediation_command" 2>&1
    )"
    remediation_status=$?
    set -e

    printf '%s\n' "$remediation_output"
    return "$remediation_status"
}

source ./script/process/lib/quality-common.sh

quality_initialize_runtime
quality_exit_if_no_changed_files "quality-gate"
quality_prepare_memeverse_gate_context

if [ "$has_src_sol" -eq 1 ]; then
    if [ "$classification" = "non-semantic" ]; then
        echo "[quality-gate] skip rule-map changed-test gate (non-semantic classification; review-note evidence still applies)"
    else
        bash ./script/process/check-rule-map.sh "$changed_files_tmp"
    fi
fi

if quality_has_any_solidity_change; then
    quality_print_solidity_context "quality-gate"

    if [ "${#solidity_files[@]}" -gt 0 ]; then
        echo "[quality-gate] forge fmt --check (changed Solidity files only)"
        forge fmt --check "${solidity_files[@]}"
    fi

    if [ "$has_src_sol" -eq 1 ] && [ "${#src_solidity_files[@]}" -gt 0 ]; then
        echo "[quality-gate] bash ./script/process/check-natspec.sh (changed src Solidity files only)"
        bash ./script/process/check-natspec.sh "${src_solidity_files[@]}"
    fi

    echo "[quality-gate] forge build"
    forge build

    case "$classification" in
        non-semantic)
            echo "[quality-gate] skip forge test / coverage (non-semantic classification)"
            ;;
        test-semantic)
            echo "[quality-gate] forge test -vvv"
            forge test -vvv
            ;;
        prod-semantic|high-risk)
            echo "[quality-gate] forge test -vvv"
            forge test -vvv
            ;;
        *)
            echo "[quality-gate] skip forge test / coverage (classification '$classification')"
            ;;
    esac
fi

if { [ "$has_src_sol" -eq 1 ] || [ "$has_script_sol" -eq 1 ]; } && { [ "$classification" = "prod-semantic" ] || [ "$classification" = "high-risk" ]; }; then
    echo "[quality-gate] bash ./script/process/check-coverage.sh"
    bash ./script/process/check-coverage.sh "$changed_files_tmp"
elif [ "$has_src_sol" -eq 1 ] || [ "$has_script_sol" -eq 1 ]; then
    echo "[quality-gate] skip coverage (verifier profile: $verifier_profile)"
fi

if [ "$has_src_sol" -eq 1 ] && { [ "$classification" = "prod-semantic" ] || [ "$classification" = "high-risk" ]; }; then
    echo "[quality-gate] bash ./script/process/check-slither.sh"
    bash ./script/process/check-slither.sh

    echo "[quality-gate] bash ./script/process/check-gas-report.sh"
    bash ./script/process/check-gas-report.sh
elif [ "$has_src_sol" -eq 1 ]; then
    echo "[quality-gate] skip slither / gas (verifier profile: $verifier_profile)"
fi

if [ "$has_src_sol" -eq 1 ] || [ "$has_script_sol" -eq 1 ]; then
    local_codex_review_required=0
    if [ "$mode" != "ci" ]; then
        if is_truthy "${!local_codex_review_force_env:-}"; then
            local_codex_review_required=1
        elif array_contains "$classification" "${local_codex_review_classifications[@]}"; then
            local_codex_review_required=1
        fi
    fi

    if [ "$has_src_sol" -eq 0 ]; then
        echo "[quality-gate] script Solidity surface routed through Solidity review-note gate"
    fi
    if [ "$local_codex_review_required" -eq 1 ]; then
        echo "[quality-gate] npm run codex:review"
        npm run codex:review
    fi
    echo "[quality-gate] bash ./script/process/check-solidity-review-note.sh"
    set +e
    review_note_output="$(bash ./script/process/check-solidity-review-note.sh 2>&1)"
    review_note_status=$?
    set -e

    printf '%s\n' "$review_note_output"

    if [ "$review_note_status" -ne 0 ]; then
        if printf '%s\n' "$review_note_output" | grep -qi "stale"; then
            set +e
            run_stale_evidence_remediation "$stale_evidence_remediation_command"
            remediation_status=$?
            set -e

            if [ "$remediation_status" -eq 0 ]; then
                exit "$stale_evidence_exit_code"
            fi

            exit "$remediation_status"
        fi

        exit "$review_note_status"
    fi
fi

if [ "$has_process_surface" -eq 1 ]; then
    echo "[quality-gate] default roles: $(join_by_semicolon "${process_default_roles[@]}")"
fi

if [ "${#shell_files[@]}" -gt 0 ]; then
    echo "[quality-gate] bash -n (changed shell scripts)"
    bash -n "${shell_files[@]}"
fi

if [ "${#process_js_files[@]}" -gt 0 ]; then
    echo "[quality-gate] node --check (changed process JS files)"
    node --check "${process_js_files[@]}"
fi

if [ "${#package_files[@]}" -gt 0 ]; then
    echo "[quality-gate] default roles: $(join_by_semicolon "${package_default_roles[@]}")"
    echo "[quality-gate] npm ci"
    npm ci
fi

if [ "$should_run_docs_check" -eq 1 ] || [ "$has_src_sol" -eq 1 ]; then
    if [ "${#docs_contract_files[@]}" -gt 0 ] && [ "$has_process_surface" -eq 0 ] && [ "${#package_files[@]}" -eq 0 ] && [ "$has_src_sol" -eq 0 ]; then
        echo "[quality-gate] default roles: $(join_by_semicolon "${docs_contract_default_roles[@]}")"
    fi
    echo "[quality-gate] npm run docs:check"
    npm run docs:check
fi

if [ "$should_run_process_selftest" -eq 1 ]; then
    if [ "$has_process_surface" -eq 0 ] && [ "${#package_files[@]}" -eq 0 ]; then
        echo "[quality-gate] default roles: $(join_by_semicolon "${process_default_roles[@]}")"
    fi
    echo "[quality-gate] npm run process:selftest"
    npm run process:selftest
fi

echo "[quality-gate] PASS"
