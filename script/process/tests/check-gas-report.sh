#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

selftest::enter_repo_root
selftest::setup_tmpdir
policy_file="$tmp_dir/policy.json"
fake_forge="$tmp_dir/fake-forge.sh"
fake_output="$tmp_dir/forge-output.txt"
fake_snapshot="$tmp_dir/generated-snapshot.txt"

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

selftest::assert_file_contains "$fake_output" "^snapshot --snap " "Expected check-gas-report to call forge snapshot with a temporary output file"

selftest::assert_text_lacks "$output" "--check" "Expected check-gas-report output to avoid baseline comparisons"

selftest::assert_text_contains "$output" "test:example() (gas: 12345)" "Expected check-gas-report to print the generated gas report"

set +e
failure_output="$(PROCESS_POLICY_FILE="$policy_file" FORGE_BIN="$fake_forge" FAKE_FORGE_OUTPUT="$fake_output" FAKE_FORGE_SNAPSHOT_SOURCE="$fake_snapshot" FAKE_FORGE_EXIT_CODE=1 bash ./script/process/check-gas-report.sh 2>&1)"
failure_status=$?
set -e

if [ "$failure_status" -eq 0 ]; then
    echo "Expected check-gas-report to fail when forge snapshot fails"
    exit 1
fi

selftest::assert_text_contains "$failure_output" "gas report generation failed" "Expected gas report failure output"

set +e
missing_output="$(PROCESS_POLICY_FILE="$policy_file" FORGE_BIN="$fake_forge" FAKE_FORGE_OUTPUT="$fake_output" FAKE_FORGE_SNAPSHOT_SOURCE="$fake_snapshot" FAKE_FORGE_WRITE_SNAPSHOT=0 bash ./script/process/check-gas-report.sh 2>&1)"
missing_status=$?
set -e

if [ "$missing_status" -eq 0 ]; then
    echo "Expected check-gas-report to fail when forge does not emit a report"
    exit 1
fi

selftest::assert_text_contains "$missing_output" "gas report was not generated" "Expected missing gas report output"
