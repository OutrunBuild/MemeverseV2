#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_dir="$(mktemp -d)"

cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

policy_file="$tmp_dir/policy.json"
rule_map_file="$tmp_dir/rule-map.json"
review_file="$tmp_dir/review.md"
pr_file="$tmp_dir/pr.md"
passing_review_file="$tmp_dir/review-pass.md"
passing_pr_file="$tmp_dir/pr-pass.md"
legacy_review_file="$tmp_dir/legacy-review.md"
changed_files_list="$tmp_dir/changed-files.txt"
check_docs_policy_file="$tmp_dir/check-docs-policy.json"
renamed_brief_policy_file="$tmp_dir/renamed-brief-policy.json"
malformed_roles_policy_file="$tmp_dir/malformed-roles-policy.json"

cat > "$policy_file" <<EOF
{
  "review_note": {
    "required_headings": ["## Scope", "## Impact", "## Custom"],
    "required_fields": ["Change summary", "Files reviewed", "Behavior change", "Ready to commit"],
    "boolean_fields": ["Behavior change", "Ready to commit"],
    "placeholder_values": ["", "yes/no"],
    "field_owners": {
      "Rule-map evidence source": "verifier"
    },
    "owner_prefixed_source_fields": ["Rule-map evidence source"]
  },
  "pull_request": {
    "required_sections": ["## Summary", "## Custom"]
  },
  "rule_map": {
    "path": "$rule_map_file",
    "evidence_field": "Existing tests exercised"
  },
  "agents": {
    "main_session_role": "main-orchestrator",
    "default_roles": ["process-implementer", "verifier"],
    "on_demand_roles": ["solidity-explorer"],
    "task_brief_directory": "docs/task-briefs",
    "agent_report_directory": "docs/agent-reports",
    "task_brief_template": ".codex/templates/task-brief.md",
    "agent_report_template": ".codex/templates/agent-report.md",
    "agent_directory": ".codex/agents"
  },
  "quality_gate": {
    "docs_contract_pattern": "^(docs/process/.*|script/process/.*|[.]githooks/.*)$",
    "package_pattern": "^(package[.]json|package-lock[.]json)$"
  }
}
EOF

task_brief_directory="$(PROCESS_POLICY_FILE="$policy_file" node ./script/process/read-process-config.js policy agents.task_brief_directory)"
if [ "$task_brief_directory" != "docs/task-briefs" ]; then
    echo "Expected read-process-config to resolve agents.task_brief_directory"
    exit 1
fi

agent_report_directory="$(PROCESS_POLICY_FILE="$policy_file" node ./script/process/read-process-config.js policy agents.agent_report_directory)"
if [ "$agent_report_directory" != "docs/agent-reports" ]; then
    echo "Expected read-process-config to resolve agents.agent_report_directory"
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
      "id": "policy-driven-rule",
      "description": "ProcessPolicyTemp source changes require mapped tests in the change list.",
      "triggers": {
        "any_of": [
          "src/ProcessPolicyTemp.sol"
        ]
      },
      "change_requirement": {
        "mode": "any",
        "tests": [
          "test/ProcessPolicyTemp.t.sol"
        ]
      }
    }
  ],
  "testing_gaps": []
}
EOF

cat > "$review_file" <<'EOF'
# temp-review

## Scope
- Change summary: ok
- Files reviewed: ok

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

## Simplification
- Candidate simplifications considered: none.
- Applied: none.
- Rejected (with reason): none.

## Docs
- Docs updated: none
- Why these docs: none.
- No-doc reason: none.

## Tests
- Tests updated: none
- Existing tests exercised: none.
- No-test-change reason: none.

## Verification
- Commands run: none.
- Results: none.

## Decision
- Ready to commit: yes
- Residual risks: none.
EOF

cat > "$pr_file" <<'EOF'
## Summary

Only summary.
EOF

set +e
review_output="$(PROCESS_POLICY_FILE="$policy_file" bash ./script/process/check-review-note.sh "$review_file" 2>&1)"
review_status=$?
pr_output="$(PROCESS_POLICY_FILE="$policy_file" bash ./script/process/check-pr-body.sh "$pr_file" 2>&1)"
pr_status=$?
set -e

if [ "$review_status" -eq 0 ]; then
    echo "Expected policy-driven review-note validation to fail when custom heading is missing"
    exit 1
fi

if ! printf '%s\n' "$review_output" | grep -q "Custom"; then
    echo "Expected review-note output to reference the missing custom heading"
    printf '%s\n' "$review_output"
    exit 1
fi

if [ "$pr_status" -eq 0 ]; then
    echo "Expected policy-driven PR body validation to fail when custom section is missing"
    exit 1
fi

if ! printf '%s\n' "$pr_output" | grep -q "Custom"; then
    echo "Expected PR body output to reference the missing custom section"
    printf '%s\n' "$pr_output"
    exit 1
