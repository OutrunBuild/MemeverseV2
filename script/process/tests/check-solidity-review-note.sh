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
agent_report_file="$tmp_dir/agent-report.md"
staged_deleted_src="src/swap/MemeverseSwapRouter.sol"
staged_deleted_mapped_test="test/swap/MemeverseSwapRouterInterface.t.sol"
temp_index="$tmp_dir/staged-deletion.index"
malformed_policy_file="$tmp_dir/malformed-owner-prefix-policy.json"

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
    ],
    "field_owners": {
      "Security evidence source": "security-reviewer",
      "Gas evidence source": "gas-reviewer",
      "Verification evidence source": "verifier",
      "Decision evidence source": "main-orchestrator",
      "Rule-map evidence source": "verifier"
    },
    "owner_prefixed_source_fields": [
      "Security evidence source",
      "Gas evidence source",
      "Verification evidence source",
      "Decision evidence source",
      "Rule-map evidence source"
    ]
  },
  "solidity_review_note": {
    "required_fields": [
      "Task Brief path",
      "Agent Report path",
      "Implementation owner",
      "Writer dispatch confirmed"
    ],
    "boolean_fields": [
      "Writer dispatch confirmed"
    ],
    "task_brief_field": "Task Brief path",
    "agent_report_field": "Agent Report path",
    "implementation_owner_field": "Implementation owner",
    "writer_dispatch_confirmed_field": "Writer dispatch confirmed"
  },
  "pull_request": {
    "required_sections": []
  },
  "agents": {
    "main_session_role": "main-orchestrator",
    "main_session_forbidden_write_patterns": [
      "^src/.*\\\\.sol$",
      "^test/.*\\\\.sol$",
      "^test/.*\\\\.t\\\\.sol$"
    ],
    "required_writer_for_patterns": {
      "^src/.*\\\\.sol$": "solidity-implementer",
      "^test/.*\\\\.sol$": "solidity-implementer",
      "^test/.*\\\\.t\\\\.sol$": "solidity-implementer"
    }
  },
  "quality_gate": {
    "review_note_directory": "$review_dir"
  }
}
EOF

cat > "$agent_report_file" <<'EOF'
# Agent Report

- Role: solidity-implementer
- Summary: ok
- Files touched/reviewed: src/Example.sol
- Findings: none
- Required follow-up: none
- Commands run: forge test -vvv
- Evidence: tests
- Residual risks: none
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
- Task Brief path: .codex/templates/task-brief.md
- Agent Report path: __AGENT_REPORT_PATH__
- Implementation owner: solidity-implementer
- Writer dispatch confirmed: yes

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
- Security evidence source: security-reviewer: docs/reviews/security-pass.md
- Security evidence source: security-reviewer: docs/reviews/security-pass.md
- Security evidence source: security-reviewer: docs/reviews/security-pass.md
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
- Gas evidence source: gas-reviewer: docs/reviews/gas-pass.md
- Gas evidence source: gas-reviewer: docs/reviews/gas-pass.md

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

sed -i "s|__AGENT_REPORT_PATH__|$agent_report_file|g" "$review_file"

PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/check-solidity-review-note.sh

rm -f "$review_file"

cat > "$review_file" <<'EOF'
# review-note

## Scope
- Change summary: ok
- Files reviewed: src/Example.sol
- Task Brief path: .codex/templates/task-brief.md
- Agent Report path: __AGENT_REPORT_PATH__
- Implementation owner: solidity-implementer
- Writer dispatch confirmed: yes

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
- Security evidence source: security-reviewer: docs/reviews/security-pass.md

## Simplification
- Candidate simplifications considered: none.
- Applied: none.
- Rejected (with reason): none.

## Gas
- Gas-sensitive paths reviewed: Example.execute
- Gas changes applied: none.
- Gas snapshot/result: unchanged.
- Gas residual risks: none.
- Gas evidence source: gas-reviewer: docs/reviews/gas-pass.md

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
- Verification evidence source: verifier: forge test -vvv

## Decision
- Ready to commit: yes
- Residual risks: none.
- Decision evidence source: main-orchestrator: local decision summary
EOF

sed -i "s|__AGENT_REPORT_PATH__|$agent_report_file|g" "$review_file"

PROCESS_POLICY_FILE="$policy_file" bash ./script/process/check-solidity-review-note.sh

printf '%s\n' "src/Example.sol" > "$changed_files_path"

cat > "$review_file" <<'EOF'
# review-note

