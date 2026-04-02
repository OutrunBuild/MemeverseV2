#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_dir="$(mktemp -d)"
review_dir="$tmp_dir/reviews"
agent_report_dir="$tmp_dir/agent-reports"
task_brief_dir="$tmp_dir/task-briefs"
policy_file="$tmp_dir/policy.json"
changed_files_path="$tmp_dir/changed-files.txt"
mixed_changed_files_path="$tmp_dir/mixed-changed-files.txt"
review_file="$review_dir/2026-03-27-example-review.md"
unrelated_review_file="$review_dir/2026-03-28-unrelated-review.md"
agent_report_file="$agent_report_dir/2026-03-27-example-implementer-report.md"
unrelated_agent_report_file="$agent_report_dir/2026-03-28-unrelated-implementer-report.md"
task_brief_file="$task_brief_dir/2026-03-27-example-task-brief.md"
logic_evidence_file="$review_dir/logic-pass.md"
security_evidence_file="$review_dir/security-pass.md"
gas_evidence_file="$review_dir/gas-pass.md"
verification_evidence_file="$review_dir/verification-pass.md"

cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir -p "$review_dir"
mkdir -p "$agent_report_dir"
mkdir -p "$task_brief_dir"

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
      "Task Brief path",
      "Agent Report path",
      "Implementation owner",
      "Writer dispatch confirmed",
      "Semantic dimensions reviewed",
      "Source-of-truth docs checked",
      "External facts checked",
      "Local control-flow facts checked",
      "Evidence chain complete",
      "Semantic alignment summary",
      "Behavior change",
      "ABI change",
      "Storage layout change",
      "Config change",
      "Logic review summary",
      "Logic residual risks",
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
      "Logic evidence source",
      "Security evidence source",
      "Gas evidence source",
      "Verification evidence source",
      "Decision evidence source",
      "Ready to commit",
      "Residual risks"
    ],
    "boolean_fields": [
      "Writer dispatch confirmed",
      "Evidence chain complete",
      "Behavior change",
      "ABI change",
      "Storage layout change",
      "Config change",
      "Ready to commit"
    ],
    "field_owners": {
      "Task Brief path": "main-orchestrator",
      "Agent Report path": "main-orchestrator",
      "Implementation owner": "main-orchestrator",
      "Writer dispatch confirmed": "main-orchestrator",
      "Logic review summary": "logic-reviewer",
      "Logic residual risks": "logic-reviewer",
      "Logic evidence source": "logic-reviewer",
      "Security evidence source": "security-reviewer",
      "Gas evidence source": "gas-reviewer",
      "Verification evidence source": "verifier",
      "Decision evidence source": "main-orchestrator"
    },
    "owner_prefixed_source_fields": [
      "Logic evidence source",
      "Security evidence source",
      "Gas evidence source",
      "Verification evidence source",
      "Decision evidence source"
    ],
    "placeholder_values": [
      "",
      "TBD",
      "<path>",
      "<path>|none",
      "<selectors or paths>",
      "<agent-report-path>",
      "<verification-source>",
      "<decision-source>",
      "yes/no"
    ]
  },
  "solidity_review_note": {
    "required_fields": [
      "Task Brief path",
      "Agent Report path",
      "Implementation owner",
      "Writer dispatch confirmed",
      "Semantic dimensions reviewed",
      "Source-of-truth docs checked",
      "External facts checked",
      "Local control-flow facts checked",
      "Evidence chain complete",
      "Semantic alignment summary",
      "Logic review summary",
      "Logic residual risks",
      "Logic evidence source"
    ],
    "boolean_fields": [
      "Writer dispatch confirmed",
      "Evidence chain complete"
    ],
    "task_brief_field": "Task Brief path",
    "agent_report_field": "Agent Report path",
    "implementation_owner_field": "Implementation owner",
    "writer_dispatch_confirmed_field": "Writer dispatch confirmed",
    "semantic_dimensions_field": "Semantic dimensions reviewed",
    "source_of_truth_field": "Source-of-truth docs checked",
    "external_facts_field": "External facts checked",
    "local_control_flow_field": "Local control-flow facts checked",
    "evidence_chain_field": "Evidence chain complete",
    "semantic_alignment_summary_field": "Semantic alignment summary",
    "critical_assumptions_field": "Semantic alignment summary",
    "task_brief_semantic_dimensions_field": "Semantic review dimensions",
    "task_brief_source_of_truth_field": "Source-of-truth docs",
    "task_brief_external_sources_field": "External sources required",
    "task_brief_critical_assumptions_field": "Critical assumptions to prove or reject",
    "task_brief_files_in_scope_field": "Files in scope",
    "task_brief_default_writer_role_field": "Default writer role",
    "task_brief_write_permissions_field": "Write permissions",
    "semantic_sensitive_patterns": [
      "^src/assets/.*\\\\.sol$",
      "^src/position/.*\\\\.sol$",
      "^src/yield/.*\\\\.sol$",
      "^src/router/.*\\\\.sol$",
      "^src/integrations/.*\\\\.sol$",
      "^src/libraries/.*\\\\.sol$"
    ]
  },
  "task_brief": {
    "required_fields": [
      "Goal",
      "Change type",
      "Files in scope",
      "Risks to check",
      "Required roles",
      "Optional roles",
      "Default writer role",
      "Implementation owner",
      "Write permissions",
      "Writer dispatch backend",
      "Writer dispatch target",
      "Writer dispatch scope",
      "Non-goals",
      "Acceptance checks",
      "Required verifier commands",
      "Required artifacts",
      "Review note required",
      "Semantic review dimensions",
      "Source-of-truth docs",
      "External sources required",
      "Critical assumptions to prove or reject",
      "Required output fields",
      "Review note impact"
    ],
    "boolean_fields": [
      "Review note required"
    ],
    "required_roles_field": "Required roles",
    "required_verifier_commands_field": "Required verifier commands",
    "review_note_required_field": "Review note required",
    "dispatch_backend_field": "Writer dispatch backend",
    "dispatch_target_field": "Writer dispatch target"
  },
  "agent_report": {
    "required_fields": [
      "Role",
      "Summary",
      "Task Brief path",
      "Scope / ownership respected",
      "Files touched/reviewed",
      "Residual risks"
    ],
    "boolean_fields": [
      "Scope / ownership respected"
    ],
    "task_brief_field": "Task Brief path",
    "scope_respected_field": "Scope / ownership respected",
    "role_field": "Role",
    "files_field": "Files touched/reviewed"
  },
  "agents": {
    "main_session_role": "main-orchestrator",
    "agent_report_directory": "$agent_report_dir",
    "task_brief_directory": "$task_brief_dir",
    "main_session_forbidden_write_patterns": [
      "^src/.*\\\\.sol$",
      "^test/.*\\\\.sol$",
      "^test/.*\\\\.t\\\\.sol$",
      "^script/.*\\\\.sh$"
    ],
    "required_writer_for_patterns": {
      "^src/.*\\\\.sol$": "solidity-implementer",
      "^test/.*\\\\.sol$": "solidity-implementer",
      "^test/.*\\\\.t\\\\.sol$": "solidity-implementer"
    }
  },
  "quality_gate": {
    "review_note_directory": "$review_dir",
    "src_default_roles": [
      "solidity-implementer",
      "logic-reviewer",
      "security-reviewer",
      "gas-reviewer",
      "verifier"
    ],
    "test_default_roles": [
      "solidity-implementer",
      "logic-reviewer",
      "verifier"
    ]
  },
  "change_classifier": {
    "role_matrix": {
      "non-semantic": {
        "required_roles": [
          "verifier"
        ],
        "verifier_profile": "light"
      },
      "prod-semantic": {
        "required_roles": [
          "logic-reviewer",
          "security-reviewer",
          "gas-reviewer",
          "verifier"
        ],
        "verifier_profile": "full"
      },
      "high-risk": {
        "required_roles": [
          "logic-reviewer",
          "security-reviewer",
          "gas-reviewer",
          "verifier"
        ],
        "verifier_profile": "full"
      }
    }
  },
  "verifier": {
    "codex_review": {
      "task_brief_token": "npm run codex:review"
    },
    "local_codex_review": {
      "required_classifications": [
        "prod-semantic",
        "high-risk"
      ],
      "force_env": "FORCE_CODEX_REVIEW"
    }
  }
}
EOF

