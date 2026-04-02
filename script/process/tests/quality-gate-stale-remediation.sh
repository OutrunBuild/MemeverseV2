#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_dir="$(mktemp -d)"
bin_dir="$tmp_dir/bin"
npm_log="$tmp_dir/npm.log"
forge_log="$tmp_dir/forge.log"
changed_files_path="$tmp_dir/changed-files.txt"
output_file="$tmp_dir/quality-gate.out"
fixture_solidity_file="src/__quality_gate_stale_remediation_fixture.sol"

backup_file() {
    local source_file="$1"
    local backup_file="$tmp_dir/backup/${source_file}"
    mkdir -p "$(dirname "$backup_file")"
    cp "$source_file" "$backup_file"
}

restore_file() {
    local source_file="$1"
    local backup_file="$tmp_dir/backup/${source_file}"
    if [ -f "$backup_file" ]; then
        cp "$backup_file" "$source_file"
    fi
}

cleanup() {
    restore_file "script/process/check-natspec.sh"
    restore_file "script/process/check-coverage.sh"
    restore_file "script/process/check-slither.sh"
    restore_file "script/process/check-gas-report.sh"
    restore_file "script/process/check-solidity-review-note.sh"
    rm -rf "$tmp_dir"
    rm -f "$fixture_solidity_file"
}
trap cleanup EXIT

mkdir -p "$bin_dir"

cat > "$bin_dir/npm" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >> "$npm_log"
if [ "\$*" = "run stale-evidence:loop" ]; then
  echo "[fake npm] stale-evidence:loop invoked"
  exit 2
fi
exit 0
EOF
chmod +x "$bin_dir/npm"

cat > "$bin_dir/forge" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >> "$forge_log"
exit 0
EOF
chmod +x "$bin_dir/forge"

backup_file "script/process/check-natspec.sh"
backup_file "script/process/check-coverage.sh"
backup_file "script/process/check-slither.sh"
backup_file "script/process/check-gas-report.sh"
backup_file "script/process/check-solidity-review-note.sh"

cat > "script/process/check-natspec.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

cat > "script/process/check-coverage.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

cat > "script/process/check-slither.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

cat > "script/process/check-gas-report.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

cat > "script/process/check-solidity-review-note.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "[check-solidity-review-note] ERROR: stale evidence. Referenced artifact predates the current writer Agent Report."
exit 1
EOF

chmod +x \
    "script/process/check-natspec.sh" \
    "script/process/check-coverage.sh" \
    "script/process/check-slither.sh" \
    "script/process/check-gas-report.sh" \
    "script/process/check-solidity-review-note.sh"

cat > "$fixture_solidity_file" <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title QualityGateStaleRemediationFixture
contract QualityGateStaleRemediationFixture {
    /// @notice Returns a constant value
    function ping() external pure returns (uint256) {
        return 1;
    }
}
EOF

cat > "$changed_files_path" <<EOF
$fixture_solidity_file
EOF

set +e
PATH="$bin_dir:$PATH" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" \
    bash ./script/process/quality-gate.sh >"$output_file" 2>&1
status=$?
set -e

if [ "$status" -ne 2 ]; then
    echo "Expected quality-gate to exit with status 2 when stale evidence remediation is required"
    cat "$output_file"
    exit 1
fi

if ! grep -q "stale evidence detected" "$output_file"; then
    echo "Expected quality-gate output to mention stale evidence remediation"
    cat "$output_file"
    exit 1
fi

if ! grep -q "stale-evidence:loop invoked" "$output_file"; then
    echo "Expected quality-gate output to include the remediation loop invocation"
    cat "$output_file"
    exit 1
fi

if ! grep -q "run stale-evidence:loop" "$npm_log"; then
    echo "Expected quality-gate to invoke npm run stale-evidence:loop after stale evidence detection"
    cat "$output_file"
    exit 1
fi

echo "quality-gate-stale-remediation selftest: PASS"
