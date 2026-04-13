#!/usr/bin/env bash
set -euo pipefail

profile="full"
changed_files_arg=""
emit_run_record=""
fail_on_legacy=0

declare -a cleanup_paths=()

usage() {
    cat >&2 <<'EOF'
Usage: bash ./script/harness/gate.sh [--profile fast|full|ci] [--changed-files <path>] [--emit-run-record <path>] [--fail-on-legacy]
EOF
}

die() {
    echo "[gate] ERROR: $*" >&2
    exit 1
}

register_cleanup() {
    cleanup_paths+=("$1")
}

cleanup() {
    local path
    for path in "${cleanup_paths[@]}"; do
        [ -n "$path" ] || continue
        [ -e "$path" ] || continue
        rm -f "$path"
    done
}

trap cleanup EXIT

json_array_from_values() {
    if [ "$#" -eq 0 ]; then
        printf '[]'
        return
    fi
    jq -cn '$ARGS.positional' --args "$@"
}

shell_join() {
    local arg
    local -a escaped=()
    for arg in "$@"; do
        printf -v arg '%q' "$arg"
        escaped+=("$arg")
    done
    local joined="${escaped[*]:-}"
    printf '%s' "$joined"
}

append_unique() {
    local array_name="$1"
    local value="$2"
    local -n array_ref="$array_name"
    local existing

    for existing in "${array_ref[@]}"; do
        if [ "$existing" = "$value" ]; then
            return
        fi
    done

    array_ref+=("$value")
}

array_contains() {
    local needle="$1"
    shift
    local value

    for value in "$@"; do
        if [ "$value" = "$needle" ]; then
            return 0
        fi
    done

    return 1
}

append_finding() {
    local target_name="$1"
    local source_role="$2"
    local summary="$3"
    local rule_id="${4-}"
    local severity="${5-}"
    local current="${!target_name}"
    local updated

    updated="$(jq -cn \
        --argjson existing "$current" \
        --arg source_role "$source_role" \
        --arg summary "$summary" \
        --arg rule_id "$rule_id" \
        --arg severity "$severity" \
        '
        $existing + [
          ({
            source_role: $source_role,
            summary: $summary
          }
          + (if $rule_id == "" then {} else {rule_id: $rule_id} end)
          + (if $severity == "" then {} else {severity: $severity} end))
        ]
        ')"

    printf -v "$target_name" '%s' "$updated"
}

json_length() {
    jq 'length' <<<"$1"
}

record_command_run() {
    local id="$1"
    local command_string="$2"
    local reason="$3"
    local scope_json="$4"

    COMMAND_STRING["$id"]="$command_string"
    COMMAND_REASON["$id"]="$reason"
    COMMAND_SCOPE_JSON["$id"]="$scope_json"
}

record_command_result() {
    local id="$1"
    local status="$2"
    local exit_code="${3-}"
    local summary="${4-}"
    local attribution="${5-}"

    RESULT_STATUS["$id"]="$status"
    if [ -n "$exit_code" ]; then
        RESULT_EXIT_CODE["$id"]="$exit_code"
    else
        unset "RESULT_EXIT_CODE[$id]" 2>/dev/null || true
    fi

    if [ -n "$summary" ]; then
        RESULT_SUMMARY["$id"]="$summary"
    else
        unset "RESULT_SUMMARY[$id]" 2>/dev/null || true
    fi

    if [ -n "$attribution" ]; then
        RESULT_ATTRIBUTION["$id"]="$attribution"
    else
        unset "RESULT_ATTRIBUTION[$id]" 2>/dev/null || true
    fi
}

record_not_applicable_command() {
    local id="$1"
    local command_string="$2"
    local reason="$3"
    local scope_json="$4"
    local summary="$5"

    record_command_run "$id" "$command_string" "$reason" "$scope_json"
    record_command_result "$id" "passed" "" "$summary" "verifier"
}

record_blocked_command() {
    local id="$1"
    local command_string="$2"
    local reason="$3"
    local scope_json="$4"
    local summary="$5"

    record_command_run "$id" "$command_string" "$reason" "$scope_json"
    record_command_result "$id" "failed" "" "$summary" "main-orchestrator"
}

run_single_command() {
    local id="$1"
    local reason="$2"
    local scope_json="$3"
    shift 3
    local -a cmd=("$@")
    local command_string
    local exit_code

    command_string="$(shell_join "${cmd[@]}")"
    record_command_run "$id" "$command_string" "$reason" "$scope_json"

    set +e
    "${cmd[@]}"
    exit_code=$?
    set -e

    if [ "$exit_code" -eq 0 ]; then
        record_command_result "$id" "passed" "$exit_code" "command succeeded" "verifier"
        return
    fi

    verification_failed=1
    record_command_result "$id" "failed" "$exit_code" "command failed" "verifier"
    append_finding blocking_findings_json "verifier" "verification command failed: $id" "$id" "error"
}

run_looped_command() {
    local id="$1"
    local reason="$2"
    local scope_json="$3"
    local subcommand_label="$4"
    shift 4
    local -a scope=("$@")
    local -a command_strings=()
    local item
    local exit_code=0
    local loop_exit

    for item in "${scope[@]}"; do
        local command_string
        command_string="$(shell_join "$subcommand_label" "$item")"
        command_strings+=("$command_string")
        set +e
        case "$id" in
            targeted_tests)
                forge test --match-path "$item"
                ;;
            node_syntax_changed_js)
                node --check "$item"
                ;;
            *)
                die "unsupported looped command id: $id"
                ;;
        esac
        loop_exit=$?
        set -e

        if [ "$loop_exit" -ne 0 ] && [ "$exit_code" -eq 0 ]; then
            exit_code="$loop_exit"
        fi
    done

    record_command_run "$id" "$(IFS=' && '; printf '%s' "${command_strings[*]}")" "$reason" "$scope_json"

    if [ "$exit_code" -eq 0 ]; then
        record_command_result "$id" "passed" "0" "all scoped commands succeeded" "verifier"
        return
    fi

    verification_failed=1
    record_command_result "$id" "failed" "$exit_code" "at least one scoped command failed" "verifier"
    append_finding blocking_findings_json "verifier" "verification command failed: $id" "$id" "error"
}