cat > "$changed_files_path" <<'EOF'
src/Example.sol
EOF

cat > "$mixed_changed_files_path" <<'EOF'
src/Example.sol
test/Example.t.sol
EOF

write_task_brief() {
    local semantic_dimensions="${1:-none}"
    local source_docs="${2:-none}"
    local external_sources="${3:-none}"
    local assumptions="${4:-none}"
    local classification="${5:-prod-semantic}"
    local required_roles="${6:-solidity-implementer, logic-reviewer, security-reviewer, gas-reviewer, verifier}"
    local required_verifier_commands="${7:-npm run codex:review; forge fmt --check; forge build; forge test -vvv; bash ./script/process/check-solidity-review-note.sh}"

    cat > "$task_brief_file" <<EOF
# Task Brief

- Goal: temporary selftest fixture
- Change classification: $classification
- Change type: none
- Files in scope: src/Example.sol
- Out of scope: none
- Known facts: none
- Open questions / assumptions: none
- Risks to check: none
- Required roles: $required_roles
- Optional roles: none
- Default writer role: solidity-implementer
- Implementation owner: solidity-implementer
- Write permissions: src/Example.sol
- Writer dispatch backend: native-codex-subagents
- Writer dispatch target: .codex/agents/solidity-implementer.toml
- Writer dispatch scope: src/Example.sol
- Non-goals: none
- Acceptance checks: none
- Required verifier commands: $required_verifier_commands
- Required artifacts: Task Brief, Agent Report, review note
- Review note required: yes
- Semantic review dimensions: $semantic_dimensions
- Source-of-truth docs: $source_docs
- External sources required: $external_sources
- Critical assumptions to prove or reject: $assumptions
- Required output fields: none
- Review note impact: no
- If blocked: stop and return the missing input or failing field
EOF
}

