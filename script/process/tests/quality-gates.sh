#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_dir="$(mktemp -d)"
bin_dir="$tmp_dir/bin"
npm_log="$tmp_dir/npm.log"
command_log="$tmp_dir/commands.log"
quick_output="$tmp_dir/quality-quick.out"
gate_output="$tmp_dir/quality-gate.out"
changed_files_path="$tmp_dir/changed-files.txt"
diff_file="$tmp_dir/change.diff"
created_src_fixture=""
created_test_fixture=""
path_spec_brief_file="docs/task-briefs/2026-04-10-quality-gates-path-spec-brief.md"
spec_brief_file="docs/task-briefs/2026-04-10-quality-gates-spec-brief.md"
custom_spec_output="docs/designs/quality-gates-spec-output.md"

cleanup() {
    if [ -n "$created_src_fixture" ] && [ -f "$created_src_fixture" ]; then
        rm -f "$created_src_fixture"
    fi
    if [ -n "$created_test_fixture" ] && [ -f "$created_test_fixture" ]; then
        rm -f "$created_test_fixture"
    fi
    rm -f "$path_spec_brief_file" "$spec_brief_file" "$custom_spec_output"
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

existing_src_file="$(rg --files src -g '*.sol' 2>/dev/null | head -n 1 || true)"
existing_test_file="$(rg --files test -g '*.sol' 2>/dev/null | head -n 1 || true)"

if [ -z "$existing_src_file" ]; then
    mkdir -p src
    created_src_fixture="src/__quality_gates_selftest__.sol"
    printf '%s\n' 'pragma solidity ^0.8.20; contract QualityGateFixture {}' > "$created_src_fixture"
    existing_src_file="$created_src_fixture"
fi

if [ -z "$existing_test_file" ]; then
    mkdir -p test
    created_test_fixture="test/__quality_gates_selftest__.t.sol"
    printf '%s\n' 'pragma solidity ^0.8.20; contract QualityGateTestFixture {}' > "$created_test_fixture"
    existing_test_file="$created_test_fixture"
fi

mkdir -p "$(dirname "$path_spec_brief_file")" "$(dirname "$spec_brief_file")" "$(dirname "$custom_spec_output")"

cat > "$path_spec_brief_file" <<'EOF'
# Task Brief

- Goal: quality gates path-based spec routing selftest
- Change classification: non-semantic
- Change type: docs
- Files in scope: docs/spec/protocol.md
- Change classification rationale: path-based spec artifact under docs/spec
- Out of scope: none
- Known facts: this brief anchors docs/spec/protocol.md to the spec surface
- Open questions / assumptions: none
- Risks to check: missing spec-surface contract enforcement
- Required roles: process-implementer, spec-reviewer, verifier
- Optional roles: none
- Verifier profile: n/a
- Default writer role: process-implementer
- Implementation owner: process-implementer
- Write permissions: docs/spec/protocol.md
- Writer dispatch backend: native-codex-subagents
- Writer dispatch target: .codex/agents/process-implementer.toml
- Writer dispatch scope: docs/spec/protocol.md
- Non-goals: none
- Acceptance checks: rerun process-implementer -> spec-reviewer -> verifier for the latest spec scope
- Required verifier commands: npm run docs:check; npm run process:selftest
- Required artifacts: Task Brief, writer evidence, spec review evidence, verifier evidence
- Review note required: no
- Artifact type: spec
- Spec review required: yes
- Spec artifact paths: docs/spec/protocol.md
- Semantic review dimensions: none
- Source-of-truth docs: none
- External sources required: none
- Critical assumptions to prove or reject: none
- Required output fields: none
- Review note impact: no
- If blocked: stop and return the spec-surface blocker
EOF

mkdir -p "$bin_dir"

cat > "$bin_dir/npm" <<EOF
#!/bin/bash
set -euo pipefail
printf '%s\n' "\$*" >> "$npm_log"
EOF
chmod +x "$bin_dir/npm"

cat > "$bin_dir/forge" <<EOF
#!/bin/bash
set -euo pipefail
printf 'forge %s\n' "\$*" >> "$command_log"
EOF
chmod +x "$bin_dir/forge"

cat > "$bin_dir/git" <<EOF
#!/bin/bash
set -euo pipefail

if [ "\${1:-}" = "rev-parse" ] && [ "\${2:-}" = "--show-toplevel" ]; then
  printf '%s\n' "$repo_root"
  exit 0
fi

if [ "\${1:-}" = "diff" ] && [ "\${2:-}" = "--cached" ] && [ "\${3:-}" = "--name-only" ] && [ "\${4:-}" = "--diff-filter=ACMRD" ]; then
  cat "$changed_files_path"
  exit 0
fi

exec /usr/bin/git "\$@"
EOF
chmod +x "$bin_dir/git"

cat > "$bin_dir/bash" <<EOF
#!/bin/bash
set -euo pipefail
if [ "\${1:-}" = "-n" ]; then
  printf 'bash %s %s\n' "\$1" "\$2" >> "$command_log"
  exit 0
fi

case "\${1:-}" in
  ./script/process/check-natspec.sh|./script/process/check-coverage.sh|./script/process/check-slither.sh|./script/process/check-gas-report.sh|./script/process/check-solidity-review-note.sh|./script/process/check-spec-reviewer-report.sh|./script/process/run-stale-evidence-loop.sh|./script/process/check-rule-map.sh)
    printf 'bash %s\n' "\$1" >> "$command_log"
    if [ "\$1" = "./script/process/check-rule-map.sh" ] && [ "\${FAIL_RULE_MAP_GATE:-0}" = "1" ]; then
      printf '[check-rule-map] simulated failure\n' >&2
      exit 1
    fi
    if [ "\$1" = "./script/process/check-solidity-review-note.sh" ]; then
      printf '[check-solidity-review-note] PASS\n'
    elif [ "\$1" = "./script/process/check-spec-reviewer-report.sh" ]; then
      printf '[check-spec-reviewer-report] PASS\n'
    fi
    exit 0
    ;;
