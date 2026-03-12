#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_dir="$(mktemp -d)"
policy_file="$tmp_dir/policy.json"
baseline_file="$tmp_dir/gas-snapshot.baseline"
fake_forge="$tmp_dir/fake-forge.sh"
fake_output="$tmp_dir/forge-output.txt"

cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

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
    "gas_snapshot_file": "$baseline_file",
    "gas_snapshot_tolerance_percent": "5"
  }
}
EOF

cat > "$fake_forge" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" > "${FAKE_FORGE_OUTPUT}"
exit "${FAKE_FORGE_EXIT_CODE:-0}"
EOF
chmod +x "$fake_forge"

set +e
missing_output="$(PROCESS_POLICY_FILE="$policy_file" FORGE_BIN="$fake_forge" FAKE_FORGE_OUTPUT="$fake_output" bash ./script/process/check-gas-snapshot.sh 2>&1)"
missing_status=$?
set -e

if [ "$missing_status" -eq 0 ]; then
    echo "Expected check-gas-snapshot to fail when the baseline file is missing"
    exit 1
fi

if ! printf '%s\n' "$missing_output" | grep -q "baseline"; then
    echo "Expected missing baseline output"
    printf '%s\n' "$missing_output"
    exit 1
fi

cat > "$baseline_file" <<'EOF'
test:example() (gas: 12345)
EOF

PROCESS_POLICY_FILE="$policy_file" FORGE_BIN="$fake_forge" FAKE_FORGE_OUTPUT="$fake_output" bash ./script/process/check-gas-snapshot.sh

if ! grep -q -- "snapshot --check $baseline_file --tolerance 5" "$fake_output"; then
    echo "Expected check-gas-snapshot to call forge snapshot with the configured baseline and tolerance"
    cat "$fake_output"
    exit 1
fi

set +e
failure_output="$(PROCESS_POLICY_FILE="$policy_file" FORGE_BIN="$fake_forge" FAKE_FORGE_OUTPUT="$fake_output" FAKE_FORGE_EXIT_CODE=1 bash ./script/process/check-gas-snapshot.sh 2>&1)"
failure_status=$?
set -e

if [ "$failure_status" -eq 0 ]; then
    echo "Expected check-gas-snapshot to fail when forge snapshot check fails"
    exit 1
fi

if ! printf '%s\n' "$failure_output" | grep -q "gas snapshot check failed"; then
    echo "Expected gas snapshot failure output"
    printf '%s\n' "$failure_output"
    exit 1
fi
