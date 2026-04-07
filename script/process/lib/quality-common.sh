#!/usr/bin/env bash

read_policy_value() {
    local key="$1"
    local default_value="${2-}"
    local value

    if [ "$#" -ge 2 ]; then
        if value="$(node ./script/process/read-process-config.js policy "$key" 2>/dev/null)"; then
            printf '%s' "$value"
            return
        fi

        printf '%s' "$default_value"
        return
    fi

    node ./script/process/read-process-config.js policy "$key"
}

read_policy_lines() {
    node ./script/process/read-process-config.js policy "$1" --lines
}

read_policy_lines_or_default() {
    local key="$1"
    shift
    local output

    if output="$(node ./script/process/read-process-config.js policy "$key" --lines 2>/dev/null)"; then
        printf '%s\n' "$output"
        return
    fi

    printf '%s\n' "$@"
}

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

quality_cleanup_paths=()

quality_register_cleanup_path() {
    quality_cleanup_paths+=("$1")
}

quality_cleanup() {
    local path
    for path in "${quality_cleanup_paths[@]}"; do
        [ -n "$path" ] || continue
        [ -e "$path" ] || continue
        rm -f "$path"
    done
}

quality_initialize_runtime() {
    repo_root="$(git rev-parse --show-toplevel)"
    cd "$repo_root"

    mode="${QUALITY_GATE_MODE:-staged}"

    if [ -n "${QUALITY_GATE_FILE_LIST:-}" ] && [ -f "${QUALITY_GATE_FILE_LIST}" ]; then
        changed_files="$(cat "${QUALITY_GATE_FILE_LIST}")"
    elif [ "$mode" = "ci" ]; then
        changed_files="$(load_file_list_from_ci)"
    else
        changed_files="$(git diff --cached --name-only --diff-filter=ACMRD)"
    fi
}

quality_exit_if_no_changed_files() {
    local label="$1"
    if [ -z "$changed_files" ]; then
        echo "[$label] no files to check, skipping."
        exit 0
    fi
}

quality_prepare_changed_files_tmp() {
    changed_files_tmp="$(mktemp)"
    quality_register_cleanup_path "$changed_files_tmp"
    trap quality_cleanup EXIT
    printf '%s\n' "$changed_files" > "$changed_files_tmp"
}

read_classifier_field() {
    local field="$1"
    CLASSIFICATION_JSON="$classification_json" node -e '
const document = JSON.parse(process.env.CLASSIFICATION_JSON || "{}");
const field = process.argv[1];
let value = document;
for (const key of field.split(".")) {
  if (key === "") continue;
  if (value == null || !Object.prototype.hasOwnProperty.call(value, key)) {
    process.exit(1);
  }
  value = value[key];
}
if (typeof value === "object") {
  process.stdout.write(JSON.stringify(value));
} else {
  process.stdout.write(String(value));
}
' "$field"
}