esac

exec /bin/bash "\$@"
EOF
chmod +x "$bin_dir/bash"

run_quality_script() {
    local script_name="$1"
    local changed_file="$2"
    local output_file="$3"
    local forced_classification="${4:-}"
    local diff_content="${5:-}"
    local gate_mode="${6:-ci}"

    : > "$npm_log"
    : > "$command_log"
    printf '%s\n' "$changed_file" > "$changed_files_path"
    printf '%s\n' "$diff_content" > "$diff_file"
    if [ "$gate_mode" = "ci" ]; then
        PATH="$bin_dir:$PATH" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" CHANGE_CLASSIFIER_FORCE="$forced_classification" CHANGE_CLASSIFIER_DIFF_FILE="$diff_file" FAIL_RULE_MAP_GATE="${FAIL_RULE_MAP_GATE:-0}" \
            /bin/bash "./script/process/${script_name}" >"$output_file" 2>&1
        return
    fi

    PATH="$bin_dir:$PATH" QUALITY_GATE_FILE_LIST="$changed_files_path" CHANGE_CLASSIFIER_FORCE="$forced_classification" CHANGE_CLASSIFIER_DIFF_FILE="$diff_file" FAIL_RULE_MAP_GATE="${FAIL_RULE_MAP_GATE:-0}" \
        /bin/bash "./script/process/${script_name}" >"$output_file" 2>&1
}

assert_contains() {
    local needle="$1"
    local haystack_file="$2"
    local context="$3"

    if ! grep -qF "$needle" "$haystack_file"; then
        echo "Expected '$needle' in $context"
        cat "$haystack_file"
        exit 1
    fi
}

if [ ! -f "./script/process/lib/quality-common.sh" ]; then
    echo "Expected shared helper ./script/process/lib/quality-common.sh"
    exit 1