match_path_against_patterns() {
    local candidate="$1"
    shift
    local pattern

    for pattern in "$@"; do
        if [[ "$candidate" =~ $pattern ]]; then
            return 0
        fi
    done

    return 1
}

resolve_run_record_path() {
    local default_dir
    local template
    local timestamp
    local relative_path

    if [ -n "$emit_run_record" ]; then
        case "$emit_run_record" in
            /*) printf '%s' "$emit_run_record" ;;
            *) printf '%s/%s' "$repo_root" "$emit_run_record" ;;
        esac
        return
    fi

    default_dir="$(jq -r '.run_record.default_output_dir' "$policy_file")"
    template="$(jq -r '.run_record.file_name_template' "$policy_file")"
    timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
    relative_path="${template//\{timestamp\}/$timestamp}"
    relative_path="${relative_path//\{profile\}/$profile}"

    printf '%s/%s/%s' "$repo_root" "$default_dir" "$relative_path"
}

resolve_harness_schema_root() {
    local -a candidates=()
    local candidate

    candidates+=("${repo_root}/.harness")
    if [ -n "${SOLIDITY_SUBAGENT_HARNESS_ROOT:-}" ]; then
        candidates+=("${SOLIDITY_SUBAGENT_HARNESS_ROOT}")
    fi
    if [ -n "${CODEX_HOME:-}" ]; then
        candidates+=("${CODEX_HOME}/skills/solidity-subagent-harness")
    fi
    candidates+=("${HOME}/.codex/skills/solidity-subagent-harness")

    for candidate in "${candidates[@]}"; do
        if [ -f "$candidate/schemas/policy.schema.json" ] && [ -f "$candidate/schemas/run-record.schema.json" ]; then
            printf '%s' "$candidate"
            return
        fi
    done

    die "unable to locate solidity-subagent-harness schemas"
}

resolve_schema_path() {
    local schema_value="$1"

    case "$schema_value" in
        /*) printf '%s' "$schema_value" ;;
        *) printf '%s/%s' "$harness_schema_root" "$schema_value" ;;
    esac
}

validate_json_file_against_schema() {
    local instance_file="$1"
    local schema_file="$2"

    python3 - "$instance_file" "$schema_file" <<'PY'
import json
import pathlib
import sys

from jsonschema import Draft202012Validator, RefResolver

instance_path = pathlib.Path(sys.argv[1]).resolve()
schema_path = pathlib.Path(sys.argv[2]).resolve()

with schema_path.open("r", encoding="utf-8") as fh:
    schema = json.load(fh)
with instance_path.open("r", encoding="utf-8") as fh:
    instance = json.load(fh)

store = {}
policy_schema_path = schema_path.parent / "policy.schema.json"
if policy_schema_path.exists():
    with policy_schema_path.open("r", encoding="utf-8") as fh:
        policy_schema = json.load(fh)
    store["policy.schema.json"] = policy_schema
    store[str(policy_schema_path)] = policy_schema
    store[policy_schema_path.as_uri()] = policy_schema
    if "$id" in policy_schema:
        store[policy_schema["$id"]] = policy_schema

resolver = RefResolver(base_uri=schema_path.as_uri(), referrer=schema, store=store)
validator = Draft202012Validator(schema, resolver=resolver)
errors = sorted(validator.iter_errors(instance), key=lambda error: list(error.path))

if errors:
    for error in errors:
        path = ".".join(str(part) for part in error.path) or "<root>"
        print(f"{path}: {error.message}", file=sys.stderr)
    sys.exit(1)
PY
}

validate_json_string_against_schema() {
    local instance_json="$1"
    local schema_file="$2"

    INSTANCE_JSON="$instance_json" python3 - "$schema_file" <<'PY'
import json
import os
import pathlib
import sys

from jsonschema import Draft202012Validator, RefResolver

schema_path = pathlib.Path(sys.argv[1]).resolve()
instance = json.loads(os.environ["INSTANCE_JSON"])
with schema_path.open("r", encoding="utf-8") as fh:
    schema = json.load(fh)

store = {}
policy_schema_path = schema_path.parent / "policy.schema.json"
if policy_schema_path.exists():
    with policy_schema_path.open("r", encoding="utf-8") as fh:
        policy_schema = json.load(fh)
    store["policy.schema.json"] = policy_schema
    store[str(policy_schema_path)] = policy_schema
    store[policy_schema_path.as_uri()] = policy_schema
    if "$id" in policy_schema:
        store[policy_schema["$id"]] = policy_schema

resolver = RefResolver(base_uri=schema_path.as_uri(), referrer=schema, store=store)
validator = Draft202012Validator(schema, resolver=resolver)
errors = sorted(validator.iter_errors(instance), key=lambda error: list(error.path))

if errors:
    for error in errors:
        path = ".".join(str(part) for part in error.path) or "<root>"
        print(f"{path}: {error.message}", file=sys.stderr)
    sys.exit(1)
PY
}

diff_covers_changed_files() {
    local diff_file="$1"
    shift

    python3 - "$diff_file" "$@" <<'PY'
import pathlib
import re
import sys

diff_path = pathlib.Path(sys.argv[1])
expected = set(sys.argv[2:])

if not expected:
    sys.exit(0)
if not diff_path.is_file():
    sys.exit(1)

covered = set()
pattern = re.compile(r"^diff --git a/(.+?) b/(.+)$")

with diff_path.open("r", encoding="utf-8", errors="replace") as fh:
    for raw_line in fh:
        match = pattern.match(raw_line.rstrip("\n"))
        if not match:
            continue
        covered.add(match.group(1))
        covered.add(match.group(2))

missing = expected - covered
sys.exit(0 if not missing else 1)
PY
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --profile)
            if [ "$#" -lt 2 ]; then
                usage
                exit 1
            fi
            profile="$2"
            shift 2
            ;;
        --changed-files)
            if [ "$#" -lt 2 ]; then
                usage
                exit 1
            fi
            changed_files_arg="$2"
            shift 2
            ;;
        --emit-run-record)
            if [ "$#" -lt 2 ]; then
                usage
                exit 1
            fi
            emit_run_record="$2"
            shift 2
            ;;
        --fail-on-legacy)
            fail_on_legacy=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage
            die "unknown argument: $1"
            ;;
    esac
done

case "$profile" in
    fast|full|ci) ;;
    *)
        die "--profile must be one of: fast, full, ci"
        ;;
esac

command -v jq >/dev/null 2>&1 || die "jq is required"
command -v node >/dev/null 2>&1 || die "node is required"

original_cwd="$(pwd)"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
cd "$repo_root"

harness_schema_root="$(resolve_harness_schema_root)"
policy_file="$repo_root/.harness/policy.json"
[ -f "$policy_file" ] || die "missing policy file: $policy_file"
policy_schema_file="$harness_schema_root/schemas/policy.schema.json"

if ! validate_json_file_against_schema "$policy_file" "$policy_schema_file"; then
    die "policy schema validation failed"
fi

run_record_schema_file="$(resolve_schema_path "$(jq -r '.run_record.schema' "$policy_file")")"
[ -f "$run_record_schema_file" ] || die "run-record schema not found: $run_record_schema_file"

mapfile -t solidity_prod_patterns < <(jq -r '.surfaces.solidity_prod[]' "$policy_file")
mapfile -t solidity_test_patterns < <(jq -r '.surfaces.solidity_test[]' "$policy_file")
mapfile -t harness_control_patterns < <(jq -r '.surfaces.harness_control[]' "$policy_file")
mapfile -t high_risk_path_patterns < <(jq -r '.risk_rules.high_risk_paths[]' "$policy_file")
mapfile -t high_risk_token_patterns < <(jq -r '.risk_rules.high_risk_tokens[]? // empty' "$policy_file")

if [ -n "$changed_files_arg" ]; then
    case "$changed_files_arg" in
        /*) ;;
        *) changed_files_arg="$original_cwd/$changed_files_arg" ;;
    esac
    [ -f "$changed_files_arg" ] || die "changed files input not found: $changed_files_arg"
    mapfile -t changed_files < <(awk '{ sub(/\r$/, ""); if ($0 != "") print $0 }' "$changed_files_arg" | awk '!seen[$0]++')
elif [ "$profile" = "ci" ]; then
    die "--changed-files is required when --profile ci is used"
else
    mapfile -t changed_files < <(git diff --cached --name-only --diff-filter=ACMRD | awk '{ sub(/\r$/, ""); if ($0 != "") print $0 }' | awk '!seen[$0]++')
fi

declare -a selected_surfaces=()
declare -a unmatched_files=()
declare -a solidity_prod_files=()
declare -a solidity_test_files=()
declare -a harness_control_files=()
declare -a shell_files=()
declare -a js_files=()
declare -a package_trigger_files=()
declare -a existing_solidity_files=()
declare -a existing_src_solidity_files=()
declare -a existing_src_or_script_solidity_files=()
declare -a existing_test_solidity_files=()
declare -a existing_shell_files=()
declare -a existing_js_files=()
declare -a classification_solidity_files=()

for changed_file in "${changed_files[@]}"; do
    matched=0

    if match_path_against_patterns "$changed_file" "${solidity_prod_patterns[@]}"; then
        append_unique solidity_prod_files "$changed_file"
        append_unique selected_surfaces "solidity_prod"
        matched=1
        if [ -f "$changed_file" ]; then
            append_unique existing_solidity_files "$changed_file"
            append_unique existing_src_or_script_solidity_files "$changed_file"
        fi
        if [[ "$changed_file" =~ ^src/.*\.sol$ ]] && [ -f "$changed_file" ]; then
            append_unique existing_src_solidity_files "$changed_file"
        fi
    fi

    if match_path_against_patterns "$changed_file" "${solidity_test_patterns[@]}"; then
        append_unique solidity_test_files "$changed_file"
        append_unique selected_surfaces "solidity_test"
        matched=1
        if [ -f "$changed_file" ]; then
            append_unique existing_solidity_files "$changed_file"
            append_unique existing_test_solidity_files "$changed_file"
        fi
    fi

    if match_path_against_patterns "$changed_file" "${harness_control_patterns[@]}"; then
        append_unique harness_control_files "$changed_file"
        append_unique selected_surfaces "harness_control"
        matched=1
    fi

    if [ "$matched" -eq 0 ]; then
        append_unique unmatched_files "$changed_file"
    fi

    case "$changed_file" in
        *.sh|.githooks/*)
            if [ -f "$changed_file" ]; then
                append_unique shell_files "$changed_file"
                append_unique existing_shell_files "$changed_file"
            fi
            ;;
    esac

    case "$changed_file" in
        *.js|*.cjs|*.mjs)
            if [ -f "$changed_file" ]; then
                append_unique js_files "$changed_file"
                append_unique existing_js_files "$changed_file"
            fi
            ;;
    esac

    case "$changed_file" in
        package.json|package-lock.json|npm-shrinkwrap.json)
            append_unique package_trigger_files "$changed_file"
            ;;
    esac
done

selected_solidity_json="$(json_array_from_values "${existing_solidity_files[@]}")"
solidity_prod_json="$(json_array_from_values "${solidity_prod_files[@]}")"
solidity_test_json="$(json_array_from_values "${solidity_test_files[@]}")"
high_risk_paths_json="$(json_array_from_values "${high_risk_path_patterns[@]}")"
high_risk_tokens_json="$(json_array_from_values "${high_risk_token_patterns[@]}")"

for classification_solidity_file in "${solidity_prod_files[@]}" "${solidity_test_files[@]}"; do
    append_unique classification_solidity_files "$classification_solidity_file"
done

declare -a selected_writer_roles=()
for selected_surface in "${selected_surfaces[@]}"; do
    selected_surface_writer_role="$(jq -r --arg surface "$selected_surface" '.write_roles[$surface]' "$policy_file")"
    if [ "$selected_surface_writer_role" != "null" ] && [ -n "$selected_surface_writer_role" ]; then
        append_unique selected_writer_roles "$selected_surface_writer_role"
    fi
done

patch_file="$(mktemp)"
register_cleanup "$patch_file"
classification_requires_diff=0
diff_evidence_error=0

if [ "${#classification_solidity_files[@]}" -gt 0 ]; then
    if [ -n "$changed_files_arg" ]; then
        if [ -n "${CHANGE_CLASSIFIER_DIFF_FILE:-}" ]; then
            if [ ! -r "${CHANGE_CLASSIFIER_DIFF_FILE}" ]; then
                diff_evidence_error=1
            else
                cp "${CHANGE_CLASSIFIER_DIFF_FILE}" "$patch_file"
                if [ ! -s "$patch_file" ]; then
                    diff_evidence_error=1
                elif ! diff_covers_changed_files "$patch_file" "${classification_solidity_files[@]}"; then
                    diff_evidence_error=1
                fi
            fi
        elif [ -n "${GATE_DIFF_BASE:-}" ]; then
            if ! git diff --unified=0 "${GATE_DIFF_BASE}" "${GATE_DIFF_HEAD:-HEAD}" -- "${classification_solidity_files[@]}" >"$patch_file"; then
                diff_evidence_error=1
            elif [ ! -s "$patch_file" ]; then
                diff_evidence_error=1
            fi
        else
            classification_requires_diff=1
            : >"$patch_file"
        fi
    else
        if [ -n "${CHANGE_CLASSIFIER_DIFF_FILE:-}" ] && [ -r "${CHANGE_CLASSIFIER_DIFF_FILE}" ]; then
            cp "${CHANGE_CLASSIFIER_DIFF_FILE}" "$patch_file"
        else
            git diff --cached --unified=0 -- "${classification_solidity_files[@]}" >"$patch_file" || true
        fi
    fi
else
    : >"$patch_file"
fi

blocking_findings_json='[]'
residual_risks_json='[]'
hard_blocked=0
verification_failed=0

if [ "${#selected_writer_roles[@]}" -gt 1 ]; then
    hard_blocked=1
    append_finding blocking_findings_json "main-orchestrator" "changed surfaces resolve to multiple writer roles: ${selected_writer_roles[*]}" "writer-role-conflict" "error"
fi

while IFS= read -r hard_block_rule; do
    [ -n "$hard_block_rule" ] || continue

    hard_block_rule_id="$(jq -r '.id' <<<"$hard_block_rule")"
    hard_block_rule_message="$(jq -r '.message' <<<"$hard_block_rule")"
    rule_matched=0

    if jq -e '.mixed_surface_sets? != null' >/dev/null <<<"$hard_block_rule"; then
        while IFS= read -r mixed_surface_set_json; do
            [ -n "$mixed_surface_set_json" ] || continue
            mixed_surface_match=1
            mapfile -t mixed_surface_set < <(jq -r '.[]' <<<"$mixed_surface_set_json")
            for mixed_surface in "${mixed_surface_set[@]}"; do
                if ! array_contains "$mixed_surface" "${selected_surfaces[@]}"; then
                    mixed_surface_match=0
                    break
                fi
            done
            if [ "$mixed_surface_match" -eq 1 ]; then
                hard_blocked=1
                rule_matched=1
                append_finding blocking_findings_json "main-orchestrator" "$hard_block_rule_message" "$hard_block_rule_id" "error"
                break
            fi
        done < <(jq -c '.mixed_surface_sets[]?' <<<"$hard_block_rule")
    fi

    if jq -e '.paths? != null and .tokens? == null' >/dev/null <<<"$hard_block_rule"; then
        mapfile -t hard_block_paths < <(jq -r '.paths[]' <<<"$hard_block_rule")
        for changed_file in "${changed_files[@]}"; do
            if match_path_against_patterns "$changed_file" "${hard_block_paths[@]}"; then
                hard_blocked=1
                rule_matched=1
                append_finding blocking_findings_json "main-orchestrator" "$hard_block_rule_message: $changed_file" "$hard_block_rule_id" "error"
                break
            fi
        done
    fi

    if jq -e '.surfaces? != null' >/dev/null <<<"$hard_block_rule"; then
        mapfile -t hard_block_surfaces < <(jq -r '.surfaces[]' <<<"$hard_block_rule")
        for hard_block_surface in "${hard_block_surfaces[@]}"; do
            if array_contains "$hard_block_surface" "${selected_surfaces[@]}"; then
                hard_blocked=1
                rule_matched=1
                append_finding blocking_findings_json "main-orchestrator" "$hard_block_rule_message: $hard_block_surface" "$hard_block_rule_id" "error"
                break
            fi
        done
    fi

    if jq -e '.writer_roles? != null' >/dev/null <<<"$hard_block_rule"; then
        mapfile -t hard_block_writer_roles < <(jq -r '.writer_roles[]' <<<"$hard_block_rule")
        for hard_block_writer_role in "${hard_block_writer_roles[@]}"; do
            if array_contains "$hard_block_writer_role" "${selected_writer_roles[@]}"; then
                hard_blocked=1
                rule_matched=1
                append_finding blocking_findings_json "main-orchestrator" "$hard_block_rule_message: $hard_block_writer_role" "$hard_block_rule_id" "error"
                break
            fi
        done
    fi

    if [ "$fail_on_legacy" -eq 1 ] && jq -e '.tokens? != null' >/dev/null <<<"$hard_block_rule"; then
        mapfile -t retained_harness_files < <(jq -r '.retained_harness_files[]' "$policy_file")
        mapfile -t hard_block_token_patterns < <(jq -r '.tokens[]' <<<"$hard_block_rule")
        mapfile -t hard_block_scan_paths < <(jq -r '.paths[]? // empty' <<<"$hard_block_rule")

        for retained_harness_file in "${retained_harness_files[@]}"; do
            [ -f "$retained_harness_file" ] || continue
            if [ "${#hard_block_scan_paths[@]}" -gt 0 ] && ! match_path_against_patterns "$retained_harness_file" "${hard_block_scan_paths[@]}"; then
                continue
            fi

            for hard_block_token_pattern in "${hard_block_token_patterns[@]}"; do
                if grep -qiE "$hard_block_token_pattern" "$retained_harness_file"; then
                    hard_blocked=1
                    rule_matched=1
                    append_finding blocking_findings_json "main-orchestrator" "$hard_block_rule_message: $retained_harness_file matched /$hard_block_token_pattern/" "$hard_block_rule_id" "error"
                    break 2
                fi
            done
        done
    fi
done < <(jq -c '.hard_blocks[]' "$policy_file")

if [ -n "$changed_files_arg" ] && { [ "${#solidity_prod_files[@]}" -gt 0 ] || [ "${#solidity_test_files[@]}" -gt 0 ]; } && [ "$classification_requires_diff" -eq 1 ]; then
    classification_requires_diff=1
    hard_blocked=1
    append_finding blocking_findings_json "main-orchestrator" "changed-files mode for Solidity changes requires CHANGE_CLASSIFIER_DIFF_FILE or GATE_DIFF_BASE to classify non-semantic diffs deterministically" "semantic-classification-requires-diff" "error"
fi

if [ -n "$changed_files_arg" ] && { [ "${#solidity_prod_files[@]}" -gt 0 ] || [ "${#solidity_test_files[@]}" -gt 0 ]; } && [ "$diff_evidence_error" -eq 1 ]; then
    hard_blocked=1
    append_finding blocking_findings_json "main-orchestrator" "changed-files mode provided unusable diff evidence for Solidity classification" "semantic-classification-diff-unusable" "error"
fi

classification_json="$(
    PROD_FILES_JSON="$solidity_prod_json" \
    TEST_FILES_JSON="$solidity_test_json" \
    HIGH_RISK_PATHS_JSON="$high_risk_paths_json" \
    HIGH_RISK_TOKENS_JSON="$high_risk_tokens_json" \
    PATCH_FILE="$patch_file" \
    node <<'EOF'
const fs = require('fs');

const prodFiles = JSON.parse(process.env.PROD_FILES_JSON || '[]');
const testFiles = JSON.parse(process.env.TEST_FILES_JSON || '[]');
const highRiskPaths = JSON.parse(process.env.HIGH_RISK_PATHS_JSON || '[]');
const highRiskTokens = JSON.parse(process.env.HIGH_RISK_TOKENS_JSON || '[]');
const patchPath = process.env.PATCH_FILE || '';
const patch = patchPath && fs.existsSync(patchPath) ? fs.readFileSync(patchPath, 'utf8') : '';
const trackedFiles = [...prodFiles, ...testFiles];

function isCommentLine(line) {
  return /^\/\//.test(line) || /^\/\*/.test(line) || /^\*/.test(line) || /^\*\//.test(line) || /^SPDX-License-Identifier:/i.test(line);
}

