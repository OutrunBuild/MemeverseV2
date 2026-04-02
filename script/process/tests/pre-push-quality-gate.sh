#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

selftest::enter_repo_root
selftest::setup_tmpdir
fake_bin_dir="$tmp_dir/bin"
npm_log="$tmp_dir/npm.log"
changed_files_path="$tmp_dir/changed-files.txt"
captured_file_list="$tmp_dir/captured-file-list.txt"

mkdir -p "$fake_bin_dir"

cat > "$fake_bin_dir/npm" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'QUALITY_GATE_MODE=%s QUALITY_GATE_FILE_LIST=%s CMD=%s\n' "\${QUALITY_GATE_MODE:-}" "\${QUALITY_GATE_FILE_LIST:-}" "\$*" >> "$npm_log"
if [ -n "\${QUALITY_GATE_FILE_LIST:-}" ] && [ -f "\${QUALITY_GATE_FILE_LIST:-}" ]; then
    cat "\${QUALITY_GATE_FILE_LIST}" > "$captured_file_list"
fi
EOF
chmod +x "$fake_bin_dir/npm"

cat > "$changed_files_path" <<'EOF'
src/Example.sol
EOF

PATH="$fake_bin_dir:$PATH" PRE_PUSH_FILE_LIST_OVERRIDE="$changed_files_path" bash ./script/process/run-pre-push-quality-gate.sh

selftest::assert_file_contains "$npm_log" "QUALITY_GATE_MODE=ci" "Expected run-pre-push-quality-gate.sh to force QUALITY_GATE_MODE=ci"

quality_gate_file_list="$(sed -n 's/.*QUALITY_GATE_FILE_LIST=\([^ ]*\).*/\1/p' "$npm_log" | tail -n 1)"
if [ -z "$quality_gate_file_list" ]; then
    echo "Expected run-pre-push-quality-gate.sh to pass a real computed file list to quality:gate"
    cat "$npm_log"
    exit 1
fi

if [ ! -f "$captured_file_list" ]; then
    echo "Expected fake npm to capture the computed push file list"
    cat "$npm_log"
    exit 1
fi

selftest::assert_file_contains "$captured_file_list" "^src/Example\\.sol$" "Expected computed push file list to contain src/Example.sol"

if ! grep -q "CMD=run quality:gate" "$npm_log"; then
    echo "Expected run-pre-push-quality-gate.sh to invoke npm run quality:gate"
    cat "$npm_log"
    exit 1
fi

if ! grep -q "run-pre-push-quality-gate.sh" .githooks/pre-push; then
    echo "Expected .githooks/pre-push to call script/process/run-pre-push-quality-gate.sh"
    cat .githooks/pre-push
    exit 1
fi

echo "pre-push-quality-gate selftest: PASS"
