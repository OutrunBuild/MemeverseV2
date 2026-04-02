#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_dir="$(mktemp -d)"
changed_solidity_file="src/__stale_evidence_loop_fixture.sol"
task_brief_file="docs/task-briefs/2026-04-01-stale-evidence-loop-task-brief.md"
agent_report_file="docs/agent-reports/2026-04-01-stale-evidence-loop-agent-report.md"
review_file="docs/reviews/2026-04-01-stale-evidence-loop-review.md"
logic_evidence_file="docs/reviews/2026-04-01-stale-evidence-loop-logic.md"
security_evidence_file="docs/reviews/2026-04-01-stale-evidence-loop-security.md"
gas_evidence_file="docs/reviews/2026-04-01-stale-evidence-loop-gas.md"
verification_evidence_file="docs/reviews/2026-04-01-stale-evidence-loop-verifier.md"
changed_files_path="$tmp_dir/changed-files.txt"
follow_up_dir="$tmp_dir/follow-up-briefs"

cleanup() {
    rm -rf "$tmp_dir"
    rm -f "$changed_solidity_file"
    rm -f "$task_brief_file" "$agent_report_file" "$review_file"
    rm -f "$logic_evidence_file" "$security_evidence_file" "$gas_evidence_file" "$verification_evidence_file"
}
trap cleanup EXIT

mkdir -p "$follow_up_dir"
mkdir -p "$(dirname "$changed_solidity_file")"

cat > "$changed_solidity_file" <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract StaleEvidenceLoopFixture {
    function ping() external pure returns (uint256) {
        return 1;
    }
}
EOF

cat > "$changed_files_path" <<EOF
$changed_solidity_file
EOF

cat > "$task_brief_file" <<EOF
# Task Brief

- Goal: stale evidence remediation loop selftest
- Change classification: prod-semantic
- Change type: none
- Files in scope: $changed_solidity_file
- Out of scope: none
- Known facts: current Agent Report should become the freshness anchor
- Open questions / assumptions: none
- Risks to check: stale reviewer/verifier evidence
- Required roles: solidity-implementer, logic-reviewer, security-reviewer, gas-reviewer, verifier
- Optional roles: none
- Default writer role: solidity-implementer
- Implementation owner: solidity-implementer
- Write permissions: $changed_solidity_file
- Writer dispatch backend: native-codex-subagents
- Writer dispatch target: .codex/agents/solidity-implementer.toml
- Writer dispatch scope: $changed_solidity_file
- Non-goals: none
- Acceptance checks: rerun downstream reviewers after a follow-up writer pass
- Required verifier commands: npm run codex:review; bash ./script/process/check-solidity-review-note.sh
- Required artifacts: Task Brief, Agent Report, review note
- Review note required: yes
- Semantic review dimensions: none
- Source-of-truth docs: none
- External sources required: none
- Critical assumptions to prove or reject: none
- Required output fields: none
- Review note impact: no
- If blocked: stop and return the stale evidence blocker
EOF

cat > "$agent_report_file" <<EOF
# Agent Report

- Role: solidity-implementer
- Summary: updated the scoped Solidity surface
- Task Brief path: $task_brief_file
- Scope / ownership respected: yes
- Files touched/reviewed: $changed_solidity_file
- Findings: none
- Required follow-up: rerun logic/security/gas/verifier after the follow-up writer pass
- Commands run: forge test -vvv
- Evidence: selftest fixture
- Residual risks: stale evidence still needs to be cleared
EOF

cat > "$logic_evidence_file" <<EOF
# Logic Evidence

- reviewer: logic-reviewer
EOF

cat > "$security_evidence_file" <<EOF
# Security Evidence

- reviewer: security-reviewer
EOF

cat > "$gas_evidence_file" <<EOF
# Gas Evidence

- reviewer: gas-reviewer
EOF

cat > "$verification_evidence_file" <<EOF
# Verification Evidence

- reviewer: verifier
EOF

cat > "$review_file" <<EOF
# review-note

