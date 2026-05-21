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

run_pre_edit_check() {
    local file_path="$1"
    printf '{"file_path":"%s"}' "$file_path" | bash script/harness/pre-edit-check.sh
}

assert_pre_edit_check_guidance() {
    local output="$1"

    grep -Fq "classify-only with the exact changed-file set" <<<"$output"
    grep -Fq "Follow emitted orchestration_profile and phase fields" <<<"$output"
    grep -Fq "Main session may edit direct/direct-review" <<<"$output"
    grep -Fq "delegated/full-review/full-subagent must use configured writers/reviewers" <<<"$output"
}

run_gate_full_capture() {
    local name="$1"
    local changed_files="$2"
    local diff_file="$3"
    local fake_bin="$tmp_dir/$name.bin"
    local stdout="$tmp_dir/$name.stdout"
    local record="$tmp_dir/$name.record.json"
    local status

    mkdir -p "$fake_bin"

    cat >"$fake_bin/forge" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$fake_bin/forge"

    cat >"$fake_bin/npm" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$fake_bin/npm"

    cat >"$fake_bin/slither" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
{
  "success": true,
  "results": {
    "detectors": [
      {
        "check": "reentrancy-eth",
        "impact": "High",
        "confidence": "High",
        "first_markdown_element": "src/verse/MemeverseLauncher.sol#L1-L4",
        "description": "New detector finding"
      }
    ]
  }
}
JSON
exit 0
EOF
    chmod +x "$fake_bin/slither"

    set +e
    PATH="$fake_bin:$PATH" RUN_RECORD_PATH="$record" CHANGE_CLASSIFIER_DIFF_FILE="$diff_file" \
        bash script/harness/gate.sh --profile full --changed-files "$changed_files" >"$stdout" 2>&1
    status=$?
    set -e

    printf '%s\n%s\n%s\n' "$status" "$record" "$stdout"
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
      (has("review_triggers") | not) and
      (has("doc_writer_roles") | not) and
      (has("selected_writer_roles") | not) and
      (has("writer_role") | not) and
      (has("selected_review_roles") | not) and
      (has("selected_review_roles_source") | not) and
      (has("pre_code_review_roles") | not) and
      (has("pre_code_review_roles_source") | not) and
      (has("post_code_review_roles") | not) and
      (has("post_code_review_roles_source") | not)
    ' "$record" >/dev/null
}

docs_changed="$(write_changed_files docs docs/foo.md)"
docs_record="$(run_classify docs "$docs_changed")"
jq -e '
  .change_class == "non-semantic" and
  .orchestration_profile == "delegated" and
  .harness_writer_roles == ["process-implementer"] and
  .spec_review_required == false and
  .code_writer_roles == [] and
  .code_review_roles == []
' "$docs_record" >/dev/null
assert_no_removed_fields "$docs_record"

readme_changed="$(write_changed_files readme README.md)"
readme_record="$(run_classify readme "$readme_changed")"
jq -e '
  .change_class == "non-semantic" and
  .orchestration_profile == "delegated" and
  .candidate_orchestration_profile == "direct" and
  .requires_doc_editorial_attestation == true and
  .harness_writer_roles == ["process-implementer"] and
  .spec_review_required == false and
  .code_writer_roles == [] and
  .code_review_roles == []
' "$readme_record" >/dev/null
assert_no_removed_fields "$readme_record"

spec_changed="$(write_changed_files spec docs/superpowers/specs/foo.md)"
spec_record="$(run_classify spec "$spec_changed")"
jq -e '
  .orchestration_profile == "delegated" and
  .harness_writer_roles == ["process-implementer"] and
  .spec_review_required == true and
  .code_writer_roles == [] and
  .code_review_roles == [] and
  .requires_human_confirmation == true
' "$spec_record" >/dev/null
assert_no_removed_fields "$spec_record"

test_changed="$(write_changed_files testsol test/verse/MemeverseLauncherConfig.t.sol)"
test_diff="$(write_diff testsol test/verse/MemeverseLauncherConfig.t.sol 'uint256 oldValue = 1;' 'uint256 newValue = 2;')"
test_record="$(run_classify testsol "$test_changed" "$test_diff")"
jq -e '
  .change_class == "test-semantic" and
  .orchestration_profile == "direct-review" and
  .harness_writer_roles == [] and
  .spec_review_required == false and
  .code_writer_roles == ["solidity-implementer"] and
  .code_review_roles == ["logic-reviewer"]
