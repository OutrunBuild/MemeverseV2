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

cleanup() {
    if [ -n "$created_src_fixture" ] && [ -f "$created_src_fixture" ]; then
        rm -f "$created_src_fixture"
    fi
    if [ -n "$created_test_fixture" ] && [ -f "$created_test_fixture" ]; then
        rm -f "$created_test_fixture"
    fi
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
    created_test_fixture="test/__quality_gates_selftest__.sol"
    printf '%s\n' 'pragma solidity ^0.8.20; contract QualityGateTestFixture {}' > "$created_test_fixture"
    existing_test_file="$created_test_fixture"
fi

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

cat > "$bin_dir/bash" <<EOF
#!/bin/bash
set -euo pipefail
if [ "\${1:-}" = "-n" ]; then
  printf 'bash %s %s\n' "\$1" "\$2" >> "$command_log"
  exit 0
fi

case "\${1:-}" in
  ./script/process/check-natspec.sh|./script/process/check-coverage.sh|./script/process/check-slither.sh|./script/process/check-gas-report.sh|./script/process/check-solidity-review-note.sh|./script/process/run-stale-evidence-loop.sh|./script/process/check-rule-map.sh)
    printf 'bash %s\n' "\$1" >> "$command_log"
    if [ "\$1" = "./script/process/check-solidity-review-note.sh" ]; then
      printf '[check-solidity-review-note] PASS\n'
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

    : > "$npm_log"
    : > "$command_log"
    printf '%s\n' "$changed_file" > "$changed_files_path"
    printf '%s\n' "$diff_content" > "$diff_file"
    PATH="$bin_dir:$PATH" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" CHANGE_CLASSIFIER_FORCE="$forced_classification" CHANGE_CLASSIFIER_DIFF_FILE="$diff_file" \
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

run_quality_script "quality-gate.sh" "$existing_src_file" "$gate_output" "non-semantic" "diff --git a/$existing_src_file b/$existing_src_file
--- a/$existing_src_file
+++ b/$existing_src_file
@@ -1 +1 @@
-// old
+// new"
assert_contains "change classification: non-semantic" "$gate_output" "quality-gate output for non-semantic Solidity change"
assert_contains "auto codex review: skipped" "$gate_output" "quality-gate output for non-semantic Solidity change"
assert_contains "verifier profile: light" "$gate_output" "quality-gate output for non-semantic Solidity change"
assert_contains "forge fmt --check $existing_src_file" "$command_log" "quality-gate command log for non-semantic Solidity change"
assert_contains "forge build" "$command_log" "quality-gate command log for non-semantic Solidity change"
assert_contains "bash ./script/process/check-natspec.sh" "$command_log" "quality-gate command log for non-semantic Solidity change"
assert_contains "bash ./script/process/check-solidity-review-note.sh" "$command_log" "quality-gate command log for non-semantic Solidity change"
if grep -q "forge test -vvv" "$command_log"; then
    echo "Did not expect forge test for non-semantic Solidity change"
    cat "$command_log"
    exit 1
fi
if grep -q "check-slither" "$command_log"; then
    echo "Did not expect slither for non-semantic Solidity change"
    cat "$command_log"
    exit 1
fi

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

run_quality_script "quality-gate.sh" "$existing_src_file" "$gate_output" "prod-semantic" "diff --git a/$existing_src_file b/$existing_src_file
--- a/$existing_src_file
+++ b/$existing_src_file
@@ -10 +10 @@
-        return amount;
+        return amount + 1;"
assert_contains "change classification: prod-semantic" "$gate_output" "quality-gate output for prod-semantic Solidity change"
assert_contains "auto codex review: required" "$gate_output" "quality-gate output for prod-semantic Solidity change"
assert_contains "verifier profile: full" "$gate_output" "quality-gate output for prod-semantic Solidity change"
assert_contains "forge test -vvv" "$command_log" "quality-gate command log for prod-semantic change"
assert_contains "bash ./script/process/check-coverage.sh" "$command_log" "quality-gate command log for prod-semantic change"
assert_contains "bash ./script/process/check-slither.sh" "$command_log" "quality-gate command log for prod-semantic change"
assert_contains "bash ./script/process/check-gas-report.sh" "$command_log" "quality-gate command log for prod-semantic change"

echo "quality-gates selftest: PASS"