function isPunctuationOnly(line) {
  return line.replace(/[{}\[\]();,]/g, '').trim() === '';
}

function isNonSemanticLine(line) {
  const trimmed = line.trim();
  return trimmed === '' || isCommentLine(trimmed) || isPunctuationOnly(trimmed);
}

const analysis = new Map(trackedFiles.map((file) => [file, { semantic: false, tokenHits: new Set() }]));

if (patch !== '') {
  let currentFile = null;
  for (const rawLine of patch.split(/\r?\n/)) {
    if (rawLine.startsWith('diff --git ')) {
      const match = /^diff --git a\/(.+?) b\/(.+)$/.exec(rawLine);
      currentFile = match ? match[2] : null;
      continue;
    }
    if (rawLine.startsWith('+++ b/')) {
      currentFile = rawLine.slice('+++ b/'.length).trim();
      continue;
    }
    if (!currentFile || !analysis.has(currentFile)) continue;
    if (rawLine.startsWith('+++') || rawLine.startsWith('---') || rawLine.startsWith('@@')) continue;
    if (!(rawLine.startsWith('+') || rawLine.startsWith('-'))) continue;
    const content = rawLine.slice(1).trim();
    if (isNonSemanticLine(content)) continue;
    const fileEntry = analysis.get(currentFile);
    fileEntry.semantic = true;
    for (const tokenPattern of highRiskTokens) {
      const regex = new RegExp(tokenPattern, 'i');
      if (regex.test(content)) {
        fileEntry.tokenHits.add(tokenPattern);
      }
    }
  }
}