## Scope
- Change summary: ok
- Files reviewed: src/Example.sol
- Task Brief path: .codex/templates/task-brief.md
- Agent Report path: __AGENT_REPORT_PATH__
- Implementation owner: main-orchestrator
- Writer dispatch confirmed: yes

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
- Security evidence source: security-reviewer: docs/reviews/security-pass.md

## Simplification
- Candidate simplifications considered: none.
- Applied: none.
- Rejected (with reason): none.

## Gas
- Gas-sensitive paths reviewed: Example.execute
- Gas changes applied: none.
- Gas snapshot/result: unchanged.
- Gas residual risks: none.
- Gas evidence source: gas-reviewer: docs/reviews/gas-pass.md

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
- Verification evidence source: verifier: forge test -vvv

## Decision
- Ready to commit: yes
- Residual risks: none.
- Decision evidence source: main-orchestrator: local decision summary
EOF

sed -i "s|__AGENT_REPORT_PATH__|$agent_report_file|g" "$review_file"

set +e
owner_output="$(PROCESS_POLICY_FILE="$policy_file" PROCESS_RULE_MAP_FILE="$rule_map_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/check-solidity-review-note.sh 2>&1)"
owner_status=$?
set -e

if [ "$owner_status" -eq 0 ]; then
    echo "Expected check-solidity-review-note to fail when Implementation owner matches forbidden main session role"
    exit 1
fi

if ! printf '%s\n' "$owner_output" | grep -q "Implementation owner"; then
    echo "Expected implementation-owner failure output"
    printf '%s\n' "$owner_output"
    exit 1
fi

cat > "$agent_report_file" <<'EOF'
# Agent Report

- Role: process-implementer
- Summary: wrong role
- Files touched/reviewed: src/Example.sol
- Findings: none
- Required follow-up: none
- Commands run: forge test -vvv
- Evidence: tests
- Residual risks: none
EOF

cat > "$review_file" <<'EOF'
# review-note

## Scope
- Change summary: ok
- Files reviewed: src/Example.sol
- Task Brief path: .codex/templates/task-brief.md
- Agent Report path: __AGENT_REPORT_PATH__
- Implementation owner: solidity-implementer
- Writer dispatch confirmed: yes

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
- Security evidence source: security-reviewer: docs/reviews/security-pass.md

## Simplification
- Candidate simplifications considered: none.
- Applied: none.
- Rejected (with reason): none.

## Gas
- Gas-sensitive paths reviewed: Example.execute
- Gas changes applied: none.
- Gas snapshot/result: unchanged.
- Gas residual risks: none.
- Gas evidence source: gas-reviewer: docs/reviews/gas-pass.md

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
- Verification evidence source: verifier: forge test -vvv

## Decision
- Ready to commit: yes
- Residual risks: none.
- Decision evidence source: main-orchestrator: local decision summary
EOF

sed -i "s|__AGENT_REPORT_PATH__|$agent_report_file|g" "$review_file"

set +e
agent_report_output="$(PROCESS_POLICY_FILE="$policy_file" PROCESS_RULE_MAP_FILE="$rule_map_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/check-solidity-review-note.sh 2>&1)"
agent_report_status=$?
set -e

if [ "$agent_report_status" -eq 0 ]; then
    echo "Expected check-solidity-review-note to fail when Agent Report role mismatches Implementation owner"
    exit 1
fi

if ! printf '%s\n' "$agent_report_output" | grep -q "Agent Report path"; then
    echo "Expected agent-report mismatch failure output"
    printf '%s\n' "$agent_report_output"
    exit 1
fi

cat > "$agent_report_file" <<'EOF'
# Agent Report

- Role: solidity-implementer
- Summary: ok
- Files touched/reviewed: src/Example.sol
- Findings: none
- Required follow-up: none
- Commands run: forge test -vvv
- Evidence: tests
- Residual risks: none
EOF

cat > "$review_file" <<'EOF'
# review-note

## Scope
- Change summary: ok
- Files reviewed: src/Example.sol
- Task Brief path: .codex/templates/task-brief.md
- Agent Report path: __AGENT_REPORT_PATH__
- Implementation owner: solidity-implementer
- Writer dispatch confirmed: yes

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
- Security evidence source: security-reviewer: docs/reviews/security-pass.md

## Simplification
- Candidate simplifications considered: none.
- Applied: none.
- Rejected (with reason): none.

## Gas
- Gas-sensitive paths reviewed: Example.execute
- Gas changes applied: none.
- Gas snapshot/result: unchanged.
- Gas residual risks: none.
- Gas evidence source: gas-reviewer: docs/reviews/gas-pass.md

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
- Verification evidence source: verifier: forge test -vvv