fi

cat > "$passing_review_file" <<'EOF'
# temp-review

## Scope
- Change summary: ok
- Files reviewed: ok

## Impact
- Behavior change: no
- Ready to commit: yes

## Custom

custom section present.
EOF

cat > "$passing_pr_file" <<'EOF'
## Summary

Summary present.

## Custom

Custom section present.
EOF

PROCESS_POLICY_FILE="$policy_file" bash ./script/process/check-review-note.sh "$passing_review_file"
PROCESS_POLICY_FILE="$policy_file" bash ./script/process/check-pr-body.sh "$passing_pr_file"

cat > "$legacy_review_file" <<'EOF'
# legacy-review

## Scope
- Change summary: ok
- Files reviewed: ok

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

## Simplification
- Candidate simplifications considered: none.
- Applied: none.
- Rejected (with reason): none.

## Docs
- Docs updated: none
- Why these docs: none.
- No-doc reason: none.

## Tests
- Tests updated: none
- Existing tests exercised: none.
- No-test-change reason: none.

## Verification
- Commands run: none.
- Results: none.

## Decision
- Ready to commit: yes
- Residual risks: none.
EOF

set +e
legacy_output="$(bash ./script/process/check-review-note.sh "$legacy_review_file" 2>&1)"
legacy_status=$?
set -e

if [ "$legacy_status" -eq 0 ]; then
    echo "Expected default review-note policy to reject legacy notes without security and gas evidence"
    exit 1
fi

if ! printf '%s\n' "$legacy_output" | grep -q "## Gas"; then
    echo "Expected default review-note policy failure output to reference the missing Gas section"
    printf '%s\n' "$legacy_output"
    exit 1
fi

resolved_rule_map_path="$(PROCESS_POLICY_FILE="$policy_file" node ./script/process/read-process-config.js rule-map __file__)"
if [ "$resolved_rule_map_path" != "$rule_map_file" ]; then
    echo "Expected read-process-config to resolve rule-map path from policy.rule_map.path"
    echo "Expected: $rule_map_file"
    echo "Actual:   $resolved_rule_map_path"
    exit 1
fi

cat > "$changed_files_list" <<'EOF'
src/ProcessPolicyTemp.sol
EOF

set +e
rule_map_output="$(PROCESS_POLICY_FILE="$policy_file" bash ./script/process/check-rule-map.sh "$changed_files_list" 2>&1)"
rule_map_status=$?
set -e

if [ "$rule_map_status" -eq 0 ]; then
    echo "Expected check-rule-map to enforce the policy-configured rule-map path"
    exit 1
fi

if ! printf '%s\n' "$rule_map_output" | grep -q "policy-driven-rule"; then
    echo "Expected check-rule-map failure output to reference the policy-driven rule id"
    printf '%s\n' "$rule_map_output"
    exit 1
fi

set +e
non_root_rule_map_output="$(
    cd "$repo_root/script/process"
    PROCESS_POLICY_FILE="$policy_file" bash ./check-rule-map.sh "$changed_files_list" 2>&1
)"
non_root_rule_map_status=$?
set -e

if [ "$non_root_rule_map_status" -eq 0 ]; then
    echo "Expected non-repo-root check-rule-map invocation to preserve policy-driven failure"
    exit 1
fi

if ! printf '%s\n' "$non_root_rule_map_output" | grep -q "policy-driven-rule"; then
    echo "Expected non-repo-root check-rule-map output to reference the policy-driven rule id"
    printf '%s\n' "$non_root_rule_map_output"
    exit 1
fi

bash ./script/process/check-docs.sh

cat > "$renamed_brief_policy_file" <<'EOF'
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
  "agents": {
    "main_session_role": "main-orchestrator",
    "default_roles": ["process-implementer", "verifier"],
    "on_demand_roles": ["solidity-explorer"],
    "task_brief_directory": "docs/task-briefs",
    "agent_report_directory": "docs/agent-reports",
    "task_brief_template": ".codex/templates/task-brief.md",
    "agent_report_template": ".codex/templates/agent-report.md",
    "agent_directory": ".codex/agents"
  },
  "quality_gate": {
    "docs_contract_pattern": "^(AGENTS[.]md|README[.]md|docs/process/.*|script/process/.*|[.]githooks/.*|docs/reviews/(TEMPLATE|README)[.]md|docs/task-briefs/.*|docs/agent-reports/.*|docs/(ARCHITECTURE|GLOSSARY|TRACEABILITY|VERIFICATION)[.]md|docs/spec/.*|docs/adr/.*|[.]github/pull_request_template[.]md|[.]codex/.*)$",
    "package_pattern": "^(package[.]json|package-lock[.]json)$"
  }
}
EOF

PROCESS_POLICY_FILE="$renamed_brief_policy_file" bash ./script/process/check-docs.sh