fi

if ! grep -q '"spec:ready"[[:space:]]*:[[:space:]]*"bash ./script/process/spec-ready.sh"' package.json; then
    echo "Expected package.json to expose npm run spec:ready via script/process/spec-ready.sh"
    exit 1
fi

if [ ! -f "./script/process/spec-ready.sh" ]; then
    echo "Expected script/process/spec-ready.sh to exist"
    exit 1
fi

if ! grep -q "git diff --cached --name-only --diff-filter=ACMRD" "./script/process/spec-ready.sh" \
    || ! grep -q "git diff --name-only --diff-filter=ACMRD" "./script/process/spec-ready.sh" \
    || ! grep -q "git ls-files --others --exclude-standard" "./script/process/spec-ready.sh" \
    || ! grep -q "QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST=" "./script/process/spec-ready.sh"; then
    echo "Expected spec-ready wrapper to collect staged + unstaged + untracked files and pass QUALITY_GATE_FILE_LIST"
    exit 1
fi

assert_contains "source ./script/process/lib/quality-common.sh" "./script/process/quality-quick.sh" "quality-quick implementation"
assert_contains "source ./script/process/lib/quality-common.sh" "./script/process/quality-gate.sh" "quality-gate implementation"

run_quality_script "quality-quick.sh" "script/process/check-coverage.js" "$quick_output"
assert_contains "[quality-quick] node --check (changed process JS files)" "$quick_output" "quality-quick output for process JS change"
assert_contains "run docs:check" "$npm_log" "quality-quick npm log for process JS change"
assert_contains "run process:selftest" "$npm_log" "quality-quick npm log for process JS change"

run_quality_script "quality-quick.sh" "script/process/fixtures/example.txt" "$quick_output"
assert_contains "run docs:check" "$npm_log" "quality-quick npm log for generic process surface change"
assert_contains "run process:selftest" "$npm_log" "quality-quick npm log for generic process surface change"

run_quality_script "quality-quick.sh" ".githooks/pre-commit" "$quick_output"
assert_contains "run docs:check" "$npm_log" "quality-quick npm log for githook change"

run_quality_script "quality-gate.sh" "docs/process/policy.json" "$gate_output"
assert_contains "run docs:check" "$npm_log" "quality-gate npm log for policy change"
assert_contains "run process:selftest" "$npm_log" "quality-gate npm log for policy change"

run_quality_script "quality-gate.sh" ".githooks/pre-commit" "$gate_output"
assert_contains "run docs:check" "$npm_log" "quality-gate npm log for githook change"

run_quality_script "quality-gate.sh" "package.json" "$gate_output"
assert_contains "ci" "$npm_log" "quality-gate npm log for package change"
assert_contains "run docs:check" "$npm_log" "quality-gate npm log for package change"
assert_contains "run process:selftest" "$npm_log" "quality-gate npm log for package change"

printf '%s\n' "$path_spec_brief_file" "docs/spec/protocol.md" > "$changed_files_path"
: > "$npm_log"
: > "$command_log"
PATH="$bin_dir:$PATH" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" /bin/bash ./script/process/quality-quick.sh >"$quick_output" 2>&1
assert_contains "default roles: process-implementer; spec-reviewer; verifier" "$quick_output" "quality-quick output for spec surface change"
assert_contains "run docs:check" "$npm_log" "quality-quick npm log for spec surface change"
assert_contains "run process:selftest" "$npm_log" "quality-quick npm log for spec surface change"

: > "$npm_log"
: > "$command_log"
PATH="$bin_dir:$PATH" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" /bin/bash ./script/process/quality-gate.sh >"$gate_output" 2>&1
assert_contains "default roles: process-implementer; spec-reviewer; verifier" "$gate_output" "quality-gate output for spec surface change"
assert_contains "run docs:check" "$npm_log" "quality-gate npm log for spec surface change"
assert_contains "run process:selftest" "$npm_log" "quality-gate npm log for spec surface change"

