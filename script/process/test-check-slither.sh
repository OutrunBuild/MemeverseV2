#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_dir="$(mktemp -d)"
fake_slither="$tmp_dir/fake-slither.sh"
fake_output="$tmp_dir/slither-output.txt"
policy_file="$tmp_dir/policy.json"
baseline_file="$tmp_dir/slither.baseline"
solidity_file="$tmp_dir/Example.sol"

cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

cat > "$fake_slither" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

json_output=""
captured_args=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --json)
            json_output="$2"
            shift 2
            ;;
        *)
            captured_args+=("$1")
            shift
            ;;
    esac
done

printf '%s\n' "${captured_args[*]}" > "${FAKE_SLITHER_OUTPUT}"

if [ -n "$json_output" ]; then
    if [ "${FAKE_SLITHER_VARIANT:-match}" = "match" ]; then
        cat > "$json_output" <<'JSON'
{"success":true,"results":{"detectors":[{"check":"arbitrary-send-eth","impact":"High","confidence":"Medium","elements":[{"type":"function","name":"doThing","source_mapping":{"filename_relative":"src/Example.sol","lines":[12,13]}}]}]}}
JSON
    else
        cat > "$json_output" <<'JSON'
{"success":true,"results":{"detectors":[{"check":"unchecked-transfer","impact":"Medium","confidence":"Medium","elements":[{"type":"function","name":"doOtherThing","source_mapping":{"filename_relative":"src/Example.sol","lines":[20,21]}}]}]}}
JSON
    fi
fi

exit "${FAKE_SLITHER_EXIT_CODE:-0}"
EOF
chmod +x "$fake_slither"

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
  "quality_gate": {
    "slither_baseline_file": "$baseline_file",
    "slither_filter_paths": "lib|test|script|node_modules",
    "slither_exclude_detectors": "naming-convention,too-many-digits"
  }
}
EOF

cat > "$solidity_file" <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Example {}
EOF

cat > "$baseline_file" <<'EOF'
{"check":"arbitrary-send-eth","impact":"High","confidence":"Medium","file":"src/Example.sol","lines":[12,13],"element_name":"doThing","element_type":"function"}
EOF

set +e
usage_output="$(bash ./script/process/check-slither.sh 2>&1)"
usage_status=$?
set -e

if [ "$usage_status" -eq 0 ]; then
    echo "Expected check-slither to fail without Solidity file arguments"
    exit 1
fi

if ! printf '%s\n' "$usage_output" | grep -q "Usage:"; then
    echo "Expected check-slither usage output"
    printf '%s\n' "$usage_output"
    exit 1
fi

rm -f "$baseline_file"

set +e
missing_baseline_output="$(PROCESS_POLICY_FILE="$policy_file" FAKE_SLITHER_OUTPUT="$fake_output" SLITHER_BIN="$fake_slither" bash ./script/process/check-slither.sh "$solidity_file" 2>&1)"
missing_baseline_status=$?
set -e

if [ "$missing_baseline_status" -eq 0 ]; then
    echo "Expected check-slither to fail when the slither baseline is missing"
    exit 1
fi

if ! printf '%s\n' "$missing_baseline_output" | grep -q "baseline"; then
    echo "Expected missing slither baseline output"
    printf '%s\n' "$missing_baseline_output"
    exit 1
fi

cat > "$baseline_file" <<'EOF'
{"check":"arbitrary-send-eth","impact":"High","confidence":"Medium","file":"src/Example.sol","lines":[12,13],"element_name":"doThing","element_type":"function"}
EOF

PROCESS_POLICY_FILE="$policy_file" FAKE_SLITHER_OUTPUT="$fake_output" SLITHER_BIN="$fake_slither" bash ./script/process/check-slither.sh "$solidity_file"

if ! grep -q "^\\. --filter-paths lib|test|script|node_modules --exclude-dependencies --exclude naming-convention,too-many-digits$" "$fake_output"; then
    echo "Expected check-slither to analyze the repository root with the configured slither arguments"
    cat "$fake_output"
    exit 1
fi

set +e
diff_output="$(PROCESS_POLICY_FILE="$policy_file" FAKE_SLITHER_OUTPUT="$fake_output" FAKE_SLITHER_VARIANT=diff SLITHER_BIN="$fake_slither" bash ./script/process/check-slither.sh "$solidity_file" 2>&1)"
diff_status=$?
set -e

if [ "$diff_status" -eq 0 ]; then
    echo "Expected check-slither to fail when the normalized findings differ from baseline"
    exit 1
fi

if ! printf '%s\n' "$diff_output" | grep -q "findings differ from baseline"; then
    echo "Expected slither baseline diff failure output"
    printf '%s\n' "$diff_output"
    exit 1
fi

set +e
failure_output="$(PROCESS_POLICY_FILE="$policy_file" FAKE_SLITHER_OUTPUT="$fake_output" FAKE_SLITHER_EXIT_CODE=1 SLITHER_BIN="$fake_slither" bash ./script/process/check-slither.sh "$solidity_file" 2>&1)"
failure_status=$?
set -e

if [ "$failure_status" -ne 0 ]; then
    echo "Expected check-slither to accept non-zero slither status when valid JSON matches baseline"
    printf '%s\n' "$failure_output"
    exit 1
fi

if ! printf '%s\n' "$failure_output" | grep -q "baseline-matching findings"; then
    echo "Expected informational output when slither returns non-zero with valid JSON"
    printf '%s\n' "$failure_output"
    exit 1
fi

cat > "$fake_slither" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

exit "${FAKE_SLITHER_EXIT_CODE:-1}"
EOF
chmod +x "$fake_slither"

set +e
failure_output="$(PROCESS_POLICY_FILE="$policy_file" FAKE_SLITHER_OUTPUT="$fake_output" FAKE_SLITHER_EXIT_CODE=1 SLITHER_BIN="$fake_slither" bash ./script/process/check-slither.sh "$solidity_file" 2>&1)"
failure_status=$?
set -e

if [ "$failure_status" -eq 0 ]; then
    echo "Expected check-slither to fail when the configured slither binary produces no JSON output"
    exit 1
fi

if ! printf '%s\n' "$failure_output" | grep -q "slither failed"; then
    echo "Expected slither execution failure output"
    printf '%s\n' "$failure_output"
    exit 1
fi