write_agent_report() {
    local role="$1"
    local files="$2"
    local output_file="${3:-$agent_report_file}"

    cat > "$output_file" <<EOF
# Agent Report

- Role: $role
- Summary: ok
- Task Brief path: $task_brief_file
- Scope / ownership respected: yes
- Files touched/reviewed: $files
- Residual risks: none
EOF
}

write_review_evidence_files() {
    cat > "$logic_evidence_file" <<EOF
# Logic Evidence

- reviewer: logic-reviewer
- status: pass
EOF

    cat > "$security_evidence_file" <<EOF
# Security Evidence

- reviewer: security-reviewer
- status: pass
EOF

    cat > "$gas_evidence_file" <<EOF
# Gas Evidence

- reviewer: gas-reviewer
- status: pass
EOF

    cat > "$verification_evidence_file" <<EOF
# Verification Evidence

- reviewer: verifier
- status: pass
EOF
}

write_review_note() {
    local implementation_owner="$1"
    local writer_dispatch="$2"
    local output_file="${3:-$review_file}"

    write_review_evidence_files

    cat > "$output_file" <<'EOF'
# review-note

## Scope
- Change summary: ok
- Files reviewed: src/Example.sol
- Task Brief path: __TASK_BRIEF_PATH__
- Agent Report path: __AGENT_REPORT_PATH__
- Implementation owner: __IMPLEMENTATION_OWNER__
- Writer dispatch confirmed: __WRITER_DISPATCH__
- Semantic dimensions reviewed: reward/accounting; external integration
- Source-of-truth docs checked: AGENTS.md; docs/process/review-notes.md
- External facts checked: docs/upstream/external-source.md
- Local control-flow facts checked: reward index updates after balance deltas
- Evidence chain complete: yes
- Semantic alignment summary: reviewed reward/accounting and external integration expectations against the task brief and local control flow

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
- Logic review summary: local control flow and state transitions match the task brief.
- Logic residual risks: none.
- Logic evidence source: logic-reviewer: __LOGIC_EVIDENCE_PATH__
- Security review summary: no critical issues.
- Security residual risks: none.
- Security evidence source: security-reviewer: __SECURITY_EVIDENCE_PATH__

## Simplification
- Candidate simplifications considered: none.
- Applied: none.
- Rejected (with reason): none.

## Gas
- Gas-sensitive paths reviewed: Example.execute
- Gas changes applied: none.
- Gas snapshot/result: unchanged.
- Gas residual risks: none.
- Gas evidence source: gas-reviewer: __GAS_EVIDENCE_PATH__

## Docs
- Docs updated: none
- Why these docs: none.
- No-doc reason: none.

## Tests
- Tests updated: none
- Existing tests exercised: test/Example.t.sol
- No-test-change reason: none.

## Verification
- Commands run: npm run codex:review; forge test -vvv
- Results: pass
- Codex review summary: no additional findings.
- Codex review evidence source: verifier: npm run codex:review
- Verification evidence source: verifier: __VERIFICATION_EVIDENCE_PATH__

## Decision
- Ready to commit: yes
- Residual risks: none.
- Decision evidence source: main-orchestrator: local decision summary
EOF

    sed -i "s|__AGENT_REPORT_PATH__|$agent_report_file|g" "$output_file"
    sed -i "s|__TASK_BRIEF_PATH__|$task_brief_file|g" "$output_file"
    sed -i "s|__IMPLEMENTATION_OWNER__|$implementation_owner|g" "$output_file"
    sed -i "s|__WRITER_DISPATCH__|$writer_dispatch|g" "$output_file"
    sed -i "s|__LOGIC_EVIDENCE_PATH__|$logic_evidence_file|g" "$output_file"
    sed -i "s|__SECURITY_EVIDENCE_PATH__|$security_evidence_file|g" "$output_file"
    sed -i "s|__GAS_EVIDENCE_PATH__|$gas_evidence_file|g" "$output_file"
    sed -i "s|__VERIFICATION_EVIDENCE_PATH__|$verification_evidence_file|g" "$output_file"

    # Memeverse freshness checks require reviewer/verifier artifacts to postdate the writer report.
    touch -m -d '+5 seconds' "$logic_evidence_file" "$security_evidence_file" "$gas_evidence_file" "$verification_evidence_file"
}

