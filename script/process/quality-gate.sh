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
            QUALITY_GATE_CHANGESET_FILE_LIST="${QUALITY_GATE_CHANGESET_FILE_LIST:-}" \
            QUALITY_GATE_REVIEW_NOTE="${QUALITY_GATE_REVIEW_NOTE:-}" \
            QUALITY_GATE_SPEC_REVIEWER_REPORT="${QUALITY_GATE_SPEC_REVIEWER_REPORT:-}" \
            FOLLOW_UP_BRIEF_OUTPUT_DIR="${FOLLOW_UP_BRIEF_OUTPUT_DIR:-}" \
            REMEDIATION_LOOP_DATE="${REMEDIATION_LOOP_DATE:-}" \
            bash -lc "$remediation_command" 2>&1
    )"
    remediation_status=$?
    set -e

    if [ "${errors_only_mode:-0}" -eq 1 ]; then
        printf '%s\n' "$remediation_output" >&2
    else
        printf '%s\n' "$remediation_output"
    fi
    return "$remediation_status"
}

source ./script/process/lib/quality-common.sh

quality_initialize_runtime
quality_exit_if_no_changed_files "quality-gate"
quality_prepare_memeverse_gate_context
quality_validate_spec_surface_brief_contract

forge_test_verbosity="${FORGE_TEST_VERBOSITY:--vvv}"
read -r -a forge_test_args <<< "$forge_test_verbosity"
if [ "${#forge_test_args[@]}" -eq 0 ]; then
    forge_test_args=(-vvv)
fi

fast_mode=0
if [ "$mode" != "ci" ] && ! is_truthy "${CI:-}" && is_truthy "${QUALITY_GATE_FAST:-0}"; then
    fast_mode=1
fi

errors_only_mode=0
if is_truthy "${QUALITY_GATE_ERRORS_ONLY:-0}"; then
    errors_only_mode=1
    exec 1>/dev/null
fi

echo "[quality-gate] forge test verbosity: ${forge_test_args[*]}"
echo "[quality-gate] fast mode: $fast_mode (local-only)"

run_quiet_on_success() {
    local output_file
    output_file="$(mktemp)"
    quality_register_cleanup_path "$output_file"

    set +e
    "$@" >"$output_file" 2>&1
    local command_status=$?
    set -e

    if [ "$command_status" -ne 0 ]; then
        cat "$output_file" >&2
        return "$command_status"
    fi
}

run_forge_test_suite() {
    if [ "$fast_mode" -eq 1 ]; then
        local fast_no_match_test
        fast_no_match_test="${QUALITY_GATE_FAST_NO_MATCH_TEST:-^invariant_}"
        echo "[quality-gate] fast test profile: --no-match-test '$fast_no_match_test' + targeted invariants"
        run_quiet_on_success forge test "${forge_test_args[@]}" --no-match-test "$fast_no_match_test"

        local module
        local mapped=0
        local -a invariant_targets=()
        local -a module_dirs=()

        while IFS= read -r module; do
            [ -z "$module" ] && continue
            module_dirs+=("$module")
        done < <(printf '%s\n' "$changed_files" | awk -F/ '
            /^src\/[^/]+\// {print $2}
            /^script\/[^/]+\// {print $2}
        ' | awk '!seen[$0]++')

        for module in "${module_dirs[@]}"; do
            if [ -d "test/$module" ]; then
                while IFS= read -r file; do
                    [ -z "$file" ] && continue
                    invariant_targets+=("$file")
                    mapped=1
                done < <(find "test/$module" -type f -name '*Invariant*.t.sol' | sort)
            fi
        done

        if [ "$mapped" -eq 0 ]; then
            while IFS= read -r file; do
                [ -z "$file" ] && continue
                invariant_targets+=("$file")
            done < <(find test -type f -name '*Invariant*.t.sol' | sort)
        fi

        if [ "${#invariant_targets[@]}" -eq 0 ]; then
            echo "[quality-gate] fast mode: no invariant targets discovered."
            return
        fi

        mapfile -t deduped_invariant_targets < <(printf '%s\n' "${invariant_targets[@]}" | awk '!seen[$0]++')
        for invariant_file in "${deduped_invariant_targets[@]}"; do
            echo "[quality-gate] forge test ${forge_test_args[*]} --match-path $invariant_file --match-test '^invariant_'"
            run_quiet_on_success forge test "${forge_test_args[@]}" --match-path "$invariant_file" --match-test '^invariant_'
        done
        return
    fi

    run_quiet_on_success forge test "${forge_test_args[@]}"
}

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
        set +e
        forge_fmt_output="$(forge fmt --check "${solidity_files[@]}" 2>&1)"
        forge_fmt_status=$?
        set -e
        if [ "$forge_fmt_status" -ne 0 ]; then
            echo "[quality-gate] ERROR: forge fmt --check failed for changed Solidity files:" >&2
            for solidity_file in "${solidity_files[@]}"; do
                echo "- $solidity_file" >&2
            done
            exit "$forge_fmt_status"
        fi
    fi

    if [ "$has_src_sol" -eq 1 ] && [ "${#src_solidity_files[@]}" -gt 0 ]; then
        echo "[quality-gate] bash ./script/process/check-natspec.sh (changed src Solidity files only)"
        bash ./script/process/check-natspec.sh "${src_solidity_files[@]}"
    fi

    echo "[quality-gate] forge build"
    forge build

    case "$classification" in
        non-semantic)
            echo "[quality-gate] forge test ${forge_test_args[*]} (strict full suite)"
            run_forge_test_suite
            ;;
        test-semantic)
            echo "[quality-gate] forge test ${forge_test_args[*]}"
            run_forge_test_suite
            ;;
        prod-semantic|high-risk)
            echo "[quality-gate] forge test ${forge_test_args[*]}"
            run_forge_test_suite
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
elif [ "$has_src_sol" -eq 1 ]; then
    echo "[quality-gate] skip slither (verifier profile: $verifier_profile)"
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

    if [ "$review_note_status" -ne 0 ]; then
        printf '%s\n' "$review_note_output" >&2
    elif [ "$errors_only_mode" -eq 0 ]; then
        printf '%s\n' "$review_note_output"
    fi

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

