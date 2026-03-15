#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_dir="$(mktemp -d)"
review_dir="$tmp_dir/reviews"
policy_file="$tmp_dir/policy.json"
rule_map_file="$tmp_dir/rule-map.json"
changed_files_path="$tmp_dir/changed-files.txt"
review_file="$review_dir/2026-03-12-example-review.md"

cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir -p "$review_dir"

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
    ]
  },
  "pull_request": {
    "required_sections": []
  },
  "quality_gate": {
    "review_note_directory": "$review_dir"
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
      "id": "example-core",
      "description": "Example source changes must cite mapped executed tests in review notes.",
      "triggers": {
        "any_of": [
          "src/Example.sol"
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

set +e
missing_output="$(PROCESS_POLICY_FILE="$policy_file" bash ./script/process/check-solidity-review-note.sh 2>&1)"
missing_status=$?
set -e

if [ "$missing_status" -eq 0 ]; then
    echo "Expected check-solidity-review-note to fail when no review note is provided or discoverable"
    exit 1
fi

if ! printf '%s\n' "$missing_output" | grep -q "review note"; then
    echo "Expected missing review note output"
    printf '%s\n' "$missing_output"
    exit 1
fi

cat > "$review_file" <<'EOF'
# review-note

## Scope
- Change summary: ok
- Files reviewed: src/Example.sol

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
- Security review summary: no critical issues.
- Security residual risks: none.
- Gas-sensitive paths reviewed: Example.execute
- Gas changes applied: none.
- Gas snapshot/result: unchanged.
- Gas residual risks: none.

## Simplification
- Candidate simplifications considered: none.
- Applied: none.
- Rejected (with reason): none.

## Gas
- Gas-sensitive paths reviewed: Example.execute
- Gas changes applied: none.
- Gas snapshot/result: unchanged.
- Gas residual risks: none.

## Docs
- Docs updated: none
- Why these docs: none.
- No-doc reason: none.

## Tests
- Tests updated: none
- Existing tests exercised: test/Example.t.sol
- No-test-change reason: none.

## Verification
- Commands run: forge test -vvv
- Results: pass

## Decision
- Ready to commit: yes
- Residual risks: none.
EOF

PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/check-solidity-review-note.sh

rm -f "$review_file"

cat > "$review_file" <<'EOF'
# review-note

## Scope
- Change summary: ok
- Files reviewed: src/Example.sol

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
- Security review summary: no critical issues.
- Security residual risks: none.

## Simplification
- Candidate simplifications considered: none.
- Applied: none.
- Rejected (with reason): none.

## Gas
- Gas-sensitive paths reviewed: Example.execute
- Gas changes applied: none.
- Gas snapshot/result: unchanged.
- Gas residual risks: none.

## Docs
- Docs updated: none
- Why these docs: none.
- No-doc reason: none.

## Tests
- Tests updated: none
- Existing tests exercised: test/Example.t.sol
- No-test-change reason: none.

## Verification
- Commands run: forge test -vvv
- Results: pass

## Decision
- Ready to commit: yes
- Residual risks: none.
EOF

PROCESS_POLICY_FILE="$policy_file" bash ./script/process/check-solidity-review-note.sh

printf '%s\n' "src/Example.sol" > "$changed_files_path"

set +e
evidence_output="$(PROCESS_POLICY_FILE="$policy_file" PROCESS_RULE_MAP_FILE="$rule_map_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/check-solidity-review-note.sh 2>&1)"
evidence_status=$?
set -e

if [ "$evidence_status" -eq 0 ]; then
    echo "Expected check-solidity-review-note to fail when mapped evidence tests are missing from Existing tests exercised"
    exit 1
fi

if ! printf '%s\n' "$evidence_output" | grep -q "example-core"; then
    echo "Expected missing evidence output to reference the triggered rule id"
    printf '%s\n' "$evidence_output"
    exit 1
fi

cat > "$review_file" <<'EOF'
# review-note

## Scope
- Change summary: ok
- Files reviewed: src/Example.sol

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
- Security review summary: no critical issues.
- Security residual risks: none.

## Simplification
- Candidate simplifications considered: none.
- Applied: none.
- Rejected (with reason): none.

## Gas
- Gas-sensitive paths reviewed: Example.execute
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
- No-test-change reason: none.

## Verification
- Commands run: forge test -vvv
- Results: pass

## Decision
- Ready to commit: yes
- Residual risks: none.
EOF

PROCESS_POLICY_FILE="$policy_file" PROCESS_RULE_MAP_FILE="$rule_map_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/check-solidity-review-note.sh

cat > "$rule_map_file" <<'EOF'
{
  "version": 2,
  "rules": [
    {
      "id": "example-none",
      "description": "Mode none should not require evidence.",
      "triggers": {
        "any_of": [
          "src/Example.sol"
        ]
      },
      "evidence_requirement": {
        "mode": "none",
        "tests": [
          "test/MappedEvidence.t.sol"
        ]
      }
    }
  ],
  "testing_gaps": []
}
EOF

cat > "$review_file" <<'EOF'
# review-note

## Scope
- Change summary: ok
- Files reviewed: src/Example.sol

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
- Security review summary: no critical issues.
- Security residual risks: none.

## Simplification
- Candidate simplifications considered: none.
- Applied: none.
- Rejected (with reason): none.

## Gas
- Gas-sensitive paths reviewed: Example.execute
- Gas changes applied: none.
- Gas snapshot/result: unchanged.
- Gas residual risks: none.

## Docs
- Docs updated: none
- Why these docs: none.
- No-doc reason: none.

## Tests
- Tests updated: none
- Existing tests exercised: test/AnotherEvidence.t.sol
- No-test-change reason: none.

## Verification
- Commands run: forge test -vvv
- Results: pass

## Decision
- Ready to commit: yes
- Residual risks: none.
EOF

PROCESS_POLICY_FILE="$policy_file" PROCESS_RULE_MAP_FILE="$rule_map_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/check-solidity-review-note.sh
