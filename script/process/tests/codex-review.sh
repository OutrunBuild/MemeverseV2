#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

selftest::enter_repo_root
selftest::setup_tmpdir
fake_bin_dir="$tmp_dir/bin"
codex_log="$tmp_dir/codex.log"
stderr_log="$tmp_dir/stderr.log"

mkdir -p "$fake_bin_dir"

cat > "$fake_bin_dir/codex" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" > "$codex_log"
EOF
chmod +x "$fake_bin_dir/codex"

PATH="$fake_bin_dir:$PATH" CODEX_REVIEW_BIN=codex bash ./script/process/run-codex-review.sh 2>"$stderr_log"

selftest::assert_file_contains "$codex_log" "^review --uncommitted\\( \\|$\\)" "Expected run-codex-review.sh to invoke 'codex review --uncommitted'"

if grep -qi "logic bugs" "$codex_log"; then
    echo "Expected run-codex-review.sh to avoid passing a positional prompt with --uncommitted"
    cat "$codex_log"
    exit 1
fi

if grep -q "CODEX_REVIEW_PROMPT is ignored" "$stderr_log"; then
    echo "Expected run-codex-review.sh to stop mentioning ignored prompt state"
    cat "$stderr_log"
    exit 1
fi

echo "codex-review selftest: PASS"
