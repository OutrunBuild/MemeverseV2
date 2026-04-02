#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib/common.sh"

selftest::enter_repo_root
selftest::setup_tmpdir
plan_dir="$tmp_dir/plans"
tmp_brief="$plan_dir/zz-temp-task-brief-for-selftest.md"
tmp_report="$plan_dir/zz-temp-agent-report-for-selftest.md"

mkdir -p "$plan_dir"

cat > "$tmp_brief" <<EOF
# Task Brief

- Goal: temporary selftest fixture
- Change classification: process-surface
- Change type: docs
- Files in scope: $tmp_brief
- Out of scope: none
- Known facts: none
- Open questions / assumptions: none
- Risks to check: none
- Required roles: process-implementer
- Optional roles: none
- Default writer role: process-implementer
- Write permissions: $tmp_brief
- Non-goals: none
- Acceptance checks: npm run docs:check
- Semantic review dimensions: none
- Source-of-truth docs: AGENTS.md
- External sources required: none
- Critical assumptions to prove or reject: none
- Required output fields: Role, Summary
- Review note impact: no
- If blocked: stop and report the docs contract failure
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
output="$(CHECK_DOCS_PLAN_DIR="$plan_dir" npm run docs:check 2>&1)"
status=$?
set -e

if [ "$status" -eq 0 ]; then
    echo "Expected docs:check to fail when a Task Brief is placed under docs/plans"
    exit 1
fi

selftest::assert_text_contains "$output" "Task Brief" "Expected docs:check failure output to reference misplaced Task Brief artifacts"

rm -f "$tmp_brief"

set +e
output="$(CHECK_DOCS_PLAN_DIR="$plan_dir" npm run docs:check 2>&1)"
status=$?
set -e

if [ "$status" -eq 0 ]; then
    echo "Expected docs:check to fail when an Agent Report is placed under docs/plans"
    exit 1
fi

selftest::assert_text_contains "$output" "Agent Report" "Expected docs:check failure output to reference misplaced Agent Report artifacts"

echo "check-docs selftest: PASS"