const semanticProdFiles = prodFiles.filter((file) => analysis.get(file)?.semantic);
const semanticTestFiles = testFiles.filter((file) => analysis.get(file)?.semantic);
const nonSemanticProdFiles = prodFiles.filter((file) => !analysis.get(file)?.semantic);
const nonSemanticTestFiles = testFiles.filter((file) => !analysis.get(file)?.semantic);
const highRiskReasons = [];

for (const file of semanticProdFiles) {
  for (const pattern of highRiskPaths) {
    if (new RegExp(pattern).test(file)) {
      highRiskReasons.push(`path:${file}~/${pattern}/`);
    }
  }
  const entry = analysis.get(file);
  if (!entry) continue;
  for (const tokenPattern of entry.tokenHits) {
    highRiskReasons.push(`token:${file}~/${tokenPattern}/`);
  }
}

let riskTier = 'none';
if (semanticProdFiles.length > 0) {
  riskTier = highRiskReasons.length > 0 ? 'high-risk' : 'prod-semantic';
} else if (semanticTestFiles.length > 0) {
  riskTier = 'test-semantic';
} else if (trackedFiles.length > 0) {
  riskTier = 'non-semantic';
}

process.stdout.write(JSON.stringify({
  risk_tier: riskTier,
  semantic_prod_files: semanticProdFiles,
  semantic_test_files: semanticTestFiles,
  non_semantic_prod_files: nonSemanticProdFiles,
  non_semantic_test_files: nonSemanticTestFiles,
  high_risk_reasons: highRiskReasons
}));
EOF
)"

