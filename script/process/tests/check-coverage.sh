#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

selftest::enter_repo_root
selftest::setup_tmpdir
policy_file="$tmp_dir/policy.json"
changed_files_path="$tmp_dir/changed-files.txt"
lcov_file="$tmp_dir/lcov.info"

cat > "$policy_file" <<EOF
{
  "quality_gate": {
    "coverage": {
      "enabled": true,
      "report_file": "$lcov_file",
      "only_changed_tiers": true,
      "fail_on_missing_data": true,
      "default_thresholds": {
        "line": 80,
        "function": 80,
        "branch": 70
      },
      "tiers": [
        { "path": "src/common", "line": 80, "function": 80, "branch": 70 },
        { "path": "src/common/access", "line": 90, "function": 90, "branch": 80 },
        { "path": "src/verse", "line": 80, "function": 80, "branch": 70 }
      ]
    }
  }
}
EOF

cat > "$changed_files_path" <<'EOF'
src/verse/Foo.sol
EOF

cat > "$lcov_file" <<'EOF'
TN:
SF:src/verse/Foo.sol
DA:10,1
DA:11,1
DA:12,1
DA:13,1
DA:14,1
DA:15,1
DA:16,1
DA:17,1
DA:18,0
DA:19,0
FN:10,foo
FN:18,bar
FNDA:1,foo
FNDA:0,bar
BRDA:10,0,0,1
BRDA:10,0,1,1
BRDA:18,1,0,0
BRDA:18,1,1,-
end_of_record
EOF

set +e
failing_output="$(PROCESS_POLICY_FILE="$policy_file" node ./script/process/check-coverage.js "$changed_files_path" "$lcov_file" 2>&1)"
failing_status=$?
set -e

if [ "$failing_status" -eq 0 ]; then
    echo "Expected check-coverage to fail when function coverage does not meet threshold"
    exit 1
fi

selftest::assert_text_contains "$failing_output" "function" "Expected failing check-coverage output to reference function coverage"

cat > "$lcov_file" <<'EOF'
TN:
SF:src/verse/Foo.sol
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
BRDA:10,0,0,1
BRDA:10,0,1,1
BRDA:18,1,0,1
BRDA:18,1,1,0
end_of_record
EOF

passing_output="$(PROCESS_POLICY_FILE="$policy_file" node ./script/process/check-coverage.js "$changed_files_path" "$lcov_file" 2>&1)"

selftest::assert_text_contains "$passing_output" "PASS" "Expected check-coverage to pass after all metrics meet threshold"

cat > "$changed_files_path" <<'EOF'
src/common/access/Guard.sol
EOF

cat > "$lcov_file" <<'EOF'
TN:
SF:src/common/access/Guard.sol
DA:20,1
DA:21,1
DA:22,1
DA:23,1
DA:24,1
DA:25,1
DA:26,1
DA:27,1
DA:28,0
DA:29,0
FN:20,allow
FN:28,deny
FNDA:1,allow
FNDA:1,deny
BRDA:20,0,0,1
BRDA:20,0,1,1
BRDA:28,1,0,1
BRDA:28,1,1,0
end_of_record
EOF

set +e
prefix_output="$(PROCESS_POLICY_FILE="$policy_file" node ./script/process/check-coverage.js "$changed_files_path" "$lcov_file" 2>&1)"
prefix_status=$?
set -e

if [ "$prefix_status" -eq 0 ]; then
    echo "Expected check-coverage to use longest-prefix tier and fail for src/common/access"
    exit 1
fi

selftest::assert_text_contains "$prefix_output" "src/common/access" "Expected longest-prefix failure output to reference src/common/access tier"

cat > "$changed_files_path" <<'EOF'
src/verse/Foo.sol
EOF

cat > "$lcov_file" <<'EOF'
TN:
SF:src/verse/Foo.sol
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
EOF

line_function_only_output="$(PROCESS_POLICY_FILE="$policy_file" COVERAGE_METRICS="line,function" node ./script/process/check-coverage.js "$changed_files_path" "$lcov_file" 2>&1)"
selftest::assert_text_contains "$line_function_only_output" "PASS" "Expected check-coverage to pass when branch metric is excluded"