cat > "$custom_spec_output" <<'EOF'
# Quality Gates Spec Output

Custom spec output fixture for brief-declared quality gate routing.
EOF

cat > "$spec_brief_file" <<EOF
# Task Brief

- Goal: quality gates spec routing selftest
- Change classification: spec-surface
- Change classification: non-semantic
- Change type: docs
- Files in scope: $custom_spec_output
- Change classification rationale: current task emits a spec artifact outside docs/spec
- Out of scope: none
- Known facts: this brief declares a custom spec output
- Open questions / assumptions: none
- Risks to check: missing spec-surface contract enforcement
- Required roles: process-implementer, spec-reviewer, verifier
- Optional roles: none
- Verifier profile: n/a
- Default writer role: process-implementer
- Implementation owner: process-implementer
- Write permissions: $spec_brief_file, $custom_spec_output
- Writer dispatch backend: native-codex-subagents
- Writer dispatch target: .codex/agents/process-implementer.toml
- Writer dispatch scope: $custom_spec_output
- Non-goals: none
- Acceptance checks: rerun process-implementer -> spec-reviewer -> verifier for the latest spec scope
- Required verifier commands: npm run docs:check; npm run process:selftest
- Required artifacts: Task Brief, writer evidence, spec review evidence, verifier evidence
- Review note required: no
- Artifact type: spec
- Spec review required: yes
- Spec artifact paths: $custom_spec_output
- Semantic review dimensions: none
- Source-of-truth docs: none
- External sources required: none
- Critical assumptions to prove or reject: none
- Required output fields: none
- Review note impact: no
- If blocked: stop and return the spec-surface blocker
EOF

printf '%s\n' "$spec_brief_file" "$custom_spec_output" > "$changed_files_path"
: > "$npm_log"
: > "$command_log"
PATH="$bin_dir:$PATH" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" /bin/bash ./script/process/quality-quick.sh >"$quick_output" 2>&1
assert_contains "default roles: process-implementer; spec-reviewer; verifier" "$quick_output" "quality-quick output for brief-declared spec surface change"
assert_contains "run docs:check" "$npm_log" "quality-quick npm log for brief-declared spec surface change"
assert_contains "run process:selftest" "$npm_log" "quality-quick npm log for brief-declared spec surface change"

: > "$npm_log"
: > "$command_log"
PATH="$bin_dir:$PATH" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" /bin/bash ./script/process/quality-gate.sh >"$gate_output" 2>&1
assert_contains "default roles: process-implementer; spec-reviewer; verifier" "$gate_output" "quality-gate output for brief-declared spec surface change"
assert_contains "run docs:check" "$npm_log" "quality-gate npm log for brief-declared spec surface change"
assert_contains "run process:selftest" "$npm_log" "quality-gate npm log for brief-declared spec surface change"

sed -i 's|- Required artifacts: Task Brief, writer evidence, spec review evidence, verifier evidence|- Required artifacts: Task Brief, writer evidence|' "$spec_brief_file"
set +e
PATH="$bin_dir:$PATH" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" /bin/bash ./script/process/quality-quick.sh >"$quick_output" 2>&1
status=$?
set -e
if [ "$status" -eq 0 ]; then
    echo "Expected quality-quick to fail when spec-surface Required artifacts metadata is incomplete"
    cat "$quick_output"
    exit 1
fi
assert_contains "Required artifacts" "$quick_output" "quality-quick output for incomplete spec-surface artifacts metadata"

cat > "$spec_brief_file" <<EOF
# Task Brief