quality_load_classifier_metadata() {
    mapfile -t classifier_required_roles < <(printf '%s' "$classification_json" | node -e '
let input = "";
process.stdin.on("data", (chunk) => { input += chunk; });
process.stdin.on("end", () => {
  const document = JSON.parse(input || "{}");
  for (const role of document.required_roles || []) {
    process.stdout.write(String(role));
    process.stdout.write("\n");
  }
});
')
    mapfile -t classifier_optional_roles < <(printf '%s' "$classification_json" | node -e '
let input = "";
process.stdin.on("data", (chunk) => { input += chunk; });
process.stdin.on("end", () => {
  const document = JSON.parse(input || "{}");
  for (const role of document.optional_roles || []) {
    process.stdout.write(String(role));
    process.stdout.write("\n");
  }
});
')
    classification="$(read_classifier_field classification)"
    classification_rationale="$(read_classifier_field rationale)"
    verifier_profile="$(read_classifier_field verifier_profile)"
}

join_by_semicolon() {
    local first=1
    local item
    for item in "$@"; do
        [ -z "$item" ] && continue
        if [ "$first" -eq 1 ]; then
            printf '%s' "$item"
            first=0
        else
            printf '; %s' "$item"
        fi
    done
}

array_contains() {
    local needle="$1"
    shift
    local item
    for item in "$@"; do
        if [ "$item" = "$needle" ]; then
            return 0
        fi
    done
    return 1
}

is_truthy() {
    case "${1:-}" in
        1|true|TRUE|yes|YES|on|ON)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

quality_has_any_solidity_change() {
    [ "$has_src_sol" -eq 1 ] || [ "$has_script_sol" -eq 1 ] || [ "$has_sol_tests" -eq 1 ]
}

quality_print_solidity_context() {
    local label="$1"
    echo "[$label] change classification: $classification"
    echo "[$label] classification rationale: $classification_rationale"
    echo "[$label] default roles: $(join_by_semicolon "solidity-implementer" "${classifier_required_roles[@]}")"
    echo "[$label] optional roles: $(join_by_semicolon "${classifier_optional_roles[@]}")"
    echo "[$label] verifier profile: $verifier_profile"
}

quality_prepare_memeverse_context() {
    quality_prepare_changed_files_tmp

    swap_src_sol_pattern="$(read_policy_value quality_gate.swap_src_sol_pattern '^src/swap/.*\\.sol$')"
    src_sol_pattern="$(read_policy_value quality_gate.src_sol_pattern '^src/.*\\.sol$')"
    script_sol_pattern="$(read_policy_value quality_gate.script_sol_pattern '^script/.*\\.sol$')"
    test_tsol_pattern="$(read_policy_value quality_gate.test_tsol_pattern '^test/.*\\.t\\.sol$')"
    test_sol_pattern="$(read_policy_value quality_gate.test_sol_pattern '^test/.*\\.sol$')"
    shell_pattern="$(read_policy_value quality_gate.shell_pattern '^(script/.*\\.sh|\\.githooks/.*)$')"
    process_surface_pattern="$(read_policy_value quality_gate.process_surface_pattern '^script/process/.*$')"
    process_js_pattern="$(read_policy_value quality_gate.process_js_pattern '^script/process/.*\\.js$')"
    package_pattern="$(read_policy_value quality_gate.package_pattern '^(package\\.json|package-lock\\.json)$')"
    docs_contract_pattern="$(read_policy_value quality_gate.docs_contract_pattern '^(AGENTS\\.md|README\\.md|docs/process/.*|docs/reviews/(TEMPLATE|README)\\.md|docs/(ARCHITECTURE|GLOSSARY|TRACEABILITY|VERIFICATION)\\.md|docs/spec/.*|docs/adr/.*|\\.github/pull_request_template\\.md|\\.codex/.*)$')"
    mapfile -t process_selftest_patterns < <(read_policy_lines quality_gate.process_selftest_patterns)
    mapfile -t process_default_roles < <(read_policy_lines quality_gate.process_default_roles)
    mapfile -t package_default_roles < <(read_policy_lines quality_gate.package_default_roles)
    mapfile -t docs_contract_default_roles < <(read_policy_lines quality_gate.docs_contract_default_roles)

    classification_json="$(
        QUALITY_GATE_MODE="$mode" \
        QUALITY_GATE_FILE_LIST="$changed_files_tmp" \
        CHANGE_CLASSIFIER_FORCE="${CHANGE_CLASSIFIER_FORCE:-}" \
        CHANGE_CLASSIFIER_DIFF_FILE="${CHANGE_CLASSIFIER_DIFF_FILE:-}" \
        node ./script/process/classify-change.js
    )"
    quality_load_classifier_metadata
    rule_map_path="$(node ./script/process/read-process-config.js rule-map __file__)"

    has_src_sol=0
    has_script_sol=0
    has_swap_src_sol=0
    has_sol_tests=0
    has_process_surface=0
    should_run_docs_check=0
    should_run_process_selftest=0
    src_solidity_candidates=()
    test_solidity_candidates=()
    solidity_files=()
    src_solidity_files=()
    changed_test_files=()
    shell_candidates=()
    shell_files=()
    process_js_candidates=()
    process_js_files=()
    package_candidates=()
    package_files=()
    docs_contract_candidates=()
    docs_contract_files=()

    while IFS= read -r file; do
        [ -z "$file" ] && continue

        if [[ "$file" =~ $swap_src_sol_pattern ]]; then
            has_src_sol=1
            has_swap_src_sol=1
            src_solidity_candidates+=("$file")
        elif [[ "$file" =~ $src_sol_pattern ]]; then
            has_src_sol=1
            src_solidity_candidates+=("$file")
        elif [[ "$file" =~ $script_sol_pattern ]]; then
            has_script_sol=1
            src_solidity_candidates+=("$file")
        elif [[ "$file" =~ $test_tsol_pattern ]]; then
            has_sol_tests=1
            test_solidity_candidates+=("$file")
            changed_test_files+=("$file")
        elif [[ "$file" =~ $test_sol_pattern ]]; then
            test_solidity_candidates+=("$file")
        fi

        if [[ "$file" =~ $process_surface_pattern ]]; then
            has_process_surface=1
            should_run_docs_check=1
        fi

        if [[ "$file" =~ $shell_pattern ]]; then
            has_process_surface=1
            should_run_docs_check=1
            shell_candidates+=("$file")
        fi

        if [[ "$file" =~ $process_js_pattern ]]; then
            has_process_surface=1
            should_run_docs_check=1
            process_js_candidates+=("$file")
        fi

        if [[ "$file" =~ $package_pattern ]]; then
            package_candidates+=("$file")
            should_run_docs_check=1
        fi

        if [[ "$file" =~ $docs_contract_pattern ]]; then
            docs_contract_candidates+=("$file")
            should_run_docs_check=1
        fi

        for pattern in "${process_selftest_patterns[@]}"; do
            if [[ "$file" =~ $pattern ]]; then
                should_run_process_selftest=1
                break
            fi
        done
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

    for file in "${process_js_candidates[@]}"; do
        [ -z "$file" ] && continue
        if [ -f "$file" ]; then
            process_js_files+=("$file")
        fi
    done

    for file in "${package_candidates[@]}"; do
        [ -z "$file" ] && continue
        package_files+=("$file")
    done

    for file in "${docs_contract_candidates[@]}"; do
        [ -z "$file" ] && continue
        docs_contract_files+=("$file")
    done
}

quality_prepare_memeverse_gate_context() {
    quality_prepare_memeverse_context

    stale_evidence_remediation_command="$(read_policy_value quality_gate.stale_evidence_remediation_command 'npm run stale-evidence:loop')"
    stale_evidence_exit_code="$(read_policy_value quality_gate.stale_evidence_exit_code '2')"
    mapfile -t local_codex_review_classifications < <(read_policy_lines_or_default verifier.local_codex_review.required_classifications 'prod-semantic' 'high-risk')
    local_codex_review_force_env="$(read_policy_value verifier.local_codex_review.force_env 'FORCE_CODEX_REVIEW')"
}
