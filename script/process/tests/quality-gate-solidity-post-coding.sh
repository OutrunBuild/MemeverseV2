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
slither_log="$tmp_dir/slither.log"
changed_files_path="$tmp_dir/changed-files.txt"
review_dir="$tmp_dir/reviews"
review_file="$review_dir/2026-03-12-example-review.md"
src_file="src/QualityGateTemp.sol"
test_file="test/QualityGateTemp.t.sol"

cleanup() {
    rm -rf "$tmp_dir"
    git reset -- "$src_file" "$test_file" >/dev/null 2>&1 || true
    rm -f "$src_file" "$test_file"
}
trap cleanup EXIT

mkdir -p "$fake_bin_dir" "$review_dir"

cat > "$policy_file" <<EOF
{
  "review_note": {
    "required_headings": [
      "## Scope",
      "## Impact",
      "## Findings",
      "## Simplification",
      "## Gas",
      "## Docs",
      "## Tests",
      "## Verification",
      "## Decision"
    ],
    "required_fields": [
      "Change summary",
      "Files reviewed",
      "Behavior change",
      "ABI change",
      "Storage layout change",
      "Config change",
      "Security review summary",
      "Security residual risks",
      "Gas-sensitive paths reviewed",
      "Gas changes applied",
      "Gas snapshot/result",
      "Gas residual risks",
      "Docs updated",
      "Tests updated",
      "Existing tests exercised",
      "Rule-map evidence source",
      "Commands run",
      "Results",
      "Ready to commit",
      "Residual risks"
    ],
    "boolean_fields": [
      "Behavior change",
      "ABI change",
      "Storage layout change",
      "Config change",
      "Ready to commit"
    ],
    "placeholder_values": [
      "",
      "TBD",
      "<path>",
      "<path>|none",
      "<selectors or paths>",
      "yes/no"
    ],
    "field_owners": {
      "Rule-map evidence source": "verifier"
    },
    "owner_prefixed_source_fields": [
      "Rule-map evidence source"
    ]
  },
  "pull_request": {
    "required_sections": [
      "## Summary",
      "## Impact",
      "## Docs",
      "## Tests",
      "## Verification",
      "## Risks",
      "## Security",
      "## Simplification",
      "## Gas"
    ]
  },
  "rule_map": {
    "path": "$rule_map_file",
    "evidence_field": "Rule-map evidence source"
  },
  "quality_gate": {
    "swap_src_sol_pattern": "^src/swap/.*\\\\.sol$",
    "src_sol_pattern": "^src/.*\\\\.sol$",
    "test_tsol_pattern": "^test/.*\\\\.t\\\\.sol$",
    "test_sol_pattern": "^test/.*\\\\.sol$",
    "shell_pattern": "^(script/.*\\\\.sh|\\\\.githooks/.*)$",
    "package_pattern": "^(package\\\\.json|package-lock\\\\.json)$",
    "docs_contract_pattern": "^(AGENTS\\\\.md|README\\\\.md|docs/process/.*|docs/reviews/(TEMPLATE|README)\\\\.md|docs/(ARCHITECTURE|GLOSSARY|TRACEABILITY|VERIFICATION)\\\\.md|docs/spec/.*|docs/adr/.*|\\\\.github/pull_request_template\\\\.md|\\\\.codex/.*)$",
    "review_note_directory": "$review_dir",
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
      "id": "quality-gate-temp-evidence",
      "description": "QualityGateTemp source changes must cite mapped review-note evidence.",
      "triggers": {
        "any_of": [
          "src/QualityGateTemp.sol"
        ]
      },
      "evidence_requirement": {
        "mode": "any",
        "tests": [
          "test/MappedEvidence.t.sol"
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

cat > "$fake_bin_dir/npm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${NPM_LOG}"
exit 0
EOF

cat > "$fake_bin_dir/slither" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

json_output=""
captured_args=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --json)
            json_output="$2"
            shift 2
            ;;
        *)
            captured_args+=("$1")
            shift
            ;;
    esac
done

printf '%s\n' "${captured_args[*]}" >> "${SLITHER_LOG}"

cat > "$json_output" <<'JSON'
{"success":true,"results":{"detectors":[{"check":"arbitrary-send-eth","impact":"High","confidence":"Medium","elements":[{"type":"function","name":"doThing","source_mapping":{"filename_relative":"src/QualityGateTemp.sol","lines":[8,9]}}]}]}}
JSON
exit 0
EOF

chmod +x "$fake_bin_dir/forge" "$fake_bin_dir/npm" "$fake_bin_dir/slither"

cat > "$src_file" <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract QualityGateTemp {
    /**
     * @notice Returns the provided value.
     * @dev Temporary source file used to exercise the post-coding quality gate.
     * @param value Value to return.
     * @return returnedValue The same value that was provided.
     */
    function echo(uint256 value) external pure returns (uint256 returnedValue) {
        return value;
    }
}
EOF

cat > "$test_file" <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract QualityGateTempTest {}
EOF

cat > "$review_file" <<'EOF'
# review-note

## Scope
- Change summary: ok
- Files reviewed: src/QualityGateTemp.sol

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
- Gas-sensitive paths reviewed: QualityGateTemp.echo
- Gas changes applied: none.
- Gas snapshot/result: unchanged.
- Gas residual risks: none.

## Docs
- Docs updated: none
- Why these docs: none.
- No-doc reason: none.

## Tests
- Tests updated: none
- Existing tests exercised: test/QualityGateTemp.t.sol
- Rule-map evidence source: verifier:test/QualityGateTemp.t.sol
- No-test-change reason: none.

## Verification
- Commands run: forge test -vvv
- Results: pass

## Decision
- Ready to commit: yes
- Residual risks: none.
EOF

set +e
git add "$src_file"

missing_evidence_output="$(PATH="$fake_bin_dir:$PATH" PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_REVIEW_NOTE="$review_file" FORGE_LOG="$forge_log" NPM_LOG="$npm_log" SLITHER_LOG="$slither_log" bash ./script/process/quality-gate.sh 2>&1)"
missing_evidence_status=$?
set -e

if [ "$missing_evidence_status" -eq 0 ]; then
    echo "Expected quality-gate to fail when rule-map evidence is missing from Rule-map evidence source"
    exit 1
fi

if ! printf '%s\n' "$missing_evidence_output" | grep -q "quality-gate-temp-evidence"; then
    echo "Expected quality-gate evidence failure output to reference the triggered rule id"
    printf '%s\n' "$missing_evidence_output"
    exit 1
fi

cat > "$review_file" <<'EOF'
# review-note

## Scope
- Change summary: ok
- Files reviewed: src/QualityGateTemp.sol

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
- Gas-sensitive paths reviewed: QualityGateTemp.echo
- Gas changes applied: none.
- Gas snapshot/result: unchanged.
- Gas residual risks: none.

## Docs
- Docs updated: none
- Why these docs: none.
- No-doc reason: none.

## Tests
- Tests updated: none
- Existing tests exercised: test/MappedEvidence.t.sol
- Rule-map evidence source: verifier:test/MappedEvidence.t.sol
- No-test-change reason: none.

## Verification
- Commands run: forge test -vvv
- Results: pass

## Decision
- Ready to commit: yes
- Residual risks: none.
EOF

PATH="$fake_bin_dir:$PATH" PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_REVIEW_NOTE="$review_file" FORGE_LOG="$forge_log" NPM_LOG="$npm_log" SLITHER_LOG="$slither_log" bash ./script/process/quality-gate.sh

git reset -- "$src_file" >/dev/null

printf '%s\n' "$src_file" > "$changed_files_path"

if ! grep -q "^snapshot --snap " "$forge_log"; then
    echo "Expected quality-gate to trigger the gas report command for Solidity source changes"
    cat "$forge_log"
    exit 1
fi

if ! grep -q "^\\. --filter-paths lib|test|script|node_modules --exclude-dependencies --exclude naming-convention,too-many-digits$" "$slither_log"; then
    echo "Expected quality-gate to trigger slither for Solidity source changes"
    cat "$slither_log"
    exit 1
fi

if ! grep -q "run docs:check" "$npm_log"; then
    echo "Expected quality-gate to run docs:check for Solidity source changes"
    cat "$npm_log"
    exit 1
fi

cat > "$review_file" <<'EOF'
# review-note

## Scope
- Change summary: ok
- Files reviewed: src/QualityGateTemp.sol

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
- Gas-sensitive paths reviewed: QualityGateTemp.echo
- Gas changes applied: none.
- Gas snapshot/result: unchanged.
- Gas residual risks: none.

## Docs
- Docs updated: none
- Why these docs: none.
- No-doc reason: none.

## Tests
- Tests updated: none
- Existing tests exercised: test/QualityGateTemp.t.sol
- Rule-map evidence source: verifier:test/QualityGateTemp.t.sol
- No-test-change reason: none.

## Verification
- Commands run: forge test -vvv
- Results: pass

## Decision
- Ready to commit: yes
- Residual risks: none.
EOF

set +e
missing_ci_evidence_output="$(PATH="$fake_bin_dir:$PATH" PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$review_file" FORGE_LOG="$forge_log" NPM_LOG="$npm_log" SLITHER_LOG="$slither_log" bash ./script/process/quality-gate.sh 2>&1)"
missing_ci_evidence_status=$?
set -e

if [ "$missing_ci_evidence_status" -eq 0 ]; then
    echo "Expected quality-gate in ci mode to fail when rule-map evidence is missing from Rule-map evidence source"
    exit 1
fi

if ! printf '%s\n' "$missing_ci_evidence_output" | grep -q "quality-gate-temp-evidence"; then
    echo "Expected ci evidence failure output to reference the triggered rule id"
    printf '%s\n' "$missing_ci_evidence_output"
    exit 1
fi

cat > "$review_file" <<'EOF'
# review-note

## Scope
- Change summary: ok
- Files reviewed: src/QualityGateTemp.sol

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
- Gas-sensitive paths reviewed: QualityGateTemp.echo
- Gas changes applied: none.
- Gas snapshot/result: unchanged.
- Gas residual risks: none.

## Docs
- Docs updated: none
- Why these docs: none.
- No-doc reason: none.

## Tests
- Tests updated: none
- Existing tests exercised: test/MappedEvidence.t.sol
- Rule-map evidence source: verifier:test/MappedEvidence.t.sol
- No-test-change reason: none.

## Verification
- Commands run: forge test -vvv
- Results: pass

## Decision
- Ready to commit: yes
- Residual risks: none.
EOF

PATH="$fake_bin_dir:$PATH" PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$review_file" FORGE_LOG="$forge_log" NPM_LOG="$npm_log" SLITHER_LOG="$slither_log" bash ./script/process/quality-gate.sh

: > "$forge_log"
: > "$npm_log"
rm -f "$slither_log"
printf '%s\n' "$test_file" > "$changed_files_path"

PATH="$fake_bin_dir:$PATH" PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$tmp_dir/missing-review.md" FORGE_LOG="$forge_log" NPM_LOG="$npm_log" SLITHER_LOG="$slither_log" bash ./script/process/quality-gate.sh

if [ -f "$slither_log" ] && [ -s "$slither_log" ]; then
    echo "Expected slither not to run for test-only changes"
    cat "$slither_log"
    exit 1
fi

if grep -q "^snapshot --snap " "$forge_log"; then
    echo "Expected gas report not to run for test-only changes"
    cat "$forge_log"
    exit 1
fi

: > "$forge_log"
: > "$npm_log"
rm -f "$slither_log"
printf '%s\n' "docs/reviews/README.md" > "$changed_files_path"

PATH="$fake_bin_dir:$PATH" PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$tmp_dir/missing-review.md" FORGE_LOG="$forge_log" NPM_LOG="$npm_log" SLITHER_LOG="$slither_log" bash ./script/process/quality-gate.sh

if ! grep -q "^run docs:check$" "$npm_log"; then
    echo "Expected quality-gate to run docs:check for docs-contract changes"
    cat "$npm_log"
    exit 1
fi

if [ -s "$forge_log" ]; then
    echo "Did not expect forge commands for docs-contract-only changes"
    cat "$forge_log"
    exit 1
fi

if [ -f "$slither_log" ] && [ -s "$slither_log" ]; then
    echo "Did not expect slither for docs-contract-only changes"
    cat "$slither_log"
    exit 1
fi

: > "$forge_log"
: > "$npm_log"
rm -f "$slither_log"
printf '%s\n' "docs/spec/protocol.md" > "$changed_files_path"

PATH="$fake_bin_dir:$PATH" PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$tmp_dir/missing-review.md" FORGE_LOG="$forge_log" NPM_LOG="$npm_log" SLITHER_LOG="$slither_log" bash ./script/process/quality-gate.sh

if ! grep -q "^run docs:check$" "$npm_log"; then
    echo "Expected quality-gate to run docs:check for product-truth doc changes"
    cat "$npm_log"
    exit 1
fi

if [ -s "$forge_log" ]; then
    echo "Did not expect forge commands for product-truth-doc-only changes"
    cat "$forge_log"
    exit 1
fi

if [ -f "$slither_log" ] && [ -s "$slither_log" ]; then
    echo "Did not expect slither for product-truth-doc-only changes"
    cat "$slither_log"
    exit 1
fi

: > "$forge_log"
: > "$npm_log"
rm -f "$slither_log"
printf '%s\n' ".codex/deleted-agent-contract.md" > "$changed_files_path"

PATH="$fake_bin_dir:$PATH" PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$tmp_dir/missing-review.md" FORGE_LOG="$forge_log" NPM_LOG="$npm_log" SLITHER_LOG="$slither_log" bash ./script/process/quality-gate.sh

if ! grep -q "^run docs:check$" "$npm_log"; then
    echo "Expected quality-gate to run docs:check for docs-contract deletion paths"
    cat "$npm_log"
    exit 1
fi

if [ -s "$forge_log" ]; then
    echo "Did not expect forge commands for docs-contract deletion paths"
    cat "$forge_log"
    exit 1
fi

if [ -f "$slither_log" ] && [ -s "$slither_log" ]; then
    echo "Did not expect slither for docs-contract deletion paths"
    cat "$slither_log"
    exit 1
fi

: > "$forge_log"
: > "$npm_log"
rm -f "$slither_log"
printf '%s\n' "package-lock.json" > "$changed_files_path"

PATH="$fake_bin_dir:$PATH" PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$tmp_dir/missing-review.md" FORGE_LOG="$forge_log" NPM_LOG="$npm_log" SLITHER_LOG="$slither_log" bash ./script/process/quality-gate.sh

if ! grep -q "^run docs:check$" "$npm_log"; then
    echo "Expected quality-gate to run docs:check for package deletion paths"
    cat "$npm_log"
    exit 1
fi

if ! grep -q "^ci$" "$npm_log"; then
    echo "Expected quality-gate to run npm ci for package deletion paths"
    cat "$npm_log"
    exit 1
fi

if [ -s "$forge_log" ]; then
    echo "Did not expect forge commands for package deletion paths"
    cat "$forge_log"
    exit 1
fi

if [ -f "$slither_log" ] && [ -s "$slither_log" ]; then
    echo "Did not expect slither for package deletion paths"
    cat "$slither_log"
    exit 1
fi

: > "$forge_log"
: > "$npm_log"
rm -f "$slither_log"
printf '%s\n' "src/DeletedQualityGateTemp.sol" > "$changed_files_path"

PATH="$fake_bin_dir:$PATH" PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$review_file" FORGE_LOG="$forge_log" NPM_LOG="$npm_log" SLITHER_LOG="$slither_log" bash ./script/process/quality-gate.sh

if ! grep -q "^snapshot --snap " "$forge_log"; then
    echo "Expected quality-gate to run gas report for src Solidity deletion paths"
    cat "$forge_log"
    exit 1
fi

if ! grep -q "^\\. --filter-paths lib|test|script|node_modules --exclude-dependencies --exclude naming-convention,too-many-digits$" "$slither_log"; then
    echo "Expected quality-gate to run slither for src Solidity deletion paths"
    cat "$slither_log"
    exit 1
fi