## Scope
- Change summary: stale evidence loop selftest
- Files reviewed: $changed_solidity_file
- Task Brief path: $task_brief_file
- Agent Report path: $agent_report_file
- Implementation owner: solidity-implementer
- Writer dispatch confirmed: yes
- Semantic dimensions reviewed: none
- Source-of-truth docs checked: none
- External facts checked: none
- Local control-flow facts checked: local control flow preserved
- Evidence chain complete: yes
- Semantic alignment summary: aligned with the task brief

## Impact
- Behavior change: no
- ABI change: no
- Storage layout change: no
- Config change: no

## Findings
- High findings: none
- Medium findings: none
- Low findings: none
- None: none
- Logic review summary: local control flow and state transitions match the task brief.
- Logic residual risks: none.
- Logic evidence source: logic-reviewer: $logic_evidence_file
- Security review summary: no critical issues.
- Security residual risks: none.
- Security evidence source: security-reviewer: $security_evidence_file

## Simplification
- Candidate simplifications considered: none
- Applied: none
- Rejected (with reason): none

## Gas
- Gas-sensitive paths reviewed: Example.execute
- Gas changes applied: none
- Gas snapshot/result: unchanged
- Gas residual risks: none
- Gas evidence source: gas-reviewer: $gas_evidence_file

## Docs
- Docs updated: none
- Why these docs: none
- No-doc reason: none

## Tests
- Tests updated: none
- Existing tests exercised: none
- No-test-change reason: none

## Verification
- Commands run: npm run codex:review; forge test -vvv
- Results: pass
- Codex review summary: no additional findings
- Codex review evidence source: verifier: npm run codex:review
- Verification evidence source: verifier: $verification_evidence_file

## Decision
- Ready to commit: yes
- Residual risks: none
- Decision evidence source: main-orchestrator: local decision summary
EOF

sleep 1
touch "$agent_report_file"

set +e
output="$(QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$review_file" FOLLOW_UP_BRIEF_OUTPUT_DIR="$follow_up_dir" REMEDIATION_LOOP_DATE="2026-04-01" bash ./script/process/run-stale-evidence-loop.sh 2>&1)"
status=$?
set -e

if [ "$status" -ne 2 ]; then
    echo "Expected stale-evidence loop to exit with status 2 after generating a follow-up brief"
    printf '%s\n' "$output"
    exit 1
fi

if ! printf '%s\n' "$output" | grep -q "follow-up brief written"; then
    echo "Expected stale-evidence loop output to report the generated follow-up brief"
    printf '%s\n' "$output"
    exit 1
fi

if ! printf '%s\n' "$output" | grep -q "re-dispatch order"; then
    echo "Expected stale-evidence loop output to report the rerun order"
    printf '%s\n' "$output"
    exit 1
fi

mapfile -t generated_follow_ups < <(find "$follow_up_dir" -maxdepth 1 -type f -name '*.md' | sort)
if [ "${#generated_follow_ups[@]}" -ne 1 ]; then
    echo "Expected exactly one generated follow-up brief"
    printf '%s\n' "$output"
    exit 1
fi

follow_up_file="${generated_follow_ups[0]}"
if ! grep -q "Parent Task Brief path: $task_brief_file" "$follow_up_file"; then
    echo "Expected follow-up brief to record the parent task brief"
    cat "$follow_up_file"
    exit 1
fi

if ! grep -q "Parent Agent Report path: $agent_report_file" "$follow_up_file"; then
    echo "Expected follow-up brief to record the parent agent report"
    cat "$follow_up_file"
    exit 1
fi

if ! grep -q "Required rerun roles: solidity-implementer, verifier, logic-reviewer, security-reviewer, gas-reviewer" "$follow_up_file"; then
    echo "Expected follow-up brief to require writer plus downstream reviewer/verifier reruns"
    cat "$follow_up_file"
    exit 1
fi

if ! grep -q "Dispatch order: solidity-implementer -> logic-reviewer -> security-reviewer -> gas-reviewer -> codex review -> verifier" "$follow_up_file"; then
    echo "Expected follow-up brief to encode the rerun dispatch order"
    cat "$follow_up_file"
    exit 1
fi

cat > "$task_brief_file" <<EOF
# Task Brief

