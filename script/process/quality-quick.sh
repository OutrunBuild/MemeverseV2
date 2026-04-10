#!/usr/bin/env bash
set -euo pipefail

source ./script/process/lib/quality-common.sh

quality_initialize_runtime
quality_exit_if_no_changed_files "quality-quick"
quality_prepare_memeverse_context
quality_validate_spec_surface_brief_contract

if [ "$has_src_sol" -eq 1 ]; then
    if [ "$classification" = "non-semantic" ]; then
        echo "[quality-quick] skip rule-map changed-test gate (non-semantic classification)"
    else
        bash ./script/process/check-rule-map.sh "$changed_files_tmp"
    fi
fi

if quality_has_any_solidity_change; then
    quality_print_solidity_context "quality-quick"

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
    if { [ "$has_src_sol" -eq 1 ] || [ "$has_script_sol" -eq 1 ]; } && { [ "$classification" = "prod-semantic" ] || [ "$classification" = "high-risk" ]; }; then
        quick_coverage_metrics="$(read_policy_value quality_gate.coverage.quick_metrics 'line,function')"
        echo "[quality-quick] bash ./script/process/check-coverage.sh (metrics: $quick_coverage_metrics)"
        COVERAGE_METRICS="$quick_coverage_metrics" bash ./script/process/check-coverage.sh "$changed_files_tmp"
    elif [ "$has_src_sol" -eq 1 ] || [ "$has_script_sol" -eq 1 ]; then
        echo "[quality-quick] skip coverage (verifier profile: $verifier_profile)"
    fi
fi

targeted_tests=()
for file in "${changed_test_files[@]}"; do
    if [ -f "$file" ]; then
        targeted_tests+=("$file")
    fi
done

if [ "$has_src_sol" -eq 1 ]; then
    while IFS= read -r mapped_test; do
        [ -z "$mapped_test" ] && continue
        if [ -f "$mapped_test" ]; then
            targeted_tests+=("$mapped_test")
        fi
    done < <(
        PROCESS_CHANGED_FILES="$changed_files" PROCESS_RULE_MAP_FILE="$rule_map_path" node ./script/process/read-process-config.js rule-map triggered.change.tests --lines
    )
fi

if [ "$classification" = "non-semantic" ]; then
    echo "[quality-quick] skip Solidity tests (non-semantic classification)"
elif [ "${#targeted_tests[@]}" -gt 0 ]; then
    mapfile -t deduped_targeted_tests < <(printf '%s\n' "${targeted_tests[@]}" | awk '!seen[$0]++')
    for test_file in "${deduped_targeted_tests[@]}"; do
        echo "[quality-quick] forge test --match-path $test_file"
        forge test --match-path "$test_file"
    done
else
    echo "[quality-quick] no targeted Solidity tests selected."
fi

if [ "${#shell_files[@]}" -gt 0 ]; then
    echo "[quality-quick] default roles: $(join_by_semicolon "${process_default_roles[@]}")"
    echo "[quality-quick] bash -n (changed shell scripts)"
    bash -n "${shell_files[@]}"
fi

if [ "${#process_js_files[@]}" -gt 0 ]; then
    echo "[quality-quick] default roles: $(join_by_semicolon "${process_default_roles[@]}")"
    echo "[quality-quick] node --check (changed process JS files)"
    node --check "${process_js_files[@]}"
fi

if [ "${#package_files[@]}" -gt 0 ]; then
    echo "[quality-quick] default roles: $(join_by_semicolon "${package_default_roles[@]}")"
fi

if [ "$has_spec_surface" -eq 1 ]; then
    echo "[quality-quick] default roles: $(join_by_semicolon "${spec_default_roles[@]}")"
    echo "[quality-quick] bash ./script/process/check-spec-reviewer-report.sh"
    bash ./script/process/check-spec-reviewer-report.sh
fi

if [ "${#docs_contract_files[@]}" -gt 0 ] && [ "$has_process_surface" -eq 0 ] && [ "${#package_files[@]}" -eq 0 ] && [ "$has_spec_surface" -eq 0 ]; then
    echo "[quality-quick] default roles: $(join_by_semicolon "${docs_contract_default_roles[@]}")"
fi

if [ "$should_run_docs_check" -eq 1 ]; then
    echo "[quality-quick] npm run docs:check"
    npm run docs:check
fi

if [ "$should_run_process_selftest" -eq 1 ]; then
    if [ "$has_spec_surface" -eq 1 ] && [ "$has_process_surface" -eq 0 ] && [ "${#package_files[@]}" -eq 0 ]; then
        echo "[quality-quick] default roles: $(join_by_semicolon "${spec_default_roles[@]}")"
    elif [ "$has_process_surface" -eq 0 ] && [ "${#package_files[@]}" -eq 0 ]; then
        echo "[quality-quick] default roles: $(join_by_semicolon "${process_default_roles[@]}")"
    fi
    echo "[quality-quick] npm run process:selftest"
    npm run process:selftest
fi

echo "[quality-quick] PASS (quick only, final verification still requires npm run quality:gate)"
