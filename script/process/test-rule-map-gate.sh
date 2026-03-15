#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_dir="$(mktemp -d)"
source_path="src/swap/RuleMapTemp.sol"
file_list_path="$tmp_dir/changed-files.txt"
rule_map_path="$tmp_dir/rule-map.json"
fake_bin_dir="$tmp_dir/bin"
review_dir="$tmp_dir/reviews"
review_file="$review_dir/2026-03-12-rule-map-review.md"

cleanup() {
    rm -rf "$tmp_dir"
    rm -f "$source_path"
}
trap cleanup EXIT

mkdir -p "$fake_bin_dir"
mkdir -p "$review_dir"

cat > "$fake_bin_dir/npm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

cat > "$fake_bin_dir/forge" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

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

if [ -n "$snapshot_output" ]; then
    cat > "$snapshot_output" <<'SNAPSHOT'
test:example() (gas: 12345)
SNAPSHOT
fi

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
chmod +x "$fake_bin_dir/forge"
chmod +x "$fake_bin_dir/slither"

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
    "slither_filter_paths": "lib|test|script|node_modules",
    "slither_exclude_detectors": "naming-convention,too-many-digits"
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

cat > "$review_file" <<'EOF'
# review-note

## Scope
- Change summary: ok
- Files reviewed: src/swap/RuleMapTemp.sol

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
- Security review summary: none.
- Security residual risks: none.

## Simplification
- Candidate simplifications considered: none.
- Applied: none.
- Rejected (with reason): none.

## Gas
- Gas-sensitive paths reviewed: RuleMapTemp.echo
- Gas changes applied: none.
- Gas snapshot/result: unchanged.
- Gas residual risks: none.

## Docs
- Docs updated: none
- Why these docs: none.
- No-doc reason: none.

## Tests
- Tests updated: none
- Existing tests exercised: test/MemeverseSwapRouter.t.sol
- No-test-change reason: none.

## Verification
- Commands run: forge test -vvv
- Results: pass

## Decision
- Ready to commit: yes
- Residual risks: none.
EOF

cat > "$file_list_path" <<EOF
$source_path
EOF

set +e
output="$(PATH="$fake_bin_dir:$PATH" SLITHER_BIN="$fake_bin_dir/slither" FORGE_BIN="$fake_bin_dir/forge" PROCESS_RULE_MAP_FILE="$rule_map_path" PROCESS_POLICY_FILE="$tmp_dir/policy.json" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$file_list_path" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/quality-gate.sh 2>&1)"
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

PATH="$fake_bin_dir:$PATH" SLITHER_BIN="$fake_bin_dir/slither" FORGE_BIN="$fake_bin_dir/forge" PROCESS_RULE_MAP_FILE="$rule_map_path" PROCESS_POLICY_FILE="$tmp_dir/policy.json" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$file_list_path" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/quality-gate.sh

cat > "$rule_map_path" <<'EOF'
{
  "version": 2,
  "rules": [
    {
      "id": "swap-router-core",
      "description": "Router changes must include mapped test evidence.",
      "triggers": {
        "any_of": [
          "src/swap/RuleMapTemp.sol"
        ]
      },
      "change_requirement": {
        "mode": "any",
        "tests": [
          "test/MemeverseSwapRouter.t.sol"
        ]
      }
    }
  ],
  "testing_gaps": []
}
EOF

cat > "$file_list_path" <<EOF
$source_path
EOF

set +e
output="$(PATH="$fake_bin_dir:$PATH" SLITHER_BIN="$fake_bin_dir/slither" FORGE_BIN="$fake_bin_dir/forge" PROCESS_RULE_MAP_FILE="$rule_map_path" PROCESS_POLICY_FILE="$tmp_dir/policy.json" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$file_list_path" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/quality-gate.sh 2>&1)"
status=$?
set -e

if [ "$status" -eq 0 ]; then
    echo "Expected v2 rule-map enforcement to fail when mapped test evidence is missing"
    exit 1
fi

if ! printf '%s\n' "$output" | grep -q "swap-router-core"; then
    echo "Expected v2 rule-map failure output to reference the missing rule id"
    printf '%s\n' "$output"
    exit 1
fi

cat > "$file_list_path" <<EOF
$source_path
test/MemeverseSwapRouter.t.sol
EOF

PATH="$fake_bin_dir:$PATH" SLITHER_BIN="$fake_bin_dir/slither" FORGE_BIN="$fake_bin_dir/forge" PROCESS_RULE_MAP_FILE="$rule_map_path" PROCESS_POLICY_FILE="$tmp_dir/policy.json" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$file_list_path" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/quality-gate.sh

cat > "$rule_map_path" <<'EOF'
{
  "version": 2,
  "rules": [
    {
      "id": "swap-router-core-none",
      "description": "Router changes with mode none should not require changed tests.",
      "triggers": {
        "any_of": [
          "src/swap/RuleMapTemp.sol"
        ]
      },
      "change_requirement": {
        "mode": "none",
        "tests": [
          "test/MemeverseSwapRouter.t.sol"
        ]
      }
    }
  ],
  "testing_gaps": []
}
EOF

cat > "$file_list_path" <<EOF
$source_path
EOF

PATH="$fake_bin_dir:$PATH" SLITHER_BIN="$fake_bin_dir/slither" FORGE_BIN="$fake_bin_dir/forge" PROCESS_RULE_MAP_FILE="$rule_map_path" PROCESS_POLICY_FILE="$tmp_dir/policy.json" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$file_list_path" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/quality-gate.sh
