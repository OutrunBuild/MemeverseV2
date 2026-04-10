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
path_spec_brief_file="docs/task-briefs/2026-04-10-quality-quick-path-spec-brief.md"
path_spec_writer_report="docs/agent-reports/2026-04-10-quality-quick-path-spec-writer.md"
path_spec_reviewer_report="docs/agent-reports/2026-04-10-quality-quick-path-spec-reviewer.md"
spec_brief_file="docs/task-briefs/2026-04-10-quality-quick-spec-brief.md"
spec_writer_report="docs/agent-reports/2026-04-10-quality-quick-spec-writer.md"
spec_reviewer_report="docs/agent-reports/2026-04-10-quality-quick-spec-reviewer.md"
custom_spec_output="docs/designs/quality-quick-spec-output.md"

cleanup() {
    rm -rf "$tmp_dir"
    git reset -- "$src_file" "$shell_file" "$path_spec_brief_file" "$path_spec_writer_report" "$path_spec_reviewer_report" "$spec_brief_file" "$spec_writer_report" "$spec_reviewer_report" "$custom_spec_output" >/dev/null 2>&1 || true
    rm -f "$src_file" "$shell_file" "$path_spec_brief_file" "$path_spec_writer_report" "$path_spec_reviewer_report" "$spec_brief_file" "$spec_writer_report" "$spec_reviewer_report" "$custom_spec_output"
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
    "spec_surface_pattern": "^(docs/spec/.*|docs/superpowers/specs/.*)$",
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
    ],
    "spec_default_roles": [
      "process-implementer",
      "spec-reviewer",
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
mkdir -p "$(dirname "$spec_brief_file")" "$(dirname "$path_spec_writer_report")" "$(dirname "$custom_spec_output")"

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

cat > "$path_spec_brief_file" <<'EOF'
# Task Brief

- Goal: quality quick path-based spec routing selftest
- Change classification: non-semantic
- Change type: docs
- Files in scope: docs/spec/protocol.md
- Change classification rationale: path-based spec artifact under docs/spec
- Out of scope: none
- Known facts: this brief anchors docs/spec/protocol.md to the spec surface
- Open questions / assumptions: none
- Risks to check: missing spec-surface routing
- Required roles: process-implementer, spec-reviewer, verifier
- Optional roles: none
- Verifier profile: n/a
- Default writer role: process-implementer
- Implementation owner: process-implementer
- Write permissions: docs/spec/protocol.md
- Writer dispatch backend: native-codex-subagents
- Writer dispatch target: .codex/agents/process-implementer.toml
- Writer dispatch scope: docs/spec/protocol.md
- Non-goals: none
- Acceptance checks: rerun process-implementer -> spec-reviewer -> verifier for the latest spec scope
- Required verifier commands: npm run docs:check; npm run process:selftest
- Required artifacts: Task Brief, writer evidence, spec review evidence, verifier evidence
- Review note required: no
- Artifact type: spec
- Spec review required: yes
- Spec artifact paths: docs/spec/protocol.md
- Semantic review dimensions: none
- Source-of-truth docs: none
- External sources required: none
- Critical assumptions to prove or reject: none
- Required output fields: none
- Review note impact: no
- If blocked: stop and return the spec-surface blocker
EOF

cat > "$path_spec_writer_report" <<EOF
# Agent Report

- Role: process-implementer
- Summary: wrote the path-based spec fixture
- Task Brief path: $path_spec_brief_file
- Scope / ownership respected: yes
- Files touched/reviewed: docs/spec/protocol.md
- Findings: none
- Required follow-up: rerun spec-reviewer after a writer update
- Commands run: npm run docs:check
- Evidence: quality-quick selftest fixture
- Residual risks: verifier evidence still pending
EOF

sleep 1

cat > "$path_spec_reviewer_report" <<EOF
# Agent Report

- Role: spec-reviewer
- Summary: reviewed the path-based spec fixture
- Task Brief path: $path_spec_brief_file
- Scope / ownership respected: yes
- Files touched/reviewed: docs/spec/protocol.md
- Findings: none
- Required follow-up: verifier
- Commands run: npm run docs:check
- Evidence: quality-quick selftest fixture
- Residual risks: verifier evidence still pending
EOF

cat > "$custom_spec_output" <<'EOF'
# Quality Quick Spec Output

Custom spec output fixture for brief-declared routing.
EOF

cat > "$spec_writer_report" <<EOF
# Agent Report

- Role: process-implementer
- Summary: wrote the brief-declared spec fixture
- Task Brief path: $spec_brief_file
- Scope / ownership respected: yes
- Files touched/reviewed: $custom_spec_output
- Findings: none
- Required follow-up: rerun spec-reviewer after a writer update
- Commands run: npm run docs:check
- Evidence: quality-quick selftest fixture
- Residual risks: verifier evidence still pending
EOF

sleep 1

cat > "$spec_reviewer_report" <<EOF
# Agent Report

- Role: spec-reviewer
- Summary: reviewed the brief-declared spec fixture
- Task Brief path: $spec_brief_file
- Scope / ownership respected: yes
- Files touched/reviewed: $custom_spec_output
- Findings: none
- Required follow-up: verifier
- Commands run: npm run docs:check
- Evidence: quality-quick selftest fixture
- Residual risks: verifier evidence still pending
EOF

cat > "$spec_brief_file" <<EOF
# Task Brief

- Goal: quality quick spec routing selftest
- Change classification: non-semantic
- Change type: docs
- Files in scope: $custom_spec_output
- Change classification rationale: spec artifact generated outside default docs/spec paths
- Out of scope: none
- Known facts: this brief declares a custom spec artifact path
- Open questions / assumptions: none
- Risks to check: missing spec-surface routing
- Required roles: process-implementer, spec-reviewer, verifier
- Optional roles: none
- Verifier profile: n/a
- Default writer role: process-implementer
- Implementation owner: process-implementer
- Write permissions: $spec_brief_file, $custom_spec_output
- Writer dispatch backend: native-codex-subagents
- Writer dispatch target: .codex/agents/process-implementer.toml
- Writer dispatch scope: $custom_spec_output
- Non-goals: none
- Acceptance checks: rerun process-implementer -> spec-reviewer -> verifier for the latest spec scope
- Required verifier commands: npm run docs:check; npm run process:selftest
- Required artifacts: Task Brief, writer evidence, spec review evidence, verifier evidence
- Review note required: no
- Artifact type: spec
- Spec review required: yes
- Spec artifact paths: $custom_spec_output
- Semantic review dimensions: none
- Source-of-truth docs: none
- External sources required: none
- Critical assumptions to prove or reject: none
- Required output fields: none
- Review note impact: no
- If blocked: stop and return the spec-surface blocker
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
${path_spec_brief_file}
docs/spec/protocol.md
EOF

: > "$forge_log"
: > "$npm_log"
: > "$command_output"
PATH="$fake_bin_dir:$PATH" FORGE_LOG="$forge_log" NPM_LOG="$npm_log" PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" bash ./script/process/quality-quick.sh > "$command_output" 2>&1

if ! grep -q 'default roles: process-implementer; spec-reviewer; verifier' "$command_output"; then
    echo "Expected quality-quick to print spec surface default roles"
    cat "$command_output"
    exit 1
fi

if ! grep -q '^run docs:check$' "$npm_log"; then
    echo "Expected quality-quick to run docs:check for product-truth doc changes"
    cat "$npm_log"
    exit 1
fi

if ! grep -q '^run process:selftest$' "$npm_log"; then
    echo "Expected quality-quick to run process:selftest for product-truth doc changes"
    cat "$npm_log"
    exit 1
fi

if [ -s "$forge_log" ]; then
    echo "Did not expect forge commands for product-truth-doc-only changes"
    cat "$forge_log"
    exit 1
fi

cat > "$changed_files_path" <<EOF
$spec_brief_file
$custom_spec_output
EOF

: > "$forge_log"
: > "$npm_log"
: > "$command_output"
PATH="$fake_bin_dir:$PATH" FORGE_LOG="$forge_log" NPM_LOG="$npm_log" PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" bash ./script/process/quality-quick.sh > "$command_output" 2>&1

if ! grep -q 'default roles: process-implementer; spec-reviewer; verifier' "$command_output"; then
    echo "Expected quality-quick to route brief-declared spec outputs through spec default roles"
    cat "$command_output"
    exit 1
fi

if ! grep -q '^run docs:check$' "$npm_log"; then
    echo "Expected quality-quick to run docs:check for brief-declared spec outputs"
    cat "$npm_log"
    exit 1
fi

if ! grep -q '^run process:selftest$' "$npm_log"; then
    echo "Expected quality-quick to run process:selftest for brief-declared spec outputs"
    cat "$npm_log"
    exit 1
fi

if [ -s "$forge_log" ]; then
    echo "Did not expect forge commands for brief-declared spec outputs"
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