- Goal: quality gates spec routing selftest
- Change classification: spec-surface
- Change classification: non-semantic
- Change type: docs
- Files in scope: $custom_spec_output
- Change classification rationale: current task emits a spec artifact outside docs/spec
- Out of scope: none
- Known facts: this brief declares a custom spec output
- Open questions / assumptions: none
- Risks to check: missing spec-surface contract enforcement
- Required roles: process-implementer, spec-reviewer, verifier
- Optional roles: none
- Verifier profile: n/a
- Default writer role: process-implementer
- Implementation owner: process-implementer
- Write permissions: $spec_brief_file, $custom_spec_output
- Writer dispatch backend: native-codex-subagents
- Writer dispatch target: .codex/agents/process-implementer.toml
- Writer dispatch scope: $custom_spec_output
- Non-goals: none
- Acceptance checks: rerun process-implementer -> spec-reviewer -> verifier for the latest spec scope
- Required verifier commands: npm run docs:check; npm run process:selftest
- Required artifacts: Task Brief, writer evidence, spec review evidence, verifier evidence
- Review note required: no
- Artifact type: spec
- Spec review required: yes
- Spec artifact paths: $custom_spec_output
- Semantic review dimensions: none
- Source-of-truth docs: none
- External sources required: none
- Critical assumptions to prove or reject: none
- Required output fields: none
- Review note impact: no
- If blocked: stop and return the spec-surface blocker
EOF

sed -i 's|- Required verifier commands: npm run docs:check; npm run process:selftest|- Required verifier commands: npm run docs:check|' "$spec_brief_file"
set +e
PATH="$bin_dir:$PATH" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" /bin/bash ./script/process/quality-gate.sh >"$gate_output" 2>&1
status=$?
set -e
if [ "$status" -eq 0 ]; then
    echo "Expected quality-gate to fail when spec-surface Required verifier commands metadata is incomplete"
    cat "$gate_output"
    exit 1
fi
assert_contains "Required verifier commands" "$gate_output" "quality-gate output for incomplete spec-surface verifier command metadata"

: > "$command_log"
FAIL_RULE_MAP_GATE=1 run_quality_script "quality-quick.sh" "$existing_src_file" "$quick_output" "non-semantic" "diff --git a/$existing_src_file b/$existing_src_file
--- a/$existing_src_file
+++ b/$existing_src_file
@@ -1 +1 @@
-// old
+// new"
assert_contains "change classification: non-semantic" "$quick_output" "quality-quick output for non-semantic Solidity change"
if grep -q "bash ./script/process/check-rule-map.sh" "$command_log"; then
    echo "Did not expect rule-map changed-test gate during non-semantic quality-quick routing"
    cat "$command_log"
    exit 1
fi

: > "$command_log"
FAIL_RULE_MAP_GATE=1
set +e
run_quality_script "quality-quick.sh" "$existing_src_file" "$quick_output" "prod-semantic" "diff --git a/$existing_src_file b/$existing_src_file
--- a/$existing_src_file
+++ b/$existing_src_file
@@ -10 +10 @@
-        return amount;
+        return amount + 1;"
status=$?
set -e
if [ "$status" -eq 0 ]; then
    echo "Expected semantic quality-quick routing to enforce the rule-map changed-test gate"
    cat "$quick_output"
    exit 1
fi
assert_contains "[check-rule-map] simulated failure" "$quick_output" "quality-quick output for semantic rule-map failure"
assert_contains "bash ./script/process/check-rule-map.sh" "$command_log" "quality-quick command log for semantic rule-map failure"

run_quality_script "quality-gate.sh" "$existing_src_file" "$gate_output" "non-semantic" "diff --git a/$existing_src_file b/$existing_src_file
--- a/$existing_src_file
+++ b/$existing_src_file
@@ -1 +1 @@
-// old
+// new"
assert_contains "change classification: non-semantic" "$gate_output" "quality-gate output for non-semantic Solidity change"
assert_contains "verifier profile: light" "$gate_output" "quality-gate output for non-semantic Solidity change"
assert_contains "forge fmt --check $existing_src_file" "$command_log" "quality-gate command log for non-semantic Solidity change"
assert_contains "forge build" "$command_log" "quality-gate command log for non-semantic Solidity change"
assert_contains "bash ./script/process/check-natspec.sh" "$command_log" "quality-gate command log for non-semantic Solidity change"
assert_contains "bash ./script/process/check-solidity-review-note.sh" "$command_log" "quality-gate command log for non-semantic Solidity change"
assert_contains "forge test -vvv" "$command_log" "quality-gate command log for non-semantic strict full suite"
if grep -q "check-slither" "$command_log"; then
    echo "Did not expect slither for non-semantic Solidity change"
    cat "$command_log"
    exit 1
