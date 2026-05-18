#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

run_classify() {
    local name="$1"
    local changed_files="$2"
    local diff_file="${3-}"
    local expected_status="${4-0}"
    local record="$tmp_dir/$name.record.json"
    local stdout="$tmp_dir/$name.stdout"
    local status

    set +e
    if [ -n "$diff_file" ]; then
        RUN_RECORD_PATH="$record" CHANGE_CLASSIFIER_DIFF_FILE="$diff_file" \
            bash script/harness/gate.sh --classify-only --changed-files "$changed_files" >"$stdout"
        status=$?
    else
        RUN_RECORD_PATH="$record" \
            bash script/harness/gate.sh --classify-only --changed-files "$changed_files" >"$stdout"
        status=$?
    fi
    set -e

    if [ "$status" -ne "$expected_status" ]; then
        echo "expected classify status $expected_status for $name, got $status" >&2
        return 1
    fi

    jq -e . "$record" >/dev/null
    jq -e . "$stdout" >/dev/null
    printf '%s\n' "$record"
}

run_default_classify_in_scratch_repo() {
    local name="$1"
    local dirty_file="$2"
    local repo="$tmp_dir/$name.repo"
    local record="$tmp_dir/$name.record.json"

    mkdir -p "$repo/script/harness" "$repo/.harness"
    cp script/harness/gate.sh "$repo/script/harness/gate.sh"
    cp -R .harness/policy.json .harness/schemas "$repo/.harness/"
    (
        cd "$repo"
        git init -q
        git config user.email test@example.invalid
        git config user.name "Harness Test"
        git add .
        git commit -q -m baseline
        mkdir -p "$(dirname "$dirty_file")"
        printf 'dirty\n' >"$dirty_file"
        RUN_RECORD_PATH="$record" bash script/harness/gate.sh --classify-only >/dev/null
    )

    jq -e . "$record" >/dev/null
    printf '%s\n' "$record"
}

write_changed_files() {
    local name="$1"
    shift
    local file="$tmp_dir/$name.changed"
    printf '%s\n' "$@" >"$file"
    printf '%s\n' "$file"
}

write_diff() {
    local name="$1"
    local path="$2"
    local removed="$3"
    local added="$4"
    local file="$tmp_dir/$name.diff"
    cat >"$file" <<EOF
diff --git a/$path b/$path
--- a/$path
+++ b/$path
@@ -1 +1 @@
-$removed
+$added
EOF
    printf '%s\n' "$file"
}

run_ci_entrypoint_capture() {
    local name="$1"
    local event_name="$2"
    local base_sha="$3"
    local head_sha="$4"
    local fake_bin="$tmp_dir/$name.bin"
    local capture_dir="$tmp_dir/$name.capture"
    local runner_temp="$tmp_dir/$name.runner"

    mkdir -p "$fake_bin" "$capture_dir" "$runner_temp"

    cat >"$fake_bin/npm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

capture_dir="${HARNESS_CAPTURE_DIR:?}"
printf '%s\n' "$@" >"$capture_dir/argv"
printf '%s' "${CHANGE_CLASSIFIER_DIFF_FILE:-}" >"$capture_dir/diff_path"

changed_files_path=""
prev_arg=""
for arg in "$@"; do
    if [ "$prev_arg" = "--changed-files" ]; then
        changed_files_path="$arg"
        break
    fi
    prev_arg="$arg"
done

printf '%s' "$changed_files_path" >"$capture_dir/changed_files_path"

if [ -n "$changed_files_path" ] && [ -f "$changed_files_path" ]; then
    cp "$changed_files_path" "$capture_dir/changed_files"
fi

if [ -n "${CHANGE_CLASSIFIER_DIFF_FILE:-}" ] && [ -f "${CHANGE_CLASSIFIER_DIFF_FILE}" ]; then
    cp "${CHANGE_CLASSIFIER_DIFF_FILE}" "$capture_dir/diff_file"
fi
EOF
    chmod +x "$fake_bin/npm"

    HARNESS_CAPTURE_DIR="$capture_dir" \
    HARNESS_EVENT_NAME="$event_name" \
    HARNESS_EVENT_BASE_SHA="$base_sha" \
    HARNESS_EVENT_HEAD_SHA="$head_sha" \
    RUNNER_TEMP="$runner_temp" \
    PATH="$fake_bin:$PATH" \
    bash script/harness/ci-gate-entrypoint.sh

    printf '%s\n' "$capture_dir"
}