write_task_brief

set +e
missing_output="$(CHANGE_CLASSIFIER_FORCE=prod-semantic PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" bash ./script/process/check-solidity-review-note.sh 2>&1)"
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

write_agent_report "solidity-implementer" "src/Example.sol"
write_review_evidence_files
write_review_note "solidity-implementer" "yes"
CHANGE_CLASSIFIER_FORCE=prod-semantic PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/check-solidity-review-note.sh

mkdir -p "$tmp_dir/outside-briefs"
mv "$task_brief_file" "$tmp_dir/outside-briefs/2026-03-27-example-task-brief.md"
task_brief_file="$tmp_dir/outside-briefs/2026-03-27-example-task-brief.md"
write_review_note "solidity-implementer" "yes"
set +e
brief_directory_output="$(CHANGE_CLASSIFIER_FORCE=prod-semantic PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/check-solidity-review-note.sh 2>&1)"
brief_directory_status=$?
set -e

if [ "$brief_directory_status" -eq 0 ]; then
    echo "Expected check-solidity-review-note to fail when Task Brief path is outside the configured task-brief directory"
    exit 1
fi

if ! printf '%s\n' "$brief_directory_output" | grep -q "task-brief directory"; then
    echo "Expected out-of-directory output to reference the configured task-brief directory"
    printf '%s\n' "$brief_directory_output"
    exit 1
fi

task_brief_file="$task_brief_dir/2026-03-27-example-task-brief.md"
write_task_brief
write_review_note "solidity-implementer" "yes"

mkdir -p "$tmp_dir/outside"
mv "$agent_report_file" "$tmp_dir/outside/2026-03-27-example-implementer-report.md"
agent_report_file="$tmp_dir/outside/2026-03-27-example-implementer-report.md"
write_review_note "solidity-implementer" "yes"
set +e
directory_output="$(CHANGE_CLASSIFIER_FORCE=prod-semantic PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/check-solidity-review-note.sh 2>&1)"
directory_status=$?
set -e