## Decision
- Ready to commit: yes
- Residual risks: none.
- Decision evidence source: main-orchestrator: local decision summary
EOF

sed -i "s|__AGENT_REPORT_PATH__|$agent_report_file|g" "$review_file"

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
- Task Brief path: .codex/templates/task-brief.md
- Agent Report path: __AGENT_REPORT_PATH__
- Implementation owner: solidity-implementer
- Writer dispatch confirmed: yes

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

sed -i "s|__AGENT_REPORT_PATH__|$agent_report_file|g" "$review_file"

set +e
missing_source_output="$(PROCESS_POLICY_FILE="$policy_file" PROCESS_RULE_MAP_FILE="$rule_map_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/check-solidity-review-note.sh 2>&1)"
missing_source_status=$?
set -e

if [ "$missing_source_status" -eq 0 ]; then
    echo "Expected check-solidity-review-note to fail when required evidence source fields are missing for src changes"
    exit 1
fi

if ! printf '%s\n' "$missing_source_output" | grep -q "Security evidence source"; then
    echo "Expected missing source-field output to reference Security evidence source"
    printf '%s\n' "$missing_source_output"
    exit 1
fi

cat > "$review_file" <<'EOF'
# review-note

## Scope
- Change summary: ok
- Files reviewed: src/Example.sol
- Task Brief path: .codex/templates/task-brief.md
- Agent Report path: __AGENT_REPORT_PATH__
- Implementation owner: solidity-implementer
- Writer dispatch confirmed: yes

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
- Security evidence source: security-reviewer: docs/reviews/security-pass.md

## Simplification
- Candidate simplifications considered: none.
- Applied: none.
- Rejected (with reason): none.

## Gas
- Gas-sensitive paths reviewed: Example.execute
- Gas changes applied: none.
- Gas snapshot/result: unchanged.
- Gas residual risks: none.
- Gas evidence source: gas-reviewer: docs/reviews/gas-pass.md

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
- Verification evidence source: verifier: forge test -vvv

## Decision
- Ready to commit: yes
- Residual risks: none.
- Decision evidence source: main-orchestrator: local decision summary
EOF

sed -i "s|__AGENT_REPORT_PATH__|$agent_report_file|g" "$review_file"

PROCESS_POLICY_FILE="$policy_file" PROCESS_RULE_MAP_FILE="$rule_map_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/check-solidity-review-note.sh

cat > "$malformed_policy_file" <<EOF
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
    ],
    "field_owners": [],
    "owner_prefixed_source_fields": [
      "Security evidence source",
      "Gas evidence source"
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

set +e
malformed_owner_output="$(PROCESS_POLICY_FILE="$malformed_policy_file" PROCESS_RULE_MAP_FILE="$rule_map_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/check-solidity-review-note.sh 2>&1)"
malformed_owner_status=$?
set -e

if [ "$malformed_owner_status" -eq 0 ]; then
    echo "Expected check-solidity-review-note to fail on malformed review_note.field_owners config"
    exit 1
fi

if ! printf '%s\n' "$malformed_owner_output" | grep -q "review_note.field_owners"; then
    echo "Expected malformed owner-prefixed config output to reference review_note.field_owners"
    printf '%s\n' "$malformed_owner_output"
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
      "id": "staged-delete-evidence",
      "description": "Staged Solidity deletions must still satisfy review-note evidence mapping.",
      "triggers": {
        "any_of": [
          "$staged_deleted_src"
        ]
      },
      "evidence_requirement": {
        "mode": "any",
        "tests": [
          "$staged_deleted_mapped_test"
        ]
      }
    }
  ],
  "testing_gaps": []
}
EOF

cat > "$review_file" <<EOF
# review-note

## Scope
- Change summary: ok
- Files reviewed: $staged_deleted_src
- Task Brief path: .codex/templates/task-brief.md
- Agent Report path: __AGENT_REPORT_PATH__
- Implementation owner: solidity-implementer
- Writer dispatch confirmed: yes

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
- Security evidence source: security-reviewer: docs/reviews/security-pass.md

## Simplification
- Candidate simplifications considered: none.
- Applied: none.
- Rejected (with reason): none.

## Gas
- Gas-sensitive paths reviewed: swap router
- Gas changes applied: none.
- Gas snapshot/result: unchanged.
- Gas residual risks: none.
- Gas evidence source: gas-reviewer: docs/reviews/gas-pass.md

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
- Verification evidence source: verifier: forge test -vvv

