#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

mode="${QUALITY_GATE_MODE:-staged}"

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
    changed_files="$(git diff --cached --name-only --diff-filter=ACMRD)"
fi

if [ -z "$changed_files" ]; then
    echo "[quality-gate] no files to check, skipping."
    exit 0
fi

changed_files_tmp="$(mktemp)"
trap 'rm -f "$changed_files_tmp"' EXIT
printf '%s\n' "$changed_files" > "$changed_files_tmp"

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
stale_evidence_remediation_command="$(read_policy_value quality_gate.stale_evidence_remediation_command 'npm run stale-evidence:loop')"
stale_evidence_exit_code="$(read_policy_value quality_gate.stale_evidence_exit_code '2')"
mapfile -t process_selftest_patterns < <(node ./script/process/read-process-config.js policy quality_gate.process_selftest_patterns --lines)
mapfile -t process_default_roles < <(node ./script/process/read-process-config.js policy quality_gate.process_default_roles --lines)
mapfile -t package_default_roles < <(node ./script/process/read-process-config.js policy quality_gate.package_default_roles --lines)
mapfile -t docs_contract_default_roles < <(node ./script/process/read-process-config.js policy quality_gate.docs_contract_default_roles --lines)
mapfile -t local_codex_review_classifications < <(node ./script/process/read-process-config.js policy verifier.local_codex_review.required_classifications --lines 2>/dev/null || printf '%s\n' 'prod-semantic' 'high-risk')
local_codex_review_force_env="$(node ./script/process/read-process-config.js policy verifier.local_codex_review.force_env 2>/dev/null || printf '%s' 'FORCE_CODEX_REVIEW')"
classification_json="$(QUALITY_GATE_MODE="$mode" QUALITY_GATE_FILE_LIST="$changed_files_tmp" CHANGE_CLASSIFIER_FORCE="${CHANGE_CLASSIFIER_FORCE:-}" CHANGE_CLASSIFIER_DIFF_FILE="${CHANGE_CLASSIFIER_DIFF_FILE:-}" node ./script/process/classify-change.js)"

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

has_src_sol=0
has_script_sol=0
has_swap_src_sol=0
has_sol_tests=0
has_process_surface=0
should_run_docs_check=0
should_run_process_selftest=0
solidity_candidates=()
src_solidity_candidates=()
solidity_files=()
src_solidity_files=()
shell_candidates=()
shell_files=()
process_js_candidates=()
process_js_files=()
package_candidates=()
package_files=()
docs_contract_candidates=()
docs_contract_files=()

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

while IFS= read -r file; do
    [ -z "$file" ] && continue

    if [[ "$file" =~ $swap_src_sol_pattern ]]; then
        has_src_sol=1
        has_swap_src_sol=1
        solidity_candidates+=("$file")
        src_solidity_candidates+=("$file")
    elif [[ "$file" =~ $src_sol_pattern ]]; then
        has_src_sol=1
        solidity_candidates+=("$file")
        src_solidity_candidates+=("$file")
    elif [[ "$file" =~ $script_sol_pattern ]]; then
        has_script_sol=1
        solidity_candidates+=("$file")
    elif [[ "$file" =~ $test_tsol_pattern ]]; then
        has_sol_tests=1
        solidity_candidates+=("$file")
    elif [[ "$file" =~ $test_sol_pattern ]]; then
        solidity_candidates+=("$file")
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

for file in "${solidity_candidates[@]}"; do
    if [ -f "$file" ]; then
        solidity_files+=("$file")
    fi
done

for file in "${src_solidity_candidates[@]}"; do
    if [ -f "$file" ]; then
        src_solidity_files+=("$file")
    fi
done

for file in "${shell_candidates[@]}"; do
    if [ -f "$file" ]; then
        shell_files+=("$file")
    fi
done

for file in "${process_js_candidates[@]}"; do
    if [ -f "$file" ]; then
        process_js_files+=("$file")
    fi
done

for file in "${package_candidates[@]}"; do
    package_files+=("$file")
done

for file in "${docs_contract_candidates[@]}"; do
    docs_contract_files+=("$file")
done

if [ "$has_src_sol" -eq 1 ]; then
    if [ "$classification" = "non-semantic" ]; then
        echo "[quality-gate] skip rule-map changed-test gate (non-semantic classification; review-note evidence still applies)"
    else
        bash ./script/process/check-rule-map.sh "$changed_files_tmp"
    fi
fi

if [ "$has_src_sol" -eq 1 ] || [ "$has_script_sol" -eq 1 ] || [ "$has_sol_tests" -eq 1 ]; then
    echo "[quality-gate] change classification: $classification"
    echo "[quality-gate] classification rationale: $classification_rationale"
    echo "[quality-gate] default roles: $(join_by_semicolon "solidity-implementer" "${classifier_required_roles[@]}")"
    echo "[quality-gate] optional roles: $(join_by_semicolon "${classifier_optional_roles[@]}")"
    echo "[quality-gate] verifier profile: $verifier_profile"

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
    slither_targets=()
    if [ "${#src_solidity_files[@]}" -gt 0 ]; then
        slither_targets=("${src_solidity_files[@]}")
    else
        slither_targets=("${src_solidity_candidates[@]}")
    fi

    echo "[quality-gate] bash ./script/process/check-slither.sh"
    bash ./script/process/check-slither.sh "${slither_targets[@]}"

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