fi
if grep -q "check-rule-map" "$command_log"; then
    echo "Did not expect rule-map changed-test gate during non-semantic quality-gate routing"
    cat "$command_log"
    exit 1
fi

: > "$command_log"
FAIL_RULE_MAP_GATE=1
set +e
run_quality_script "quality-gate.sh" "$existing_src_file" "$gate_output" "test-semantic" "diff --git a/$existing_src_file b/$existing_src_file
--- a/$existing_src_file
+++ b/$existing_src_file
@@ -10 +10 @@
-        return amount;
+        return amount + 1;"
status=$?
set -e
if [ "$status" -eq 0 ]; then
    echo "Expected semantic quality-gate routing to enforce the rule-map changed-test gate"
    cat "$gate_output"
    exit 1
fi
assert_contains "[check-rule-map] simulated failure" "$gate_output" "quality-gate output for semantic rule-map failure"
assert_contains "bash ./script/process/check-rule-map.sh" "$command_log" "quality-gate command log for semantic rule-map failure"

FAIL_RULE_MAP_GATE=0
run_quality_script "quality-gate.sh" "$existing_test_file" "$gate_output" "test-semantic" "diff --git a/$existing_test_file b/$existing_test_file
--- a/$existing_test_file
+++ b/$existing_test_file
@@ -10 +10 @@
-        assertEq(result, 1);
+        assertEq(result, 2);"
assert_contains "change classification: test-semantic" "$gate_output" "quality-gate output for test-semantic Solidity change"
assert_contains "verifier profile: light" "$gate_output" "quality-gate output for test-semantic Solidity change"
assert_contains "forge test -vvv" "$command_log" "quality-gate command log for test-semantic change"
if grep -q "check-coverage" "$command_log"; then
    echo "Did not expect coverage for test-semantic change"
    cat "$command_log"
    exit 1
fi

FAIL_RULE_MAP_GATE=0
run_quality_script "quality-gate.sh" "$existing_src_file" "$gate_output" "prod-semantic" "diff --git a/$existing_src_file b/$existing_src_file
--- a/$existing_src_file
+++ b/$existing_src_file
@@ -10 +10 @@
-        return amount;
+        return amount + 1;" "staged"
assert_contains "change classification: prod-semantic" "$gate_output" "quality-gate output for prod-semantic Solidity change"
assert_contains "verifier profile: full" "$gate_output" "quality-gate output for prod-semantic Solidity change"
assert_contains "forge test -vvv" "$command_log" "quality-gate command log for prod-semantic change"
assert_contains "bash ./script/process/check-coverage.sh" "$command_log" "quality-gate command log for prod-semantic change"
assert_contains "bash ./script/process/check-slither.sh" "$command_log" "quality-gate command log for prod-semantic change"
assert_contains "run codex:review" "$npm_log" "quality-gate npm log for staged prod-semantic change"

run_quality_script "quality-gate.sh" "$existing_src_file" "$gate_output" "prod-semantic" "diff --git a/$existing_src_file b/$existing_src_file
--- a/$existing_src_file
+++ b/$existing_src_file
@@ -10 +10 @@
-        return amount;
+        return amount + 1;"
if grep -q "run codex:review" "$npm_log"; then
    echo "Did not expect codex review for ci-mode quality-gate"
    cat "$npm_log"
    exit 1
fi

echo "quality-gates selftest: PASS"