cat > "$malformed_roles_policy_file" <<'EOF'
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
  "agents": {
    "main_session_role": "main-orchestrator",
    "default_roles": "process-implementer",
    "on_demand_roles": ["verifier"],
    "task_brief_directory": "docs/task-briefs",
    "agent_report_directory": "docs/agent-reports",
    "task_brief_template": ".codex/templates/task-brief.md",
    "agent_report_template": ".codex/templates/agent-report.md",
    "agent_directory": ".codex/agents"
  },
  "quality_gate": {
    "docs_contract_pattern": "^(AGENTS[.]md|README[.]md|docs/process/.*|script/process/.*|[.]githooks/.*|docs/reviews/(TEMPLATE|README)[.]md|docs/task-briefs/.*|docs/agent-reports/.*|docs/(ARCHITECTURE|GLOSSARY|TRACEABILITY|VERIFICATION)[.]md|docs/spec/.*|docs/adr/.*|[.]github/pull_request_template[.]md|[.]codex/.*)$"
  }
}
EOF

set +e
malformed_roles_output="$(PROCESS_POLICY_FILE="$malformed_roles_policy_file" bash ./script/process/check-docs.sh 2>&1)"
malformed_roles_status=$?
set -e

if [ "$malformed_roles_status" -eq 0 ]; then
    echo "Expected check-docs to fail when agents.default_roles is malformed"
    exit 1
fi

if ! printf '%s\n' "$malformed_roles_output" | grep -q "agents.default_roles"; then
    echo "Expected malformed role-array failure output to reference agents.default_roles"
    printf '%s\n' "$malformed_roles_output"
    exit 1
fi

cat > "$check_docs_policy_file" <<'EOF'
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
  "agents": {
    "main_session_role": "main-orchestrator",
    "default_roles": ["process-implementer", "verifier"],
    "on_demand_roles": ["solidity-explorer"],
    "task_brief_directory": "docs/task-briefs",
    "agent_report_directory": "docs/agent-reports",
    "task_brief_template": ".codex/templates/task-brief.md",
    "agent_report_template": ".codex/templates/agent-report.md",
    "agent_directory": ".codex/agents"
  },
  "quality_gate": {
    "docs_contract_pattern": "^(AGENTS[.]md|README[.]md|docs/process/.*|script/process/.*|[.]githooks/.*|docs/reviews/README[.]md|docs/task-briefs/.*|docs/agent-reports/.*|docs/(ARCHITECTURE|GLOSSARY|TRACEABILITY|VERIFICATION)[.]md|docs/spec/.*|docs/adr/.*|[.]github/pull_request_template[.]md|[.]codex/.*)$"
  }
}
EOF

set +e
check_docs_output="$(PROCESS_POLICY_FILE="$check_docs_policy_file" bash ./script/process/check-docs.sh 2>&1)"
check_docs_status=$?
set -e

if [ "$check_docs_status" -eq 0 ]; then
    echo "Expected check-docs to fail when docs_contract_pattern excludes required harness files"
    exit 1
fi

if ! printf '%s\n' "$check_docs_output" | grep -q "docs/reviews/TEMPLATE.md"; then
    echo "Expected check-docs failure output to reference docs/reviews/TEMPLATE.md coverage"
    printf '%s\n' "$check_docs_output"
    exit 1
fi

cat > "$check_docs_policy_file" <<'EOF'
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
  "agents": {
    "main_session_role": "main-orchestrator",
    "default_roles": ["process-implementer", "verifier"],
    "on_demand_roles": ["solidity-explorer"],
    "task_brief_directory": "docs/task-briefs",
    "agent_report_directory": "docs/agent-reports",
    "task_brief_template": ".codex/templates/task-brief.md",
    "agent_report_template": ".codex/templates/agent-report.md",
    "agent_directory": ".codex/agents"
  },
  "quality_gate": {
    "docs_contract_pattern": "^(AGENTS[.]md|README[.]md|docs/process/.*|script/process/.*|[.]githooks/.*|docs/reviews/(TEMPLATE|README)[.]md|docs/task-briefs/.*|docs/agent-reports/.*|docs/(ARCHITECTURE|GLOSSARY|TRACEABILITY|VERIFICATION)[.]md|docs/adr/.*|[.]github/pull_request_template[.]md|[.]codex/.*)$"
  }
}
EOF

set +e
check_docs_output="$(PROCESS_POLICY_FILE="$check_docs_policy_file" bash ./script/process/check-docs.sh 2>&1)"
check_docs_status=$?
set -e

if [ "$check_docs_status" -eq 0 ]; then
    echo "Expected check-docs to fail when docs_contract_pattern excludes required product-truth spec files"
    exit 1
fi

if ! printf '%s\n' "$check_docs_output" | grep -q "docs/spec/protocol.md"; then
    echo "Expected check-docs failure output to reference docs/spec/protocol.md coverage"
    printf '%s\n' "$check_docs_output"
    exit 1
fi