if [ "$directory_status" -eq 0 ]; then
    echo "Expected check-solidity-review-note to fail when Agent Report path is outside the configured agent-report directory"
    exit 1
fi

if ! printf '%s\n' "$directory_output" | grep -q "agent-report directory"; then
    echo "Expected out-of-directory output to reference the configured agent-report directory"
    printf '%s\n' "$directory_output"
    exit 1
fi

agent_report_file="$agent_report_dir/2026-03-27-example-implementer-report.md"
write_agent_report "solidity-implementer" "src/Example.sol"
write_review_note "solidity-implementer" "yes"

write_agent_report "solidity-implementer" "src/Example.sol"
write_review_note "main-orchestrator" "yes"
set +e
owner_output="$(CHANGE_CLASSIFIER_FORCE=prod-semantic PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/check-solidity-review-note.sh 2>&1)"
owner_status=$?
set -e

if [ "$owner_status" -eq 0 ]; then
    echo "Expected check-solidity-review-note to fail when Implementation owner is the forbidden main session role"
    exit 1
fi

if ! printf '%s\n' "$owner_output" | grep -q "Implementation owner"; then
    echo "Expected forbidden-owner output to reference Implementation owner"
    printf '%s\n' "$owner_output"
    exit 1
fi

write_agent_report "process-implementer" "src/Example.sol"
write_review_note "solidity-implementer" "yes"
set +e
role_output="$(CHANGE_CLASSIFIER_FORCE=prod-semantic PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/check-solidity-review-note.sh 2>&1)"
role_status=$?
set -e

if [ "$role_status" -eq 0 ]; then
    echo "Expected check-solidity-review-note to fail when Agent Report role mismatches Implementation owner"
    exit 1
fi

if ! printf '%s\n' "$role_output" | grep -q "agent report role"; then
    echo "Expected role-mismatch output to reference agent report role mismatch"
    printf '%s\n' "$role_output"
    exit 1
fi

write_agent_report "solidity-implementer" "src/OtherExample.sol"
write_review_note "solidity-implementer" "yes"
set +e
path_output="$(CHANGE_CLASSIFIER_FORCE=prod-semantic PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/check-solidity-review-note.sh 2>&1)"
path_status=$?
set -e

if [ "$path_status" -eq 0 ]; then
    echo "Expected check-solidity-review-note to fail when Agent Report does not reference a changed Solidity path"
    exit 1
fi

if ! printf '%s\n' "$path_output" | grep -q "changed production Solidity path"; then
    echo "Expected changed-path output to reference the missing changed production Solidity path linkage"
    printf '%s\n' "$path_output"
    exit 1
fi

write_task_brief
write_agent_report "solidity-implementer" "test/Example.t.sol"
write_review_note "solidity-implementer" "yes"
sed -i 's|Files reviewed: src/Example.sol|Files reviewed: test/Example.t.sol|g' "$review_file"
set +e
mixed_linkage_output="$(CHANGE_CLASSIFIER_FORCE=prod-semantic PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$mixed_changed_files_path" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/check-solidity-review-note.sh 2>&1)"
mixed_linkage_status=$?
set -e

if [ "$mixed_linkage_status" -eq 0 ]; then
    echo "Expected check-solidity-review-note to fail when mixed src+test changes only reference the test surface"
    exit 1
fi

if ! printf '%s\n' "$mixed_linkage_output" | grep -q "changed production Solidity path"; then
    echo "Expected mixed src+test linkage output to reference the changed production Solidity path requirement"
    printf '%s\n' "$mixed_linkage_output"
    exit 1
fi

write_task_brief
write_agent_report "solidity-implementer" "test/Example.t.sol"
write_review_note "solidity-implementer" "yes"
sed -i 's|Files reviewed: src/Example.sol|Files reviewed: test/Example.t.sol|g' "$review_file"
set +e
mixed_discovery_output="$(CHANGE_CLASSIFIER_FORCE=prod-semantic PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$mixed_changed_files_path" bash ./script/process/check-solidity-review-note.sh 2>&1)"
mixed_discovery_status=$?
set -e

