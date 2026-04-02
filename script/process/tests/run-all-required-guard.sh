#!/usr/bin/env bash
set -euo pipefail

if [ "${PROCESS_SELFTEST_RUN_ALL_GUARD_PROBE:-0}" = "1" ]; then
    exit 0
fi

source "$(dirname "$0")/lib/common.sh"

selftest::enter_repo_root
selftest::setup_tmpdir

suite_dir="$tmp_dir/selftests"
run_log="$tmp_dir/run.log"
mkdir -p "$suite_dir"

cat > "$suite_dir/alpha.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "alpha" >> "$run_log"
EOF
chmod +x "$suite_dir/alpha.sh"

missing_output="$(
    PROCESS_SELFTEST_RUN_ALL_GUARD_PROBE=1 \
    PROCESS_SELFTEST_RUN_ALL_TEST_DIR="$suite_dir" \
    PROCESS_SELFTEST_RUN_ALL_REQUIRED_TOP_LEVEL=$'alpha.sh\nbeta.sh' \
    bash ./script/process/tests/run-all.sh 2>&1 || true
)"

selftest::assert_text_contains \
    "$missing_output" \
    "missing required top-level selftests: beta.sh" \
    "Expected run-all to fail fast when a required top-level selftest is missing"

cat > "$suite_dir/beta.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "beta" >> "$run_log"
EOF

cat > "$suite_dir/gamma.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "gamma" >> "$run_log"
EOF

chmod +x "$suite_dir/beta.sh" "$suite_dir/gamma.sh"

success_output="$(
    PROCESS_SELFTEST_RUN_ALL_TEST_DIR="$suite_dir" \
    PROCESS_SELFTEST_RUN_ALL_REQUIRED_TOP_LEVEL=$'alpha.sh\nbeta.sh' \
    bash ./script/process/tests/run-all.sh 2>&1
)"

selftest::assert_text_contains \
    "$success_output" \
    "PASS$" \
    "Expected run-all to pass when required top-level selftests exist"
selftest::assert_file_contains \
    "$run_log" \
    "^alpha$" \
    "Expected run-all to execute required selftests from the override directory"
selftest::assert_file_contains \
    "$run_log" \
    "^beta$" \
    "Expected run-all to execute every required selftest from the override directory"
selftest::assert_file_contains \
    "$run_log" \
    "^gamma$" \
    "Expected run-all to preserve auto-discovery for additional top-level selftests"

echo "run-all required guard selftest: PASS"