- Goal: stale evidence remediation loop selftest
- Change classification: non-semantic
- Change type: none
- Files in scope: $changed_solidity_file
- Out of scope: none
- Known facts: current Agent Report should become the freshness anchor
- Open questions / assumptions: none
- Risks to check: stale verifier evidence
- Required roles: verifier
- Optional roles: none
- Default writer role: solidity-implementer
- Implementation owner: solidity-implementer
- Write permissions: $changed_solidity_file
- Writer dispatch backend: native-codex-subagents
- Writer dispatch target: .codex/agents/solidity-implementer.toml
- Writer dispatch scope: $changed_solidity_file
- Non-goals: none
- Acceptance checks: rerun downstream verification after a follow-up writer pass
- Required verifier commands: bash ./script/process/check-solidity-review-note.sh
- Required artifacts: Task Brief, Agent Report, review note
- Review note required: yes
- Semantic review dimensions: none
- Source-of-truth docs: none
- External sources required: none
- Critical assumptions to prove or reject: none
- Required output fields: none
- Review note impact: no
- If blocked: stop and return the stale evidence blocker
EOF

cat > "$review_file" <<EOF
# review-note

## Scope
- Change summary: stale evidence loop selftest
- Files reviewed: $changed_solidity_file
- Task Brief path: $task_brief_file
- Agent Report path: $agent_report_file
- Implementation owner: solidity-implementer
- Writer dispatch confirmed: yes
- Semantic dimensions reviewed: none
- Source-of-truth docs checked: none
- External facts checked: none
- Local control-flow facts checked: local control flow preserved
- Evidence chain complete: yes
- Semantic alignment summary: aligned with the task brief

## Impact
- Behavior change: no
- ABI change: no
- Storage layout change: no
- Config change: no

## Findings
- High findings: none
- Medium findings: none
- Low findings: none
- None: none
- Logic review summary: local control flow and state transitions match the task brief.
- Logic residual risks: none.
- Logic evidence source: logic-reviewer: $logic_evidence_file
- Security review summary: no critical issues.
- Security residual risks: none.
- Security evidence source: security-reviewer: $security_evidence_file

## Simplification
- Candidate simplifications considered: none
- Applied: none
- Rejected (with reason): none

## Gas
- Gas-sensitive paths reviewed: Example.execute
- Gas changes applied: none
- Gas snapshot/result: unchanged
- Gas residual risks: none
- Gas evidence source: gas-reviewer: $gas_evidence_file

## Docs
- Docs updated: none
- Why these docs: none
- No-doc reason: none

## Tests
- Tests updated: none
- Existing tests exercised: none
- No-test-change reason: none

## Verification
- Commands run: forge test -vvv
- Results: pass
- Verification evidence source: verifier: $verification_evidence_file

## Decision
- Ready to commit: yes
- Residual risks: none
- Decision evidence source: main-orchestrator: local decision summary
EOF

sleep 1
touch "$agent_report_file"

set +e
output="$(CHANGE_CLASSIFIER_FORCE=non-semantic QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_path" QUALITY_GATE_REVIEW_NOTE="$review_file" FOLLOW_UP_BRIEF_OUTPUT_DIR="$follow_up_dir" REMEDIATION_LOOP_DATE="2026-04-01" bash ./script/process/run-stale-evidence-loop.sh 2>&1)"
status=$?
set -e

if [ "$status" -ne 2 ]; then
    echo "Expected stale-evidence loop to exit with status 2 for non-semantic stale verifier evidence"
    printf '%s\n' "$output"
    exit 1
fi

mapfile -t generated_follow_ups < <(find "$follow_up_dir" -maxdepth 1 -type f -name '*.md' | sort)
follow_up_file="$(grep -l "Change classification: non-semantic" "${generated_follow_ups[@]}" | tail -n 1)"

if ! grep -q "Required rerun roles: solidity-implementer, verifier" "$follow_up_file"; then
    echo "Expected non-semantic follow-up brief to require only writer and verifier reruns"
    cat "$follow_up_file"
    exit 1
fi

if ! grep -q "Dispatch order: solidity-implementer -> verifier" "$follow_up_file"; then
    echo "Expected non-semantic follow-up brief to skip codex review reruns"
    cat "$follow_up_file"
    exit 1
fi

echo "stale-evidence-loop selftest: PASS"