assert_ci_workflow_expressions() {
    python3 - <<'PY'
import yaml

with open(".github/workflows/test.yml", "r", encoding="utf-8") as fh:
    workflow = yaml.safe_load(fh)

steps = workflow["jobs"]["check"]["steps"]
run_gate_step = next(step for step in steps if step.get("name") == "Run gate:ci")
env = run_gate_step["env"]

assert env["HARNESS_EVENT_NAME"] == "${{ github.event_name }}"
assert env["HARNESS_EVENT_BASE_SHA"] == "${{ github.event_name == 'pull_request' && github.event.pull_request.base.sha || github.event.before }}"
assert env["HARNESS_EVENT_HEAD_SHA"] == "${{ github.sha }}"
assert env["RUN_RECORD_PATH"] == "${{ runner.temp }}/memeversev2-gate-ci.json"
assert run_gate_step["run"] == "bash script/harness/ci-gate-entrypoint.sh"
PY
}

assert_no_removed_fields() {
    local record="$1"
    jq -e '
      (has("risk_tier") | not) and
      (has("high-risk") | not) and
      (has("high_risk_paths") | not) and
      (has("high_risk_tokens") | not) and
      (has("high_risk_reasons") | not) and
      (has("review_matrix") | not) and
      (has("review_triggers") | not)
    ' "$record" >/dev/null
}

docs_changed="$(write_changed_files docs docs/foo.md)"
docs_record="$(run_classify docs "$docs_changed")"
jq -e '
  .change_class == "non-semantic" and
  .orchestration_profile == "delegated" and
  .selected_writer_roles == ["process-implementer"] and
  .selected_review_roles == [] and
  .selected_review_roles_source == "delegated_review_rules"
' "$docs_record" >/dev/null
assert_no_removed_fields "$docs_record"

readme_changed="$(write_changed_files readme README.md)"
readme_record="$(run_classify readme "$readme_changed")"
jq -e '
  .change_class == "non-semantic" and
  .orchestration_profile == "delegated" and
  .candidate_orchestration_profile == "direct" and
  .requires_doc_editorial_attestation == true and
  .selected_writer_roles == ["process-implementer"]
' "$readme_record" >/dev/null
assert_no_removed_fields "$readme_record"

spec_changed="$(write_changed_files spec docs/superpowers/specs/foo.md)"
spec_record="$(run_classify spec "$spec_changed")"
jq -e '
  .orchestration_profile == "delegated" and
  .selected_writer_roles == ["process-implementer"] and
  .selected_review_roles == ["spec-reviewer"] and
  .requires_human_confirmation == true
' "$spec_record" >/dev/null
assert_no_removed_fields "$spec_record"

test_changed="$(write_changed_files testsol test/verse/MemeverseLauncherConfig.t.sol)"
test_diff="$(write_diff testsol test/verse/MemeverseLauncherConfig.t.sol 'uint256 oldValue = 1;' 'uint256 newValue = 2;')"
test_record="$(run_classify testsol "$test_changed" "$test_diff")"
jq -e '
  .change_class == "test-semantic" and
  .orchestration_profile == "direct-review" and
  .selected_writer_roles == ["solidity-implementer"] and
  .selected_review_roles == ["logic-reviewer"]
' "$test_record" >/dev/null
assert_no_removed_fields "$test_record"

src_changed="$(write_changed_files srcsol src/swap/MemeverseSwapRouter.sol)"
src_diff="$(write_diff srcsol src/swap/MemeverseSwapRouter.sol 'uint256 oldAmount = amount;' 'uint256 newAmount = amount + 1;')"
src_record="$(run_classify srcsol "$src_changed" "$src_diff" 1)"
jq -e '
  .change_class == "prod-semantic" and
  .surface_sensitivity == "sensitive" and
  .semantic_escalation == null and
  .requires_main_risk_analysis == true and
  .default_orchestration_profile == "full-review" and
  .candidate_orchestration_profile == "direct-review" and
  .orchestration_profile == "blocked" and
  .final_verdict == "blocked" and
  .selected_writer_roles == ["process-implementer"] and
  .selected_review_roles == ["spec-reviewer"] and
  .selected_review_roles_source == "spec_readiness_gate" and
  .coverage_required_full_ci == true and
  .slither_required_full_ci == true
