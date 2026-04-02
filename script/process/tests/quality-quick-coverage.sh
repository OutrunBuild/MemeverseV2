#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_dir="$(mktemp -d)"
policy_file="$tmp_dir/policy.json"
rule_map_file="$tmp_dir/rule-map.json"
fake_bin_dir="$tmp_dir/bin"
forge_log="$tmp_dir/forge.log"
changed_files_path="$tmp_dir/changed-files.txt"
src_file="src/QualityQuickCoverageTemp.sol"
command_output="$tmp_dir/quality-quick.out"
patch_file="$tmp_dir/semantic.patch"
check_coverage_script="script/process/check-coverage.sh"
check_coverage_backup="$tmp_dir/check-coverage.sh.bak"

cleanup() {
    if [ -f "$check_coverage_backup" ]; then
        cp "$check_coverage_backup" "$check_coverage_script"
    fi
    rm -rf "$tmp_dir"
    git reset -- "$src_file" >/dev/null 2>&1 || true
    rm -f "$src_file"
}
trap cleanup EXIT

mkdir -p "$fake_bin_dir"

cat > "$policy_file" <<EOF
{
  "review_note": {
    "required_headings": [],
    "required_fields": [],
    "boolean_fields": [],
    "placeholder_values": []
  },
  "pull_request": {
    "required_sections": []
  },
  "rule_map": {
    "path": "$rule_map_file",
    "evidence_field": "Existing tests exercised"
  },
  "quality_gate": {
    "swap_src_sol_pattern": "^src/swap/.*\\\\.sol$",
    "src_sol_pattern": "^src/.*\\\\.sol$",
    "test_tsol_pattern": "^test/.*\\\\.t\\\\.sol$",
    "test_sol_pattern": "^test/.*\\\\.sol$",
    "shell_pattern": "^(script/.*\\\\.sh|\\\\.githooks/.*)$",
    "process_surface_pattern": "^(AGENTS\\\\.md|docs/process/.*|\\\\.codex/.*|script/process/.*|\\\\.github/.*|\\\\.githooks/.*|README\\\\.md|docs/reviews/(README|TEMPLATE)\\\\.md|docs/task-briefs/README\\\\.md|docs/agent-reports/README\\\\.md|\\\\.solhint\\\\.json|\\\\.solhintignore)$",
    "process_js_pattern": "^script/process/.*\\\\.js$",
    "package_pattern": "^(package\\\\.json|package-lock\\\\.json)$",
    "docs_contract_pattern": "^(AGENTS\\\\.md|README\\\\.md|docs/process/.*|docs/reviews/(TEMPLATE|README)\\\\.md|docs/(ARCHITECTURE|GLOSSARY|TRACEABILITY|VERIFICATION)\\\\.md|docs/spec/.*|docs/adr/.*|\\\\.github/pull_request_template\\\\.md|\\\\.codex/.*)$",
    "process_selftest_patterns": [
      "^docs/process/.*$",
      "^\\\\.codex/.*$",
      "^script/process/.*$",
      "^package(-lock)?\\\\.json$"
    ],
    "process_default_roles": [
      "process-implementer",
      "verifier"
    ],
    "package_default_roles": [
      "process-implementer",
      "verifier"
    ],
    "docs_contract_default_roles": [
      "process-implementer",
      "verifier"
    ],
    "review_note_directory": "docs/reviews",
    "slither_filter_paths": "lib|test|script|node_modules",
    "slither_exclude_detectors": "naming-convention,too-many-digits",
    "coverage": {
      "enabled": true,
      "report_file": "$tmp_dir/coverage/lcov.info",
      "exclude_tests": true,
      "ir_minimum": true,
      "quick_metrics": "line,function",
      "only_changed_tiers": true,
      "fail_on_missing_data": true,
      "default_thresholds": {
        "line": 80,
        "function": 80,
        "branch": 90
      },
      "tiers": [
        { "path": "src", "line": 80, "function": 80, "branch": 90 }
      ]
    }
  }
}
EOF

cat > "$rule_map_file" <<'EOF'
{
  "version": 2,
  "defaults": {
    "change_requirement_mode": "none",
    "evidence_requirement_mode": "none"
  },
  "rules": [],
  "testing_gaps": []
}
EOF

cat > "$fake_bin_dir/forge" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${FORGE_LOG}"

if [ "${1:-}" = "coverage" ]; then
    report_output=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --report-file)
                report_output="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    mkdir -p "$(dirname "$report_output")"
    cat > "$report_output" <<'LCOV'
TN:
SF:src/QualityQuickCoverageTemp.sol
DA:10,1
DA:11,1
DA:12,1
DA:13,1
DA:14,1
DA:15,1
DA:16,1
DA:17,1
DA:18,1
DA:19,0
FN:10,foo
FN:18,bar
FNDA:1,foo
FNDA:1,bar
BRDA:10,0,0,0
BRDA:10,0,1,0
BRDA:18,1,0,0
BRDA:18,1,1,0
end_of_record
LCOV
    exit 0
fi

exit 0
EOF

chmod +x "$fake_bin_dir/forge"

cp "$check_coverage_script" "$check_coverage_backup"
cat > "$check_coverage_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

report_file="$(node ./script/process/read-process-config.js policy quality_gate.coverage.report_file)"
forge coverage --report lcov --report-file "$report_file" --exclude-tests --ir-minimum
EOF
chmod +x "$check_coverage_script"

cat > "$src_file" <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract QualityQuickCoverageTemp {
    /**
     * @notice Returns the provided value.
     * @dev Temporary source file used to exercise quality quick coverage.
     * @param value Value to return.
     * @return returnedValue The same value that was provided.
     */
    function echo(uint256 value) external pure returns (uint256 returnedValue) {
        return value;
    }
}
EOF

cat > "$changed_files_path" <<EOF
$src_file
EOF

: > "$command_output"
cat > "$patch_file" <<EOF
diff --git a/$src_file b/$src_file
--- a/$src_file
+++ b/$src_file
@@ -1 +1 @@
-        return value;
+        return value + 1;
EOF
PATH="$fake_bin_dir:$PATH" CHANGE_CLASSIFIER_DIFF_FILE="$patch_file" PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" FORGE_LOG="$forge_log" bash ./script/process/quality-quick.sh > "$command_output" 2>&1

selftest::assert_text_lacks \
    "$(cat "$command_output")" \
    "forced by CHANGE_CLASSIFIER_FORCE=prod-semantic" \
    "Expected quality-quick coverage selftest to use the real classifier integration"

if ! grep -q "^coverage --report lcov --report-file " "$forge_log"; then
    echo "Expected quality-quick to run forge coverage when src Solidity files change"
    cat "$forge_log"
    exit 1
fi