risk_tier="$(jq -r '.risk_tier' <<<"$classification_json")"

if [ "$classification_requires_diff" -eq 1 ]; then
    if [ "${#solidity_prod_files[@]}" -gt 0 ]; then
        fallback_high_risk=0
        for solidity_prod_file in "${solidity_prod_files[@]}"; do
            if match_path_against_patterns "$solidity_prod_file" "${high_risk_path_patterns[@]}"; then
                fallback_high_risk=1
                break
            fi
        done

        if [ "$fallback_high_risk" -eq 1 ]; then
            risk_tier="high-risk"
        else
            risk_tier="prod-semantic"
        fi
    elif [ "${#solidity_test_files[@]}" -gt 0 ]; then
        risk_tier="test-semantic"
    fi
fi

while IFS= read -r testing_gap; do
    [ -n "$testing_gap" ] || continue

    testing_gap_id="$(jq -r '.id' <<<"$testing_gap")"
    testing_gap_status="$(jq -r '.status' <<<"$testing_gap")"
    testing_gap_enforcement="$(jq -r '.enforcement' <<<"$testing_gap")"
    mapfile -t testing_gap_paths < <(jq -r '.paths[]' <<<"$testing_gap")

    gap_hit=0
    for changed_file in "${changed_files[@]}"; do
        for testing_gap_path in "${testing_gap_paths[@]}"; do
            if [ "$changed_file" = "$testing_gap_path" ]; then
                gap_hit=1
                break
            fi
        done
        [ "$gap_hit" -eq 1 ] && break
    done

    [ "$gap_hit" -eq 1 ] || continue

    if [ "$testing_gap_enforcement" = "risk-upgrade" ] && [ "$risk_tier" != "none" ]; then
        risk_tier="high-risk"
    fi

    if [ "$testing_gap_enforcement" = "residual-risk" ]; then
        append_finding residual_risks_json "verifier" "testing gap '$testing_gap_id' applies ($testing_gap_status)" "$testing_gap_id" "medium"
    fi
