#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_dir="$(mktemp -d)"
review_path="docs/reviews/9999-12-31-rule-map-test-review.md"
source_path="src/swap/RuleMapTemp.sol"
file_list_path="$tmp_dir/changed-files.txt"
rule_map_path="$tmp_dir/rule-map.json"

cleanup() {
    rm -rf "$tmp_dir"
    rm -f "$review_path"
    rm -f "$source_path"
}
trap cleanup EXIT

cat > "$rule_map_path" <<'EOF'
{
  "rules": [
    {
      "id": "swap-test-evidence",
      "path_prefix": "src/swap/",
      "description": "Swap changes must cite a mapped test path.",
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

cat > "$review_path" <<'EOF'
# 9999-12-31-rule-map-test-review

## Scope
- Change summary: Temporary rule-map gate rehearsal.
- Files reviewed: src/swap/RuleMapTemp.sol.

## Impact
- Behavior change: no
- ABI change: no
- Storage layout change: no
- Config change: no

## Findings
- High findings: none.
- Medium findings: none.
- Low findings: none.
- None: none.

## Simplification
- Candidate simplifications considered: none.
- Applied: none.
- Rejected (with reason): none.

## Docs
- Docs updated: none
- Why these docs: no docs needed for this rehearsal.
- No-doc reason: behavior unchanged in the rehearsal.

## Tests
- Tests updated: none
- Existing tests exercised: test/Unrelated.t.sol
- No-test-change reason: rehearsal only.

## Verification
- Commands run: none.
- Results: none.

## Decision
- Ready to commit: yes
- Residual risks: none.
EOF

cat > "$file_list_path" <<EOF
$source_path
$review_path
EOF

set +e
output="$(PROCESS_RULE_MAP_FILE="$rule_map_path" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$file_list_path" bash ./script/quality-gate.sh 2>&1)"
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

cat > "$review_path" <<'EOF'
# 9999-12-31-rule-map-test-review

## Scope
- Change summary: Temporary rule-map gate rehearsal.
- Files reviewed: src/swap/RuleMapTemp.sol.

## Impact
- Behavior change: no
- ABI change: no
- Storage layout change: no
- Config change: no

## Findings
- High findings: none.
- Medium findings: none.
- Low findings: none.
- None: none.

## Simplification
- Candidate simplifications considered: none.
- Applied: none.
- Rejected (with reason): none.

## Docs
- Docs updated: none
- Why these docs: no docs needed for this rehearsal.
- No-doc reason: behavior unchanged in the rehearsal.

## Tests
- Tests updated: none
- Existing tests exercised: test/MemeverseSwapRouter.t.sol
- No-test-change reason: rehearsal only.

## Verification
- Commands run: none.
- Results: none.

## Decision
- Ready to commit: yes
- Residual risks: none.
EOF

PROCESS_RULE_MAP_FILE="$rule_map_path" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$file_list_path" bash ./script/quality-gate.sh
