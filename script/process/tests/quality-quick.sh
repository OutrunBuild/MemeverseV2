#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_dir="$(mktemp -d)"
policy_file="$tmp_dir/policy.json"
rule_map_file="$tmp_dir/rule-map.json"
fake_bin_dir="$tmp_dir/bin"
forge_log="$tmp_dir/forge.log"
npm_log="$tmp_dir/npm.log"
changed_files_path="$tmp_dir/changed-files.txt"
patch_file="$tmp_dir/semantic.patch"
command_output="$tmp_dir/quality-quick.out"

src_file="src/QualityQuickTemp.sol"
swap_file="src/swap/MemeverseSwapRouter.sol"
test_file="test/swap/MemeverseSwapRouterInterface.t.sol"
launcher_file="src/verse/MemeverseLauncher.sol"
launcher_test_file="test/verse/MemeverseLauncherViews.t.sol"
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
  "rule_map": {
    "path": "$rule_map_file",
    "evidence_field": "Existing tests exercised"
  },
  "quality_gate": {
    "swap_src_sol_pattern": "^src/swap/.*\\\\.sol$",
    "src_sol_pattern": "^src/.*\\\\.sol$",
    "test_tsol_pattern": "^test/.*\\\\.t\\\\.sol$",
    "test_sol_pattern": "^test/.*\\\\.sol$",
    "shell_pattern": "^(script/.*\\\\.sh|\\\\.githooks/.*)$",
    "process_surface_pattern": "^(AGENTS\\\\.md|docs/process/.*|\\\\.codex/.*|script/process/.*|\\\\.github/.*|\\\\.githooks/.*|README\\\\.md|docs/reviews/(README|TEMPLATE)\\\\.md|docs/task-briefs/README\\\\.md|docs/agent-reports/README\\\\.md|\\\\.solhint\\\\.json|\\\\.solhintignore)$",
    "process_js_pattern": "^script/process/.*\\\\.js$",
    "package_pattern": "^(package\\\\.json|package-lock\\\\.json)$",
    "docs_contract_pattern": "^(AGENTS\\\\.md|README\\\\.md|docs/process/.*|docs/reviews/(TEMPLATE|README)\\\\.md|docs/(ARCHITECTURE|GLOSSARY|TRACEABILITY|VERIFICATION)\\\\.md|docs/spec/.*|docs/adr/.*|\\\\.github/pull_request_template\\\\.md|\\\\.codex/.*)$",
    "process_selftest_patterns": [
      "^script/process/.*$",
      "^docs/process/.*$",
      "^AGENTS\\\\.md$",
      "^package\\\\.json$",
      "^package-lock\\\\.json$",
      "^\\\\.codex/.*$"
    ],
    "review_note_directory": "docs/reviews",
    "slither_filter_paths": "lib|test|script|node_modules",
    "slither_exclude_detectors": "naming-convention,too-many-digits",
    "process_default_roles": [
      "process-implementer",
      "verifier"
    ],
    "package_default_roles": [
      "process-implementer",
      "verifier"
    ],
    "docs_contract_default_roles": [
      "process-implementer",
      "verifier"
    ]
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
          "test/swap/MemeverseSwapRouterInterface.t.sol"
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
PATH="$fake_bin_dir:$PATH" FORGE_LOG="$forge_log" NPM_LOG="$npm_log" PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" bash ./script/process/quality-quick.sh

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
          "test/swap/MemeverseSwapRouterInterface.t.sol"
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
: > "$command_output"
cat > "$patch_file" <<EOF
diff --git a/$swap_file b/$swap_file
--- a/$swap_file
+++ b/$swap_file
@@ -1 +1 @@
-        return amountOut;
+        return amountOut + 1;
EOF
PATH="$fake_bin_dir:$PATH" FORGE_LOG="$forge_log" NPM_LOG="$npm_log" CHANGE_CLASSIFIER_DIFF_FILE="$patch_file" PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" bash ./script/process/quality-quick.sh > "$command_output" 2>&1

selftest::assert_text_lacks \
    "$(cat "$command_output")" \
    "forced by CHANGE_CLASSIFIER_FORCE=prod-semantic" \
    "Expected swap semantic-path selftest to use the real classifier integration"

if ! grep -q '^test --match-path test/swap/MemeverseSwapRouterInterface.t.sol$' "$forge_log"; then
    echo "Expected quality-quick to run mapped forge test for swap source changes"
    cat "$forge_log"
    exit 1
fi

cat > "$rule_map_file" <<EOF
{
  "version": 2,
  "defaults": {
    "change_requirement_mode": "none",
    "evidence_requirement_mode": "any"
  },
  "rules": [
    {
      "id": "launcher-core",
      "description": "Non-swap formal rules should also drive quick targeted tests.",
      "triggers": {
        "any_of": [
          "$launcher_file"
        ]
      },
      "change_requirement": {
        "mode": "none",
        "tests": [
          "$launcher_test_file"
        ]
      }
    }
  ],
  "testing_gaps": []
}
EOF

cat > "$changed_files_path" <<EOF
$launcher_file
EOF

: > "$forge_log"
: > "$command_output"
cat > "$patch_file" <<EOF
diff --git a/$launcher_file b/$launcher_file
--- a/$launcher_file
+++ b/$launcher_file
@@ -1 +1 @@
-        return currentEpoch;
+        return currentEpoch + 1;
EOF
PATH="$fake_bin_dir:$PATH" FORGE_LOG="$forge_log" NPM_LOG="$npm_log" CHANGE_CLASSIFIER_DIFF_FILE="$patch_file" PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" bash ./script/process/quality-quick.sh > "$command_output" 2>&1

selftest::assert_text_lacks \
    "$(cat "$command_output")" \
    "forced by CHANGE_CLASSIFIER_FORCE=prod-semantic" \
    "Expected non-swap semantic-path selftest to use the real classifier integration"

if ! grep -q "^test --match-path $launcher_test_file$" "$forge_log"; then
    echo "Expected quality-quick to run mapped forge test for non-swap source changes"
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
          "test/swap/MemeverseSwapRouterInterface.t.sol"
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
: > "$command_output"
cat > "$patch_file" <<EOF
diff --git a/$swap_file b/$swap_file
--- a/$swap_file
+++ b/$swap_file
@@ -1 +1 @@
-        return amountOut;
+        return amountOut + 1;
EOF
PATH="$fake_bin_dir:$PATH" FORGE_LOG="$forge_log" NPM_LOG="$npm_log" CHANGE_CLASSIFIER_DIFF_FILE="$patch_file" PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" bash ./script/process/quality-quick.sh > "$command_output" 2>&1

if ! grep -q '^test --match-path test/swap/MemeverseSwapRouterInterface.t.sol$' "$forge_log"; then
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
docs/reviews/README.md
EOF

: > "$forge_log"
: > "$npm_log"
PATH="$fake_bin_dir:$PATH" FORGE_LOG="$forge_log" NPM_LOG="$npm_log" PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" bash ./script/process/quality-quick.sh

if ! grep -q '^run docs:check$' "$npm_log"; then
    echo "Expected quality-quick to run docs:check for docs-contract changes"
    cat "$npm_log"
    exit 1
fi

if [ -s "$forge_log" ]; then
    echo "Did not expect forge commands for docs-contract-only changes"
    cat "$forge_log"
    exit 1
fi

cat > "$changed_files_path" <<EOF
docs/spec/protocol.md
EOF

: > "$forge_log"
: > "$npm_log"
PATH="$fake_bin_dir:$PATH" FORGE_LOG="$forge_log" NPM_LOG="$npm_log" PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" bash ./script/process/quality-quick.sh

if ! grep -q '^run docs:check$' "$npm_log"; then
    echo "Expected quality-quick to run docs:check for product-truth doc changes"
    cat "$npm_log"
    exit 1
fi

if [ -s "$forge_log" ]; then
    echo "Did not expect forge commands for product-truth-doc-only changes"
    cat "$forge_log"
    exit 1
fi

cat > "$changed_files_path" <<EOF
.codex/deleted-agent-contract.md
EOF

: > "$forge_log"
: > "$npm_log"
PATH="$fake_bin_dir:$PATH" FORGE_LOG="$forge_log" NPM_LOG="$npm_log" PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" bash ./script/process/quality-quick.sh

if ! grep -q '^run docs:check$' "$npm_log"; then
    echo "Expected quality-quick to run docs:check for docs-contract deletion paths"
    cat "$npm_log"
    exit 1
fi

if [ -s "$forge_log" ]; then
    echo "Did not expect forge commands for docs-contract deletion paths"
    cat "$forge_log"
    exit 1
fi

cat > "$changed_files_path" <<EOF
package-lock.json
EOF

: > "$forge_log"
: > "$npm_log"
PATH="$fake_bin_dir:$PATH" FORGE_LOG="$forge_log" NPM_LOG="$npm_log" PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" bash ./script/process/quality-quick.sh

if ! grep -q '^run docs:check$' "$npm_log"; then
    echo "Expected quality-quick to run docs:check for package deletion paths"
    cat "$npm_log"
    exit 1
fi

if [ -s "$forge_log" ]; then
    echo "Did not expect forge commands for package deletion paths"
    cat "$forge_log"
    exit 1
fi

cat > "$changed_files_path" <<EOF
$shell_file
EOF

: > "$forge_log"
set +e
PATH="$fake_bin_dir:$PATH" FORGE_LOG="$forge_log" NPM_LOG="$npm_log" PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" bash ./script/process/quality-quick.sh >/dev/null 2>&1
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