done < <(jq -cr '.testing_gaps | to_entries[]? | .value[]?' "$policy_file")

if [ "$risk_tier" = "none" ] && [[ " ${selected_surfaces[*]:-} " == *" harness_control "* ]]; then
    risk_tier="non-semantic"
fi

if [ "${#unmatched_files[@]}" -gt 0 ]; then
    hard_blocked=1
    append_finding blocking_findings_json "main-orchestrator" "changed files do not match configured policy surfaces: ${unmatched_files[*]}" "unclassified-paths" "error"
fi

writer_role="none"
if [ "$hard_blocked" -eq 0 ] && [ "${#selected_writer_roles[@]}" -eq 1 ]; then
    writer_role="${selected_writer_roles[0]}"
fi

if [ "${#changed_files[@]}" -eq 0 ] && [ "$hard_blocked" -eq 0 ]; then
    surface_json='"no-op"'
    risk_tier="none"
    writer_role="none"
    verification_profile="none"
    selected_review_roles_json='[]'
else
    if [ "${#selected_surfaces[@]}" -eq 1 ]; then
        surface_json="$(jq -cn --arg surface "${selected_surfaces[0]}" '$surface')"
    elif [ "${#selected_surfaces[@]}" -gt 1 ]; then
        surface_json="$(json_array_from_values "${selected_surfaces[@]}")"
    else
        surface_json='"no-op"'
    fi

    verification_profile="$profile"

    if [ "$hard_blocked" -eq 0 ] && [[ " ${selected_surfaces[*]:-} " == *" solidity_prod "* || " ${selected_surfaces[*]:-} " == *" solidity_test "* ]]; then
        mapfile -t review_matrix_roles < <(jq -r --arg tier "$risk_tier" '.review_matrix[$tier][]? // empty' "$policy_file")
        declare -a selected_review_roles=()
        for review_role in "${review_matrix_roles[@]}"; do
            append_unique selected_review_roles "$review_role"
        done
        selected_review_roles_json="$(json_array_from_values "${selected_review_roles[@]}")"
    else
        selected_review_roles_json='[]'
    fi
fi

