#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_dir="$(mktemp -d)"
policy_file="$tmp_dir/policy.json"
fake_forge="$tmp_dir/fake-forge.sh"
fake_output="$tmp_dir/forge-output.txt"
fake_snapshot="$tmp_dir/generated-snapshot.txt"

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
  "quality_gate": {}
}
EOF

cat > "$fake_forge" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" > "${FAKE_FORGE_OUTPUT}"

snapshot_output=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --snap)
            snapshot_output="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

if [ -n "$snapshot_output" ] && [ "${FAKE_FORGE_WRITE_SNAPSHOT:-1}" = "1" ]; then
    cp "${FAKE_FORGE_SNAPSHOT_SOURCE}" "$snapshot_output"
fi

exit "${FAKE_FORGE_EXIT_CODE:-0}"
EOF
chmod +x "$fake_forge"

cat > "$fake_snapshot" <<'EOF'
test:example() (gas: 12345)
EOF

output="$(PROCESS_POLICY_FILE="$policy_file" FORGE_BIN="$fake_forge" FAKE_FORGE_OUTPUT="$fake_output" FAKE_FORGE_SNAPSHOT_SOURCE="$fake_snapshot" bash ./script/process/check-gas-report.sh 2>&1)"

if ! grep -q -- "^snapshot --snap " "$fake_output"; then
    echo "Expected check-gas-report to call forge snapshot with a temporary output file"
    cat "$fake_output"
    exit 1
fi

if printf '%s\n' "$output" | grep -q -- "--check"; then
    echo "Expected check-gas-report output to avoid baseline comparisons"
    printf '%s\n' "$output"
    exit 1
fi

if ! printf '%s\n' "$output" | grep -q "test:example() (gas: 12345)"; then
    echo "Expected check-gas-report to print the generated gas report"
    printf '%s\n' "$output"
    exit 1
fi

set +e
failure_output="$(PROCESS_POLICY_FILE="$policy_file" FORGE_BIN="$fake_forge" FAKE_FORGE_OUTPUT="$fake_output" FAKE_FORGE_SNAPSHOT_SOURCE="$fake_snapshot" FAKE_FORGE_EXIT_CODE=1 bash ./script/process/check-gas-report.sh 2>&1)"
failure_status=$?
set -e

if [ "$failure_status" -eq 0 ]; then
    echo "Expected check-gas-report to fail when forge snapshot fails"
    exit 1
fi

if ! printf '%s\n' "$failure_output" | grep -q "gas report generation failed"; then
    echo "Expected gas report failure output"
    printf '%s\n' "$failure_output"
    exit 1
fi

set +e
missing_output="$(PROCESS_POLICY_FILE="$policy_file" FORGE_BIN="$fake_forge" FAKE_FORGE_OUTPUT="$fake_output" FAKE_FORGE_SNAPSHOT_SOURCE="$fake_snapshot" FAKE_FORGE_WRITE_SNAPSHOT=0 bash ./script/process/check-gas-report.sh 2>&1)"
missing_status=$?
set -e

if [ "$missing_status" -eq 0 ]; then
    echo "Expected check-gas-report to fail when forge does not emit a report"
    exit 1
fi

if ! printf '%s\n' "$missing_output" | grep -q "gas report was not generated"; then
    echo "Expected missing gas report output"
    printf '%s\n' "$failure_output"
    exit 1
fi