if [ "$mixed_discovery_status" -eq 0 ]; then
    echo "Expected check-solidity-review-note discovery to fail when mixed src+test changes only have a test-matching review note"
    exit 1
fi

if ! printf '%s\n' "$mixed_discovery_output" | grep -q "changed production Solidity paths"; then
    echo "Expected mixed src+test discovery output to reference changed production Solidity paths"
    printf '%s\n' "$mixed_discovery_output"
    exit 1
fi

write_task_brief
write_agent_report "solidity-implementer" "src/Example.sol.bak"
write_review_note "solidity-implementer" "yes"
sed -i 's|Files reviewed: src/Example.sol|Files reviewed: src/Example.sol.bak|g' "$review_file"
set +e
bak_explicit_output="$(CHANGE_CLASSIFIER_FORCE=prod-semantic PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/check-solidity-review-note.sh 2>&1)"
bak_explicit_status=$?
set -e

if [ "$bak_explicit_status" -eq 0 ]; then
    echo "Expected check-solidity-review-note to fail when .bak file references are used for an explicit review note"
    exit 1
fi

if ! printf '%s\n' "$bak_explicit_output" | grep -q "changed production Solidity path"; then
    echo "Expected .bak explicit output to reference the changed production Solidity path requirement"
    printf '%s\n' "$bak_explicit_output"
    exit 1
fi

write_task_brief
write_agent_report "solidity-implementer" "src/Example.sol"
write_review_note "solidity-implementer" "yes"
sed -i 's|Files reviewed: src/Example.sol|Files reviewed: src/Example.sol.bak|g' "$review_file"
set +e
bak_discovery_output="$(CHANGE_CLASSIFIER_FORCE=prod-semantic PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" bash ./script/process/check-solidity-review-note.sh 2>&1)"
bak_discovery_status=$?
set -e

if [ "$bak_discovery_status" -eq 0 ]; then
    echo "Expected check-solidity-review-note discovery to fail when only .bak review-note references exist"
    exit 1
fi

if ! printf '%s\n' "$bak_discovery_output" | grep -q "changed production Solidity paths"; then
    echo "Expected .bak discovery output to reference changed production Solidity paths"
    printf '%s\n' "$bak_discovery_output"
    exit 1
fi

write_agent_report "solidity-implementer" "src/Example.sol"
write_review_note "solidity-implementer" "no"
set +e
dispatch_output="$(CHANGE_CLASSIFIER_FORCE=prod-semantic PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/check-solidity-review-note.sh 2>&1)"
dispatch_status=$?
set -e

if [ "$dispatch_status" -eq 0 ]; then
    echo "Expected check-solidity-review-note to fail when Writer dispatch confirmed is not yes"
    exit 1
fi

if ! printf '%s\n' "$dispatch_output" | grep -q "Writer dispatch confirmed"; then
    echo "Expected writer-dispatch output to reference Writer dispatch confirmed"
    printf '%s\n' "$dispatch_output"
    exit 1
fi

write_agent_report "solidity-implementer" "src/Example.sol"
write_review_note "solidity-implementer" "yes"
sed -i "s|$task_brief_file|docs/task-briefs/does-not-exist.md|" "$review_file"
set +e
brief_output="$(CHANGE_CLASSIFIER_FORCE=prod-semantic PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/check-solidity-review-note.sh 2>&1)"
brief_status=$?
set -e

if [ "$brief_status" -eq 0 ]; then
    echo "Expected check-solidity-review-note to fail when Task Brief path does not exist"
    exit 1
fi

if ! printf '%s\n' "$brief_output" | grep -q "Task Brief path"; then
    echo "Expected task-brief output to reference Task Brief path"
    printf '%s\n' "$brief_output"
    exit 1
fi