## Decision
- Ready to commit: yes
- Residual risks: none.
- Decision evidence source: main-orchestrator: local decision summary
EOF

cat > "$agent_report_file" <<EOF
# Agent Report

- Role: solidity-implementer
- Summary: staged delete
- Files touched/reviewed: $staged_deleted_src
- Findings: none
- Required follow-up: none
- Commands run: forge test -vvv
- Evidence: tests
- Residual risks: none
EOF

sed -i "s|__AGENT_REPORT_PATH__|$agent_report_file|g" "$review_file"

rm -f "$temp_index"
GIT_INDEX_FILE="$temp_index" git read-tree HEAD
GIT_INDEX_FILE="$temp_index" git update-index --force-remove "$staged_deleted_src"

set +e
staged_delete_output="$(GIT_INDEX_FILE="$temp_index" PROCESS_POLICY_FILE="$policy_file" PROCESS_RULE_MAP_FILE="$rule_map_file" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/check-solidity-review-note.sh 2>&1)"
staged_delete_status=$?
set -e

if [ "$staged_delete_status" -eq 0 ]; then
    echo "Expected check-solidity-review-note to fail for staged Solidity deletions missing mapped evidence"
    exit 1
fi

if ! printf '%s\n' "$staged_delete_output" | grep -q "staged-delete-evidence"; then
    echo "Expected staged deletion failure output to reference the staged-delete-evidence rule id"
    printf '%s\n' "$staged_delete_output"
    exit 1
fi

cat > "$review_file" <<EOF
# review-note

## Scope
- Change summary: ok
- Files reviewed: $staged_deleted_src
- Task Brief path: .codex/templates/task-brief.md
- Agent Report path: __AGENT_REPORT_PATH__
- Implementation owner: solidity-implementer
- Writer dispatch confirmed: yes

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
- Security evidence source: security-reviewer: docs/reviews/security-pass.md

## Simplification
- Candidate simplifications considered: none.
- Applied: none.
- Rejected (with reason): none.

## Gas
- Gas-sensitive paths reviewed: swap router
- Gas changes applied: none.
- Gas snapshot/result: unchanged.
- Gas residual risks: none.
- Gas evidence source: gas-reviewer: docs/reviews/gas-pass.md

## Docs
- Docs updated: none
- Why these docs: none.
- No-doc reason: none.

## Tests
- Tests updated: none
- Existing tests exercised: $staged_deleted_mapped_test
- No-test-change reason: none.

## Verification
- Commands run: forge test -vvv
- Results: pass
- Verification evidence source: verifier: forge test -vvv

## Decision
- Ready to commit: yes
- Residual risks: none.
- Decision evidence source: main-orchestrator: local decision summary
EOF

sed -i "s|__AGENT_REPORT_PATH__|$agent_report_file|g" "$review_file"

GIT_INDEX_FILE="$temp_index" PROCESS_POLICY_FILE="$policy_file" PROCESS_RULE_MAP_FILE="$rule_map_file" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/check-solidity-review-note.sh

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

cat > "$agent_report_file" <<'EOF'
# Agent Report

- Role: solidity-implementer
- Summary: ok
- Files touched/reviewed: src/Example.sol
- Findings: none
- Required follow-up: none
- Commands run: forge test -vvv
- Evidence: tests
- Residual risks: none
EOF

cat > "$review_file" <<'EOF'
# review-note

## Scope
- Change summary: ok
- Files reviewed: src/Example.sol
- Task Brief path: .codex/templates/task-brief.md
- Agent Report path: __AGENT_REPORT_PATH__
- Implementation owner: solidity-implementer
- Writer dispatch confirmed: yes

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
- Security evidence source: security-reviewer: docs/reviews/security-pass.md

## Simplification
- Candidate simplifications considered: none.
- Applied: none.
- Rejected (with reason): none.

## Gas
- Gas-sensitive paths reviewed: Example.execute
- Gas changes applied: none.
- Gas snapshot/result: unchanged.
- Gas residual risks: none.
- Gas evidence source: gas-reviewer: docs/reviews/gas-pass.md

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
- Verification evidence source: verifier: forge test -vvv

## Decision
- Ready to commit: yes
- Residual risks: none.
- Decision evidence source: main-orchestrator: local decision summary
EOF

sed -i "s|__AGENT_REPORT_PATH__|$agent_report_file|g" "$review_file"

PROCESS_POLICY_FILE="$policy_file" PROCESS_RULE_MAP_FILE="$rule_map_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/check-solidity-review-note.sh
