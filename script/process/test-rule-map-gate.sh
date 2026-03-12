#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_dir="$(mktemp -d)"
source_path="src/swap/RuleMapTemp.sol"
file_list_path="$tmp_dir/changed-files.txt"
rule_map_path="$tmp_dir/rule-map.json"
fake_bin_dir="$tmp_dir/bin"
slither_baseline_file="$tmp_dir/slither.baseline"

cleanup() {
    rm -rf "$tmp_dir"
    rm -f "$source_path"
}
trap cleanup EXIT

mkdir -p "$fake_bin_dir"

cat > "$fake_bin_dir/npm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

cat > "$fake_bin_dir/slither" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

json_output=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --json)
            json_output="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

cat > "$json_output" <<'JSON'
{"success":true,"results":{"detectors":[]}}
JSON
EOF
chmod +x "$fake_bin_dir/npm"
chmod +x "$fake_bin_dir/slither"

cat > "$slither_baseline_file" <<'EOF'
EOF

cat > "$tmp_dir/policy.json" <<EOF
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
    "swap_src_sol_pattern": "^src/swap/.*\\\\.sol$",
    "src_sol_pattern": "^src/.*\\\\.sol$",
    "test_tsol_pattern": "^test/.*\\\\.t\\\\.sol$",
    "test_sol_pattern": "^test/.*\\\\.sol$",
    "shell_pattern": "^(script/.*\\\\.sh|\\\\.githooks/.*)$",
    "review_note_directory": "docs/reviews",
    "slither_baseline_file": "$slither_baseline_file",
    "slither_filter_paths": "lib|test|script|node_modules",
    "slither_exclude_detectors": "naming-convention,too-many-digits",
    "gas_snapshot_file": "docs/process/gas-snapshot.baseline",
    "gas_snapshot_tolerance_percent": "5"
  }
}
EOF

cat > "$rule_map_path" <<'EOF'
{
  "rules": [
    {
      "id": "swap-test-evidence",
      "path_prefix": "src/swap/",
      "description": "Swap changes must include a mapped changed test path.",
      "required_test_patterns": [
        "test/MemeverseSwapRouter.t.sol"
      ]
    }
  ]
}
EOF

cat > "$source_path" <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract RuleMapTemp {
    /**
     * @notice Returns the provided value.
     * @dev Temporary source file used to exercise rule-map enforcement.
     * @param value Value to return.
     * @return returnedValue The same value that was provided.
     */
    function echo(uint256 value) external pure returns (uint256 returnedValue) {
        return value;
    }
}
EOF

cat > "$file_list_path" <<EOF
$source_path
EOF

set +e
output="$(PATH="$fake_bin_dir:$PATH" SLITHER_BIN="$fake_bin_dir/slither" FORGE_BIN=/bin/true PROCESS_RULE_MAP_FILE="$rule_map_path" PROCESS_POLICY_FILE="$tmp_dir/policy.json" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$file_list_path" bash ./script/process/quality-gate.sh 2>&1)"
status=$?
set -e

if [ "$status" -eq 0 ]; then
    echo "Expected rule-map enforcement to fail when swap test evidence is missing"
    exit 1
fi

if ! printf '%s\n' "$output" | grep -q "swap-test-evidence"; then
    echo "Expected rule-map failure output to reference the missing rule id"
    printf '%s\n' "$output"
    exit 1
fi

cat > "$file_list_path" <<EOF
$source_path
test/MemeverseSwapRouter.t.sol
EOF

PATH="$fake_bin_dir:$PATH" SLITHER_BIN="$fake_bin_dir/slither" FORGE_BIN=/bin/true PROCESS_RULE_MAP_FILE="$rule_map_path" PROCESS_POLICY_FILE="$tmp_dir/policy.json" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$file_list_path" bash ./script/process/quality-gate.sh