' "$src_record" >/dev/null
jq -e '
  .repo == "MemeverseV2" and
  .orchestration_decision_state == "pending-main-session-risk-analysis" and
  .risk_analysis_record_required == true and
  .risk_analysis_record == null and
  .doc_editorial_attestation == null and
  .spec_readiness_writer_roles == ["process-implementer"] and
  .spec_readiness_review_roles == ["spec-reviewer"] and
  .requires_human_confirmation == true and
  (.orchestration_reasons | index("spec-readiness-doc-update") != null) and
  (.blocking_findings[] | select(.rule_id == "spec-readiness-doc-update")) and
  (.spec_readiness_required_docs | index("docs/spec/swap/swap-flow.md") != null)
' "$src_record" >/dev/null
assert_no_removed_fields "$src_record"

script_changed="$(write_changed_files scriptsol script/Deploy.s.sol)"
script_diff="$(write_diff scriptsol script/Deploy.s.sol 'uint256 oldAmount = amount;' 'uint256 newAmount = amount + 1;')"
script_record="$(run_classify scriptsol "$script_changed" "$script_diff")"
jq -e '
  .change_class == "prod-semantic" and
  .surface_sensitivity == "sensitive" and
  .requires_main_risk_analysis == true and
  .candidate_orchestration_profile == "direct-review" and
  .selected_writer_roles == ["solidity-implementer"] and
  .coverage_required_full_ci == true and
  .slither_required_full_ci == false
' "$script_record" >/dev/null
assert_no_removed_fields "$script_record"

mixed_changed="$(write_changed_files mixed docs/foo.md src/swap/MemeverseSwapRouter.sol)"
mixed_record="$(run_classify mixed "$mixed_changed" "$src_diff" 1)"
jq -e '
  .orchestration_profile == "blocked" and
  .final_verdict == "blocked" and
  .structural_escalation == true and
  (.orchestration_reasons | index("mixed_solidity_and_harness_control") != null) and
  (.orchestration_reasons | index("spec-readiness-doc-update") != null) and
  .selected_writer_roles == ["process-implementer"] and
  .selected_review_roles == ["spec-reviewer"] and
  .selected_review_roles_source == "spec_readiness_gate" and
  (.blocking_findings[] | select(.rule_id == "spec-readiness-doc-update"))
' "$mixed_record" >/dev/null
assert_no_removed_fields "$mixed_record"

default_record="$(run_default_classify_in_scratch_repo default README.md)"
jq -e '
  .changed_files == ["README.md"] and
  .change_class == "non-semantic" and
  .orchestration_profile == "delegated"
' "$default_record" >/dev/null
assert_no_removed_fields "$default_record"

assert_ci_workflow_expressions

current_head="$(git rev-parse HEAD)"
empty_tree="4b825dc642cb6eb9a060e54bf8d69288fbee4904"

zero_base_capture="$(run_ci_entrypoint_capture zero-base workflow_dispatch "" "$current_head")"
grep -qx -- "run" "$zero_base_capture/argv"
grep -qx -- "gate:ci" "$zero_base_capture/argv"
grep -qx -- "--" "$zero_base_capture/argv"
grep -qx -- "--all" "$zero_base_capture/argv"
if grep -qx -- "--changed-files" "$zero_base_capture/argv"; then
    echo "zero-base CI path should not pass --changed-files" >&2
    exit 1
fi
[ ! -s "$zero_base_capture/diff_path" ]
[ ! -f "$zero_base_capture/changed_files" ]

diff_capture="$(run_ci_entrypoint_capture diff-based push "$empty_tree" "$current_head")"
grep -qx -- "run" "$diff_capture/argv"
grep -qx -- "gate:ci" "$diff_capture/argv"
grep -qx -- "--" "$diff_capture/argv"
grep -qx -- "--changed-files" "$diff_capture/argv"
[ -s "$diff_capture/changed_files_path" ]
[ -s "$diff_capture/diff_path" ]
[ -s "$diff_capture/changed_files" ]
[ -s "$diff_capture/diff_file" ]
diff -u <(git diff --name-only "$empty_tree" "$current_head") "$diff_capture/changed_files"

echo "orchestration tests passed"