if [ "$has_spec_surface" -eq 1 ]; then
    echo "[quality-gate] default roles: $(join_by_semicolon "${spec_default_roles[@]}")"
    echo "[quality-gate] bash ./script/process/check-spec-reviewer-report.sh"
    set +e
    spec_review_output="$(bash ./script/process/check-spec-reviewer-report.sh 2>&1)"
    spec_review_status=$?
    set -e

    if [ "$spec_review_status" -ne 0 ]; then
        printf '%s\n' "$spec_review_output" >&2
    elif [ "$errors_only_mode" -eq 0 ]; then
        printf '%s\n' "$spec_review_output"
    fi

    if [ "$spec_review_status" -ne 0 ]; then
        if printf '%s\n' "$spec_review_output" | grep -qi "stale"; then
            set +e
            run_stale_evidence_remediation "$stale_evidence_remediation_command"
            remediation_status=$?
            set -e

            if [ "$remediation_status" -eq 0 ]; then
                exit "$stale_evidence_exit_code"
            fi

            exit "$remediation_status"
        fi

        exit "$spec_review_status"
    fi
elif [ "${#docs_contract_files[@]}" -gt 0 ] && [ "$has_process_surface" -eq 0 ] && [ "${#package_files[@]}" -eq 0 ] && [ "$has_src_sol" -eq 0 ]; then
    echo "[quality-gate] default roles: $(join_by_semicolon "${docs_contract_default_roles[@]}")"
fi

if [ "$should_run_docs_check" -eq 1 ] || [ "$has_src_sol" -eq 1 ]; then
    echo "[quality-gate] npm run docs:check"
    npm run docs:check
fi

if [ "$should_run_process_selftest" -eq 1 ]; then
    if [ "$has_spec_surface" -eq 1 ] && [ "$has_process_surface" -eq 0 ] && [ "${#package_files[@]}" -eq 0 ]; then
        echo "[quality-gate] default roles: $(join_by_semicolon "${spec_default_roles[@]}")"
    elif [ "$has_process_surface" -eq 0 ] && [ "${#package_files[@]}" -eq 0 ]; then
        echo "[quality-gate] default roles: $(join_by_semicolon "${process_default_roles[@]}")"
    fi
    echo "[quality-gate] npm run process:selftest"
    npm run process:selftest
fi

if ! is_truthy "${QUALITY_GATE_HIDE_PASS:-0}"; then
    echo "[quality-gate] PASS"
fi
