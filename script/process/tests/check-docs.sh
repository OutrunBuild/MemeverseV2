#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_suffix="$$"
tmp_brief="docs/plans/zz-temp-task-brief-for-selftest-${tmp_suffix}.md"
tmp_report="docs/plans/zz-temp-agent-report-for-selftest-${tmp_suffix}.md"

cleanup() {
    rm -f "$tmp_brief" "$tmp_report"
}
trap cleanup EXIT

cat > "$tmp_brief" <<'EOF'
# Task Brief

- Goal: temporary selftest fixture
- Change type: docs
- Files in scope: docs/plans/zz-temp-task-brief-for-selftest-${tmp_suffix}.md
- Risks to check: none
- Required roles: process-implementer
- Optional roles: none
- Default writer role: process-implementer
- Write permissions: docs/plans/zz-temp-task-brief-for-selftest-${tmp_suffix}.md
- Non-goals: none
- Acceptance checks: npm run docs:check
- Semantic review dimensions: none
- Source-of-truth docs: AGENTS.md
- External sources required: none
- Critical assumptions to prove or reject: none
- Required output fields: Role, Summary
- Review note impact: no
EOF

cat > "$tmp_report" <<'EOF'
# Agent Report

- Role: verifier
- Summary: temporary selftest fixture
- Files touched/reviewed: none
- Findings: none
- Required follow-up: none
- Commands run: none
- Evidence: none
- Residual risks: none
EOF

set +e
output="$(npm run docs:check 2>&1)"
status=$?
set -e

if [ "$status" -eq 0 ]; then
    echo "Expected docs:check to fail when a Task Brief is placed under docs/plans"
    exit 1
fi

if ! printf '%s\n' "$output" | grep -qi "Task Brief"; then
    echo "Expected docs:check failure output to reference misplaced Task Brief artifacts"
    printf '%s\n' "$output"
    exit 1
fi

rm -f "$tmp_brief"

set +e
output="$(npm run docs:check 2>&1)"
status=$?
set -e

if [ "$status" -eq 0 ]; then
    echo "Expected docs:check to fail when an Agent Report is placed under docs/plans"
    exit 1
fi

if ! printf '%s\n' "$output" | grep -qi "Agent Report"; then
    echo "Expected docs:check failure output to reference misplaced Agent Report artifacts"
    printf '%s\n' "$output"
    exit 1
fi

echo "check-docs selftest: PASS"