write_task_brief
sed -i 's|Files in scope: src/Example.sol|Files in scope: src/CompletelyDifferent.sol|g' "$task_brief_file"
sed -i 's|Write permissions: src/Example.sol|Write permissions: src/CompletelyDifferent.sol|g' "$task_brief_file"
write_agent_report "solidity-implementer" "src/Example.sol"
write_review_note "solidity-implementer" "yes"
set +e
brief_scope_output="$(CHANGE_CLASSIFIER_FORCE=prod-semantic PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/check-solidity-review-note.sh 2>&1)"
brief_scope_status=$?
set -e

if [ "$brief_scope_status" -eq 0 ]; then
    echo "Expected check-solidity-review-note to fail when Task Brief Files in scope does not match the changed production Solidity file"
    exit 1
fi

if ! printf '%s\n' "$brief_scope_output" | grep -q "Files in scope"; then
    echo "Expected foreign-brief output to reference Files in scope"
    printf '%s\n' "$brief_scope_output"
    exit 1
fi

write_task_brief
sed -i 's|Default writer role: solidity-implementer|Default writer role: |g' "$task_brief_file"
write_agent_report "solidity-implementer" "src/Example.sol"
write_review_note "solidity-implementer" "yes"
set +e
blank_writer_output="$(CHANGE_CLASSIFIER_FORCE=prod-semantic PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/check-solidity-review-note.sh 2>&1)"
blank_writer_status=$?
set -e

if [ "$blank_writer_status" -eq 0 ]; then
    echo "Expected check-solidity-review-note to fail when Task Brief Default writer role is blank"
    exit 1
fi

if ! printf '%s\n' "$blank_writer_output" | grep -q "Default writer role"; then
    echo "Expected blank-writer output to reference Default writer role"
    printf '%s\n' "$blank_writer_output"
    exit 1
fi

write_task_brief

task_brief_file="$task_brief_dir/2026-03-27-example-task-brief.md"
write_task_brief "reward/accounting; external integration" "AGENTS.md; docs/process/review-notes.md" "docs/upstream/external-source.md" "reward index must update after balance deltas"
write_agent_report "solidity-implementer" "src/Example.sol"
write_review_note "solidity-implementer" "yes"
sed -i 's|Semantic dimensions reviewed: reward/accounting; external integration|Semantic dimensions reviewed: reward/accounting|g' "$review_file"
sed -i 's|External facts checked: docs/upstream/external-source.md|External facts checked: none|g' "$review_file"
set +e
semantic_output="$(CHANGE_CLASSIFIER_FORCE=prod-semantic PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/check-solidity-review-note.sh 2>&1)"
semantic_status=$?
set -e

if [ "$semantic_status" -eq 0 ]; then
    echo "Expected check-solidity-review-note to fail when review-note semantic alignment does not cover the task brief"
    exit 1
fi

if ! printf '%s\n' "$semantic_output" | grep -q "Semantic dimensions reviewed"; then
    echo "Expected semantic-alignment output to reference Semantic dimensions reviewed"
    printf '%s\n' "$semantic_output"
    exit 1
fi

write_task_brief "reward/accounting; external integration" "AGENTS.md; docs/process/review-notes.md" "docs/upstream/external-source.md" "reward index must update after balance deltas; external adapter must preserve share accounting"
write_agent_report "solidity-implementer" "src/Example.sol"
write_review_note "solidity-implementer" "yes"
sed -i 's|reward index updates after balance deltas|reward index updates after balance deltas|g' "$review_file"
sed -i 's|reviewed reward/accounting and external integration expectations against the task brief and local control flow|reviewed reward/accounting expectations against the task brief and local control flow|g' "$review_file"
set +e
assumption_output="$(CHANGE_CLASSIFIER_FORCE=prod-semantic PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/check-solidity-review-note.sh 2>&1)"
assumption_status=$?
set -e

if [ "$assumption_status" -eq 0 ]; then
    echo "Expected check-solidity-review-note to fail when critical assumptions are not reflected in the configured review-note field"
    exit 1
fi

if ! printf '%s\n' "$assumption_output" | grep -q "Critical assumptions to prove or reject"; then
    echo "Expected critical-assumption output to reference Task Brief critical assumptions"
    printf '%s\n' "$assumption_output"
    exit 1