declare -a targeted_test_files=()
if [ "$verification_profile" = "fast" ] && [ "$hard_blocked" -eq 0 ]; then
    for changed_test_file in "${solidity_test_files[@]}"; do
        if [ -f "$changed_test_file" ]; then
            append_unique targeted_test_files "$changed_test_file"
        fi
    done

    while IFS= read -r test_mapping_rule; do
        [ -n "$test_mapping_rule" ] || continue
        mapfile -t test_mapping_rule_paths < <(jq -r '.paths[]' <<<"$test_mapping_rule")
        rule_matches_prod=0

        for prod_file in "${solidity_prod_files[@]}"; do
            if match_path_against_patterns "$prod_file" "${test_mapping_rule_paths[@]}"; then
                rule_matches_prod=1
                break
            fi
        done

        [ "$rule_matches_prod" -eq 1 ] || continue

        mapping_entry_key="$(jq -r '.key' <<<"$test_mapping_rule")"
        rule_id="$(jq -r '.id' <<<"$test_mapping_rule")"
        mapfile -t mapped_tests < <(jq -r --arg key "$mapping_entry_key" --arg rule_id "$rule_id" '
            (
              (.test_mapping[$key].tests // [])
              + (.test_mapping[$key].rules[]? | select(.id == $rule_id) | .change_tests)
              + (.test_mapping[$key].rules[]? | select(.id == $rule_id) | .evidence_tests)
            )[]' "$policy_file")
        for mapped_test in "${mapped_tests[@]}"; do
            if [ -f "$mapped_test" ]; then
                append_unique targeted_test_files "$mapped_test"
            fi
        done
    done < <(jq -c '.test_mapping | to_entries[] | . as $entry | $entry.value.rules[]? | . + {key: $entry.key}' "$policy_file")
fi

declare -A COMMAND_STRING=()
declare -A COMMAND_REASON=()
declare -A COMMAND_SCOPE_JSON=()
declare -A RESULT_STATUS=()
declare -A RESULT_EXIT_CODE=()
declare -A RESULT_SUMMARY=()
declare -A RESULT_ATTRIBUTION=()

if [ "$verification_profile" = "none" ]; then
    required_command_ids=()
    profile_required_commands_json='[]'
else
    mapfile -t required_command_ids < <(jq -r --arg profile "$verification_profile" '.verification_profiles[$profile].required_commands[]' "$policy_file")
    profile_required_commands_json="$(json_array_from_values "${required_command_ids[@]}")"
fi

if [ "${#changed_files[@]}" -gt 0 ]; then
    for command_id in "${required_command_ids[@]}"; do
        case "$command_id" in
            fmt_changed_solidity)
                if [ "$hard_blocked" -eq 1 ]; then
                    record_blocked_command "$command_id" "forge fmt --check $(shell_join "${existing_solidity_files[@]}")" "format check selected Solidity files" "$selected_solidity_json" "command blocked before execution by policy hard-block"
                elif [ "${#existing_solidity_files[@]}" -gt 0 ]; then
                    run_single_command "$command_id" "format check selected Solidity files" "$selected_solidity_json" forge fmt --check "${existing_solidity_files[@]}"
                else
                    record_not_applicable_command "$command_id" "forge fmt --check" "format check selected Solidity files" "$selected_solidity_json" "no Solidity files in scope"
                fi
                ;;
            lint_changed_solidity)
                src_or_script_scope_json="$(json_array_from_values "${existing_src_or_script_solidity_files[@]}")"
                test_scope_json="$(json_array_from_values "${existing_test_solidity_files[@]}")"
                if [ "$hard_blocked" -eq 1 ]; then
                    record_blocked_command "$command_id" "npx solhint -c solhint.config.js <src-or-script-solidity> && npx solhint -c solhint-test.config.js <test-solidity>" "lint selected Solidity files" "$selected_solidity_json" "command blocked before execution by policy hard-block"
                elif [ "${#existing_src_or_script_solidity_files[@]}" -gt 0 ]; then
                    lint_command="npx solhint -c solhint.config.js $(shell_join "${existing_src_or_script_solidity_files[@]}")"
                    if [ "${#existing_test_solidity_files[@]}" -gt 0 ]; then
                        lint_command="$lint_command && npx solhint -c solhint-test.config.js $(shell_join "${existing_test_solidity_files[@]}")"
                        lint_scope_json="$(jq -cn --argjson src "$src_or_script_scope_json" --argjson test "$test_scope_json" '$src + $test')"
                    else
                        lint_scope_json="$src_or_script_scope_json"
                    fi
                    run_single_command "$command_id" "lint selected Solidity files" "$lint_scope_json" bash -lc "$lint_command"
                elif [ "${#existing_test_solidity_files[@]}" -gt 0 ]; then
                    run_single_command "$command_id" "lint selected Solidity files" "$test_scope_json" npx solhint -c solhint-test.config.js "${existing_test_solidity_files[@]}"
                else
                    record_not_applicable_command "$command_id" "npx solhint -c solhint.config.js && npx solhint -c solhint-test.config.js" "lint selected Solidity files" "$selected_solidity_json" "no Solidity files in scope"
                fi
                ;;
            forge_build)
                if [ "$hard_blocked" -eq 1 ]; then
                    record_blocked_command "$command_id" "forge build" "compile the repository" '[]' "command blocked before execution by policy hard-block"
                else
                    run_single_command "$command_id" "compile the repository" '[]' forge build
                fi
                ;;
            targeted_tests)
                targeted_tests_json="$(json_array_from_values "${targeted_test_files[@]}")"
                if [ "$hard_blocked" -eq 1 ]; then
                    record_blocked_command "$command_id" "forge test --match-path <targeted-test>" "run changed and mapped targeted tests" "$targeted_tests_json" "command blocked before execution by policy hard-block"
                elif [ "${#targeted_test_files[@]}" -gt 0 ]; then
                    run_looped_command "$command_id" "run changed and mapped targeted tests" "$targeted_tests_json" "forge test --match-path" "${targeted_test_files[@]}"
                else
                    record_not_applicable_command "$command_id" "forge test --match-path" "run changed and mapped targeted tests" "$targeted_tests_json" "no targeted tests selected"
                fi
                ;;
            forge_test_full)
                if [ "$hard_blocked" -eq 1 ]; then
                    record_blocked_command "$command_id" "forge test -vvv" "run the full Forge test suite" '[]' "command blocked before execution by policy hard-block"
                else
                    run_single_command "$command_id" "run the full Forge test suite" '[]' forge test -vvv
                fi
                ;;
            coverage_when_required)
                if [ "$hard_blocked" -eq 1 ]; then
                    record_blocked_command "$command_id" "forge coverage --report summary" "run coverage for semantic production Solidity changes" '[]' "command blocked before execution by policy hard-block"
                elif [ "$risk_tier" = "prod-semantic" ] || [ "$risk_tier" = "high-risk" ]; then
                    run_single_command "$command_id" "run coverage for semantic production Solidity changes" '[]' forge coverage --report summary
                else
                    record_not_applicable_command "$command_id" "forge coverage --report summary" "run coverage for semantic production Solidity changes" '[]' "coverage not required for current risk tier"
                fi
                ;;
            slither_when_required)
                slither_filter_paths="$(jq -r '.risk_rules.slither_filter_paths // empty' "$policy_file")"
                slither_exclude_detectors="$(jq -r '.risk_rules.slither_exclude_detectors // empty' "$policy_file")"
                src_scope_json="$(json_array_from_values "${existing_src_solidity_files[@]}")"
                if [ "$hard_blocked" -eq 1 ]; then
                    record_blocked_command "$command_id" "slither . --filter-paths \"$slither_filter_paths\" --exclude-dependencies --exclude \"$slither_exclude_detectors\"" "run slither for changed src Solidity production scope" "$src_scope_json" "command blocked before execution by policy hard-block"
                elif [ "${#existing_src_solidity_files[@]}" -gt 0 ] && { [ "$risk_tier" = "prod-semantic" ] || [ "$risk_tier" = "high-risk" ]; }; then
                    run_single_command "$command_id" "run slither for changed src Solidity production scope" "$src_scope_json" slither . --filter-paths "$slither_filter_paths" --exclude-dependencies --exclude "$slither_exclude_detectors"
                else
                    record_not_applicable_command "$command_id" "slither . --filter-paths \"$slither_filter_paths\" --exclude-dependencies --exclude \"$slither_exclude_detectors\"" "run slither for changed src Solidity production scope" "$src_scope_json" "no changed src Solidity files require slither"
                fi
                ;;
            bash_syntax_changed_shell)
                shell_scope_json="$(json_array_from_values "${existing_shell_files[@]}")"
                if [ "$hard_blocked" -eq 1 ]; then
                    record_blocked_command "$command_id" "bash -n $(shell_join "${existing_shell_files[@]}")" "check Bash syntax for changed shell files" "$shell_scope_json" "command blocked before execution by policy hard-block"
                elif [ "${#existing_shell_files[@]}" -gt 0 ]; then
                    run_single_command "$command_id" "check Bash syntax for changed shell files" "$shell_scope_json" bash -n "${existing_shell_files[@]}"
                else
                    record_not_applicable_command "$command_id" "bash -n" "check Bash syntax for changed shell files" "$shell_scope_json" "no changed shell files in scope"
                fi
                ;;
            node_syntax_changed_js)
                js_scope_json="$(json_array_from_values "${existing_js_files[@]}")"
                if [ "$hard_blocked" -eq 1 ]; then
                    record_blocked_command "$command_id" "node --check <changed-js-file>" "check Node syntax for changed JavaScript files" "$js_scope_json" "command blocked before execution by policy hard-block"
                elif [ "${#existing_js_files[@]}" -gt 0 ]; then
                    run_looped_command "$command_id" "check Node syntax for changed JavaScript files" "$js_scope_json" "node --check" "${existing_js_files[@]}"
                else
                    record_not_applicable_command "$command_id" "node --check" "check Node syntax for changed JavaScript files" "$js_scope_json" "no changed JavaScript files in scope"
                fi
                ;;
            npm_ci_when_package_changes)
                package_scope_json="$(json_array_from_values "${package_trigger_files[@]}")"
                if [ "$hard_blocked" -eq 1 ]; then
                    record_blocked_command "$command_id" "npm ci" "refresh npm dependencies when package manifests change" "$package_scope_json" "command blocked before execution by policy hard-block"
                elif [ "${#package_trigger_files[@]}" -gt 0 ]; then
                    run_single_command "$command_id" "refresh npm dependencies when package manifests change" "$package_scope_json" npm ci
                else
                    record_not_applicable_command "$command_id" "npm ci" "refresh npm dependencies when package manifests change" "$package_scope_json" "package manifests unchanged"
                fi
                ;;
            *)
                die "unsupported command id: $command_id"
                ;;
        esac
    done