' "$test_record" >/dev/null
assert_no_removed_fields "$test_record"

src_changed="$(write_changed_files srcsol src/verse/MemeverseLauncher.sol)"
src_diff="$(write_diff srcsol src/verse/MemeverseLauncher.sol 'uint256 oldAmount = amount;' 'uint256 newAmount = amount + 1;')"
src_record="$(run_classify srcsol "$src_changed" "$src_diff")"
jq -e '
  .change_class == "prod-semantic" and
  .orchestration_profile == "full-review" and
  .harness_writer_roles == [] and
  .spec_review_required == false and
  .code_writer_roles == ["solidity-implementer"] and
  (.code_review_roles | sort) == ["gas-reviewer", "logic-reviewer", "security-reviewer"]
' "$src_record" >/dev/null
assert_no_removed_fields "$src_record"

mixed_changed="$(write_changed_files mixed src/verse/MemeverseLauncher.sol docs/spec/verse/state-machines.md)"
mixed_record="$(run_classify mixed "$mixed_changed" "$src_diff")"
jq -e '
  .change_class == "prod-semantic" and
  .orchestration_profile == "full-review" and
  .harness_writer_roles == ["process-implementer"] and
  .spec_review_required == true and
  .code_writer_roles == ["solidity-implementer"] and
  (.code_review_roles | sort) == ["gas-reviewer", "logic-reviewer", "security-reviewer"] and
  .requires_human_confirmation == true
' "$mixed_record" >/dev/null
assert_no_removed_fields "$mixed_record"

mixed_non_spec_changed="$(write_changed_files mixednonspec src/verse/MemeverseLauncher.sol docs/TRACEABILITY.md)"
mixed_non_spec_record="$(run_classify mixednonspec "$mixed_non_spec_changed" "$src_diff")"
jq -e '
  .change_class == "prod-semantic" and
  .orchestration_profile == "full-review" and
  .harness_writer_roles == ["process-implementer"] and
  .spec_review_required == false and
  .code_writer_roles == ["solidity-implementer"] and
  (.code_review_roles | sort) == ["gas-reviewer", "logic-reviewer", "security-reviewer"] and
  .requires_human_confirmation == false
' "$mixed_non_spec_record" >/dev/null
assert_no_removed_fields "$mixed_non_spec_record"

pure_unknown_changed="$(write_changed_files pureunknown notes.txt)"
pure_unknown_record="$(run_classify pureunknown "$pure_unknown_changed" "" 1)"
jq -e '
  .change_class == "no-op" and
  .orchestration_profile == "blocked" and
  .final_verdict == "blocked" and
  (.blocking_findings[] | select(.rule_id == "unclassified-paths"))
' "$pure_unknown_record" >/dev/null
assert_no_removed_fields "$pure_unknown_record"

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

pre_edit_output="$(run_pre_edit_check "$repo_root/script/harness/test-orchestration.sh")"
assert_pre_edit_check_guidance "$pre_edit_output"
if grep -Fq "Do NOT edit files directly in the main session" <<<"$pre_edit_output"; then
    echo "pre-edit-check still forbids main session direct/direct-review edits" >&2
    exit 1
fi

slither_changed="$(write_changed_files slither src/verse/MemeverseLauncher.sol)"
slither_diff="$(write_diff slither src/verse/MemeverseLauncher.sol 'uint256 oldAmount = amount;' 'uint256 newAmount = amount + 1;')"
mapfile -t slither_run < <(run_gate_full_capture slither "$slither_changed" "$slither_diff")
slither_status="${slither_run[0]}"
slither_record="${slither_run[1]}"
slither_stdout="${slither_run[2]}"
[ "$slither_status" -ne 0 ]
jq -e '
  .final_verdict == "fail" and
  .command_results.slither_when_required.status == "failed" and
  (.blocking_findings[] | select(.rule_id == "slither_when_required"))
' "$slither_record" >/dev/null
grep -Fq "new slither finding" "$slither_stdout"

if grep -Fq "review roles are the union" docs/TRACEABILITY.md; then
    echo "TRACEABILITY still contains old review union wording" >&2
    exit 1
fi
if grep -Fq "writer may be \`mixed\`" docs/TRACEABILITY.md; then
    echo "TRACEABILITY still contains old mixed writer wording" >&2
    exit 1
fi
grep -Fq 'The gate reports phase fields for `harness_writer_roles`, `spec_review_required`, `code_writer_roles`, and `code_review_roles`.' docs/TRACEABILITY.md

echo "orchestration tests passed"