fi

write_task_brief "reward/accounting; external integration" "AGENTS.md; docs/process/review-notes.md" "docs/upstream/external-source.md" "reward index must update after balance deltas; external adapter must preserve share accounting"
write_agent_report "solidity-implementer" "src/Example.sol"
write_agent_report "solidity-implementer" "src/OtherExample.sol" "$unrelated_agent_report_file"
write_review_evidence_files
write_review_note "solidity-implementer" "yes"
write_review_note "solidity-implementer" "yes" "$unrelated_review_file"
sed -i 's|Semantic alignment summary: reviewed reward/accounting and external integration expectations against the task brief and local control flow|Semantic alignment summary: reviewed reward/accounting and external integration expectations against the task brief and local control flow; reward index must update after balance deltas; external adapter must preserve share accounting|g' "$review_file"
sed -i 's|Semantic alignment summary: reviewed reward/accounting and external integration expectations against the task brief and local control flow|Semantic alignment summary: reviewed reward/accounting and external integration expectations against the task brief and local control flow; reward index must update after balance deltas; external adapter must preserve share accounting|g' "$unrelated_review_file"
sed -i "s|$agent_report_file|$unrelated_agent_report_file|g" "$unrelated_review_file"
sed -i "s|Files reviewed: src/Example.sol|Files reviewed: src/OtherExample.sol|g" "$unrelated_review_file"
sleep 1
touch "$unrelated_review_file"
CHANGE_CLASSIFIER_FORCE=prod-semantic PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" bash ./script/process/check-solidity-review-note.sh

write_task_brief
write_agent_report "solidity-implementer" "src/Example.sol"
write_review_evidence_files
write_review_note "solidity-implementer" "yes"
touch -m -d '+5 seconds' "$agent_report_file"
set +e
stale_evidence_output="$(CHANGE_CLASSIFIER_FORCE=prod-semantic PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/check-solidity-review-note.sh 2>&1)"
stale_evidence_status=$?
set -e

if [ "$stale_evidence_status" -eq 0 ]; then
    echo "Expected check-solidity-review-note to fail when writer evidence is newer than the review note and reviewer/verifier evidence"
    exit 1
fi

if ! printf '%s\n' "$stale_evidence_output" | grep -qi "stale"; then
    echo "Expected stale-evidence output to reference stale reviewer or verifier evidence"
    printf '%s\n' "$stale_evidence_output"
    exit 1
fi

write_agent_report "solidity-implementer" "src/Example.sol"
write_review_evidence_files
write_review_note "solidity-implementer" "yes"

pythonless_task_brief_backup="$tmp_dir/task-brief-without-codex-review.md"
cp "$task_brief_file" "$pythonless_task_brief_backup"
sed -i "s/npm run codex:review; //" "$task_brief_file"

missing_codex_review_output="$(CHANGE_CLASSIFIER_FORCE=prod-semantic PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/check-solidity-review-note.sh 2>&1 || true)"
if ! printf '%s\n' "$missing_codex_review_output" | grep -qi "codex:review"; then
    echo "Expected check-solidity-review-note to fail when Task Brief required verifier commands omit npm run codex:review"
    printf '%s\n' "$missing_codex_review_output"
    exit 1
fi

cp "$pythonless_task_brief_backup" "$task_brief_file"

write_task_brief "none" "none" "none" "none" "non-semantic" "solidity-implementer, verifier" "forge fmt --check; forge build; bash ./script/process/check-solidity-review-note.sh"
write_agent_report "solidity-implementer" "src/Example.sol"
write_review_evidence_files
write_review_note "solidity-implementer" "yes"
sed -i "/- Codex review summary:/d" "$review_file"
sed -i "/- Codex review evidence source:/d" "$review_file"
sed -i "s/npm run codex:review; //" "$review_file"
CHANGE_CLASSIFIER_FORCE=non-semantic PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$review_file" bash ./script/process/check-solidity-review-note.sh

echo "check-solidity-review-note selftest: PASS"