fi

commands_run_json='{}'
command_results_json='{}'
all_command_ids=(
    fmt_changed_solidity
    lint_changed_solidity
    forge_build
    targeted_tests
    forge_test_full
    coverage_when_required
    slither_when_required
    bash_syntax_changed_shell
    node_syntax_changed_js
    npm_ci_when_package_changes
)

for command_id in "${all_command_ids[@]}"; do
    if [ -n "${COMMAND_STRING[$command_id]:-}" ]; then
        commands_run_json="$(jq -cn \
            --argjson current "$commands_run_json" \
            --arg id "$command_id" \
            --arg command "${COMMAND_STRING[$command_id]}" \
            --arg reason "${COMMAND_REASON[$command_id]:-}" \
            --argjson scope "${COMMAND_SCOPE_JSON[$command_id]:-[]}" \
            '
            $current + {
              ($id): ({
                command: $command
              }
              + (if $reason == "" then {} else {reason: $reason} end)
              + (if ($scope | length) == 0 then {} else {scope: $scope} end))
            }
            ')"
    fi

    if [ -n "${RESULT_STATUS[$command_id]:-}" ]; then
        command_results_json="$(jq -cn \
            --argjson current "$command_results_json" \
            --arg id "$command_id" \
            --arg status "${RESULT_STATUS[$command_id]}" \
            --arg exit_code "${RESULT_EXIT_CODE[$command_id]:-}" \
            --arg summary "${RESULT_SUMMARY[$command_id]:-}" \
            --arg attribution "${RESULT_ATTRIBUTION[$command_id]:-}" \
            '
            $current + {
              ($id): ({
                status: $status
              }
              + (if $exit_code == "" then {} else {exit_code: ($exit_code | tonumber)} end)
              + (if $summary == "" then {} else {summary: $summary} end)
              + (if $attribution == "" then {} else {attribution: $attribution} end))
            }
            ')"
    fi
done

if [ "${#changed_files[@]}" -eq 0 ] && [ "$hard_blocked" -eq 0 ]; then
    final_verdict="no-op"
elif [ "$hard_blocked" -eq 1 ]; then
    final_verdict="blocked"
elif [ "$verification_failed" -eq 1 ]; then
    final_verdict="fail"
else
    final_verdict="pass"
fi

review_roles_json="${selected_review_roles_json:-[]}"

run_id="gate-$(date -u +%Y%m%dT%H%M%SZ)-$$"
changed_files_json="$(json_array_from_values "${changed_files[@]}")"

run_record_json="$(jq -cn \
    --arg run_id "$run_id" \
    --arg repo "$(jq -r '.repo' "$policy_file")" \
    --argjson changed_files "$changed_files_json" \
    --argjson surface "$surface_json" \
    --arg risk_tier "$risk_tier" \
    --arg writer_role "$writer_role" \
    --argjson review_roles "$review_roles_json" \
    --arg verification_profile "$verification_profile" \
    --argjson profile_required_commands "$profile_required_commands_json" \
    --argjson commands_run "$commands_run_json" \
    --argjson command_results "$command_results_json" \
    --argjson blocking_findings "$blocking_findings_json" \
    --argjson residual_risks "$residual_risks_json" \
    --arg final_verdict "$final_verdict" \
    '
    {
      run_id: $run_id,
      repo: $repo,
      changed_files: $changed_files,
      surface: $surface,
      risk_tier: $risk_tier,
      writer_role: $writer_role,
      review_roles: $review_roles,
      verification_profile: $verification_profile,
      profile_required_commands: $profile_required_commands,
      commands_run: $commands_run,
      command_results: $command_results,
      delegated_remediations: [],
      blocking_findings: $blocking_findings,
      residual_risks: $residual_risks,
      final_verdict: $final_verdict
    }
    ')"

if ! validate_json_string_against_schema "$run_record_json" "$run_record_schema_file"; then
    die "assembled run record failed schema validation"
fi

should_emit_run_record=1
if [ "$final_verdict" = "no-op" ] && [ -z "$emit_run_record" ]; then
    emit_on_noop="$(jq -r '.run_record.emit_on_noop // false' "$policy_file")"
    if [ "$emit_on_noop" != "true" ]; then
        should_emit_run_record=0
    fi
fi

run_record_path=""
if [ "$should_emit_run_record" -eq 1 ]; then
    run_record_path="$(resolve_run_record_path)"
    mkdir -p "$(dirname "$run_record_path")"
    printf '%s\n' "$run_record_json" >"$run_record_path"
fi

echo "[gate] profile=$profile verdict=$final_verdict risk=$risk_tier writer=$writer_role"
if [ -n "$run_record_path" ]; then
    echo "[gate] run_record=$run_record_path"
fi

case "$final_verdict" in
    pass|no-op)
        exit 0
        ;;
    fail|blocked)
        exit 1
        ;;
    *)
        die "unexpected final verdict: $final_verdict"
        ;;
esac
