#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_dir="$(mktemp -d)"
source_path="src/swap/RuleMapTemp.sol"
file_list_path="$tmp_dir/changed-files.txt"
rule_map_path="$tmp_dir/rule-map.json"

cleanup() {
    rm -rf "$tmp_dir"
    rm -f "$source_path"
}
trap cleanup EXIT

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
output="$(PROCESS_RULE_MAP_FILE="$rule_map_path" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$file_list_path" bash ./script/process/quality-gate.sh 2>&1)"
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

PROCESS_RULE_MAP_FILE="$rule_map_path" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$file_list_path" bash ./script/process/quality-gate.sh
