#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_dir="$(mktemp -d)"
policy_file="$tmp_dir/policy.json"
rule_map_file="$tmp_dir/rule-map.json"
fake_bin_dir="$tmp_dir/bin"
forge_log="$tmp_dir/forge.log"
npm_log="$tmp_dir/npm.log"
changed_files_path="$tmp_dir/changed-files.txt"

src_file="src/QualityQuickTemp.sol"
swap_file="src/swap/MemeverseSwapRouter.sol"
test_file="test/MemeverseSwapRouterInterface.t.sol"
shell_file="script/process/quality-quick-temp.sh"

cleanup() {
    rm -rf "$tmp_dir"
    git reset -- "$src_file" "$shell_file" >/dev/null 2>&1 || true
    rm -f "$src_file" "$shell_file"
}
trap cleanup EXIT

mkdir -p "$fake_bin_dir"

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

cat > "$rule_map_file" <<'EOF'
{
  "version": 2,
  "defaults": {
    "change_requirement_mode": "none",
    "evidence_requirement_mode": "any"
  },
  "rules": [
    {
      "id": "swap-router-core",
      "description": "Router changes must include mapped test evidence.",
      "triggers": {
        "any_of": [
          "src/swap/MemeverseSwapRouter.sol"
        ]
      },
      "change_requirement": {
        "mode": "any",
        "tests": [
          "test/MemeverseSwapRouterInterface.t.sol"
        ]
      }
    }
  ],
  "testing_gaps": []
}
EOF

cat > "$fake_bin_dir/forge" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${FORGE_LOG}"
exit 0
EOF

cat > "$fake_bin_dir/npm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${NPM_LOG}"
exit 0
EOF

chmod +x "$fake_bin_dir/forge" "$fake_bin_dir/npm"

mkdir -p "$(dirname "$src_file")" "$(dirname "$test_file")" "$(dirname "$shell_file")"

cat > "$src_file" <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract QualityQuickTemp {
    /**
     * @notice Returns the provided value.
     * @dev Temporary source file used to exercise the quality quick flow.
     * @param value Value to return.
     * @return returnedValue The same value that was provided.
     */
    function echo(uint256 value) external pure returns (uint256 returnedValue) {
        return value;
    }
}
EOF

cat > "$shell_file" <<'EOF'
#!/usr/bin/env bash
if [
EOF

cat > "$changed_files_path" <<EOF
$src_file
EOF

: > "$forge_log"
: > "$npm_log"
PATH="$fake_bin_dir:$PATH" FORGE_LOG="$forge_log" NPM_LOG="$npm_log" PROCESS_RULE_MAP_FILE="$rule_map_file" PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" bash ./script/process/quality-quick.sh

if ! grep -q '^fmt --check src/QualityQuickTemp.sol$' "$forge_log"; then
    echo "Expected quality-quick to run forge fmt --check for changed src Solidity files"
    cat "$forge_log"
    exit 1
fi

if ! grep -q '^build$' "$forge_log"; then
    echo "Expected quality-quick to run forge build"
    cat "$forge_log"
    exit 1
fi

if grep -q '^test -vvv$' "$forge_log"; then
    echo "Did not expect quality-quick to run full forge test -vvv"
    cat "$forge_log"
    exit 1
fi

if grep -q 'docs:check' "$npm_log"; then
    echo "Did not expect quality-quick to run docs:check"
    cat "$npm_log"
    exit 1
fi

cat > "$rule_map_file" <<'EOF'
{
  "version": 2,
  "defaults": {
    "change_requirement_mode": "none",
    "evidence_requirement_mode": "any"
  },
  "rules": [
    {
      "id": "swap-router-core",
      "description": "Router changes should still run mapped tests in quick mode.",
      "triggers": {
        "any_of": [
          "src/swap/MemeverseSwapRouter.sol"
        ]
      },
      "change_requirement": {
        "mode": "none",
        "tests": [
          "test/MemeverseSwapRouterInterface.t.sol"
        ]
      }
    }
  ],
  "testing_gaps": []
}
EOF

cat > "$changed_files_path" <<EOF
$swap_file
EOF

: > "$forge_log"
PATH="$fake_bin_dir:$PATH" FORGE_LOG="$forge_log" NPM_LOG="$npm_log" PROCESS_RULE_MAP_FILE="$rule_map_file" PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" bash ./script/process/quality-quick.sh

if ! grep -q '^test --match-path test/MemeverseSwapRouterInterface.t.sol$' "$forge_log"; then
    echo "Expected quality-quick to run mapped forge test for swap source changes"
    cat "$forge_log"
    exit 1
fi

cat > "$rule_map_file" <<'EOF'
{
  "version": 2,
  "defaults": {
    "change_requirement_mode": "none",
    "evidence_requirement_mode": "any"
  },
  "rules": [
    {
      "id": "swap-router-core",
      "description": "Router changes must include mapped test evidence.",
      "triggers": {
        "any_of": [
          "src/swap/MemeverseSwapRouter.sol"
        ]
      },
      "change_requirement": {
        "mode": "any",
        "tests": [
          "test/MemeverseSwapRouterInterface.t.sol"
        ]
      }
    }
  ],
  "testing_gaps": []
}
EOF

cat > "$changed_files_path" <<EOF
$swap_file
$test_file
EOF

: > "$forge_log"
PATH="$fake_bin_dir:$PATH" FORGE_LOG="$forge_log" NPM_LOG="$npm_log" PROCESS_RULE_MAP_FILE="$rule_map_file" PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" bash ./script/process/quality-quick.sh

if ! grep -q '^test --match-path test/MemeverseSwapRouterInterface.t.sol$' "$forge_log"; then
    echo "Expected quality-quick to run targeted forge test for changed or mapped tests"
    cat "$forge_log"
    exit 1
fi

if grep -q '^test -vvv$' "$forge_log"; then
    echo "Did not expect targeted test flow to run full forge test -vvv"
    cat "$forge_log"
    exit 1
fi

cat > "$changed_files_path" <<EOF
$shell_file
EOF

: > "$forge_log"
set +e
PATH="$fake_bin_dir:$PATH" FORGE_LOG="$forge_log" NPM_LOG="$npm_log" PROCESS_RULE_MAP_FILE="$rule_map_file" PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" bash ./script/process/quality-quick.sh >/dev/null 2>&1
status=$?
set -e

if [ "$status" -eq 0 ]; then
    echo "Expected quality-quick to fail on invalid shell syntax"
    exit 1
fi

if [ -s "$forge_log" ]; then
    echo "Did not expect forge commands for shell-only changes"
    cat "$forge_log"
    exit 1
fi
