#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

if [ -d "docs/contracts" ]; then
    echo "Generated docs directory must not exist: docs/contracts"
    echo "Remove generated contract docs and keep product-truth docs under docs/spec instead."
    exit 1
fi

read_policy_value() {
    local key="$1"
    local default_value="$2"
    local value

    if value="$(node ./script/process/read-process-config.js policy "$key" 2>/dev/null)"; then
        printf '%s' "$value"
        return
    fi

    printf '%s' "$default_value"
}

load_role_array() {
    local key="$1"
    local __target="$2"
    local output

    if ! output="$(node ./script/process/read-process-config.js policy "$key" --lines)"; then
        echo "Invalid policy role array: $key"
        exit 1
    fi

    mapfile -t "$__target" <<< "$output"
}

find_misplaced_artifacts() {
    local expected_heading="$1"
    local plan_dir="$2"
    local file
    local first_nonempty_line

    [ -d "$plan_dir" ] || return 0

    while IFS= read -r -d '' file; do
        first_nonempty_line="$(awk 'NF { print; exit }' "$file")"
        if [ "$first_nonempty_line" = "$expected_heading" ]; then
            printf '%s\n' "$file"
        fi
    done < <(find "$plan_dir" -type f -name '*.md' -print0)
}

task_brief_template="$(read_policy_value agents.task_brief_template '.codex/templates/task-brief.md')"
role_delta_brief_template="$(read_policy_value agents.role_delta_brief_template '.codex/templates/role-delta-brief.md')"
follow_up_brief_template="$(read_policy_value agents.follow_up_brief_template '.codex/templates/follow-up-brief.md')"
agent_report_template="$(read_policy_value agents.agent_report_template '.codex/templates/agent-report.md')"
task_brief_directory="$(read_policy_value agents.task_brief_directory 'docs/task-briefs')"
agent_report_directory="$(read_policy_value agents.agent_report_directory 'docs/agent-reports')"
agent_directory="$(read_policy_value agents.agent_directory '.codex/agents')"
main_session_role="$(read_policy_value agents.main_session_role 'main-orchestrator')"
docs_contract_pattern="$(read_policy_value quality_gate.docs_contract_pattern '^(AGENTS\\.md|README\\.md|docs/process/.*|docs/reviews/(TEMPLATE|README)\\.md|docs/task-briefs/.*|docs/agent-reports/.*|docs/(ARCHITECTURE|GLOSSARY|TRACEABILITY|VERIFICATION)\\.md|docs/spec/.*|docs/adr/.*|\\.github/pull_request_template\\.md|\\.codex/.*)$')"
plan_dir="${CHECK_DOCS_PLAN_DIR:-docs/plans}"

load_role_array agents.default_roles default_roles
load_role_array agents.on_demand_roles on_demand_roles

required_harness_support_files=(
    "AGENTS.md"
    ".codex/runtime/subagent-runtime.json"
    ".codex/workflows/solidity-subagent-workflow.json"
    "README.md"
    ".githooks/pre-commit"
    ".githooks/pre-push"
    "script/process/run-codex-review.sh"
    "script/process/run-stale-evidence-loop.sh"
    "script/process/run-pre-push-quality-gate.sh"
    "docs/reviews/README.md"
    "docs/reviews/TEMPLATE.md"
    "$task_brief_directory/README.md"
    "$agent_report_directory/README.md"
    "$task_brief_template"
    "$role_delta_brief_template"
    "$follow_up_brief_template"
    "$agent_report_template"
)

required_product_truth_support_files=(
    "docs/ARCHITECTURE.md"
    "docs/GLOSSARY.md"
    "docs/TRACEABILITY.md"
    "docs/VERIFICATION.md"
)

required_product_truth_core_docs=(
    "docs/spec/protocol.md"
    "docs/spec/state-machines.md"
    "docs/spec/accounting.md"
    "docs/spec/access-control.md"
    "docs/spec/upgradeability.md"
    "docs/spec/implementation-map.md"
)

if [ ! -d "docs/spec" ]; then
    echo "Expected product-truth spec directory missing: docs/spec"
    exit 1
fi

mapfile -t discovered_spec_docs < <(find docs/spec -type f -name '*.md' | sort)

if [ "${#discovered_spec_docs[@]}" -eq 0 ]; then
    echo "Expected at least one spec doc under docs/spec"
    exit 1
fi

mapfile -t required_role_names < <(printf '%s\n' "$main_session_role" "${default_roles[@]}" "${on_demand_roles[@]}" | awk 'NF && !seen[$0]++')

for path in "${required_harness_support_files[@]}"; do
    if [ ! -f "$path" ]; then
        echo "Expected harness support file missing: $path"
        exit 1
    fi

    if [[ ! "$path" =~ $docs_contract_pattern ]]; then
        echo "Policy docs_contract_pattern does not cover required harness file: $path"
        exit 1
    fi
done

for directory in "$task_brief_directory" "$agent_report_directory"; do
    if [ ! -d "$directory" ]; then
        echo "Expected artifact directory missing: $directory"
        exit 1
    fi
done

for path in "${required_product_truth_support_files[@]}"; do
    if [ ! -f "$path" ]; then
        echo "Expected product-truth support doc missing: $path"
        exit 1
    fi

    if [[ ! "$path" =~ $docs_contract_pattern ]]; then
        echo "Policy docs_contract_pattern does not cover required product-truth support doc: $path"
        exit 1
    fi
done

for path in "${required_product_truth_core_docs[@]}"; do
    if [ ! -f "$path" ]; then
        echo "Expected product-truth core doc missing: $path"
        exit 1
    fi

    if [[ ! "$path" =~ $docs_contract_pattern ]]; then
        echo "Policy docs_contract_pattern does not cover required product-truth core doc: $path"
        exit 1
    fi
done

for path in "${discovered_spec_docs[@]}"; do
    if [ ! -f "$path" ]; then
        echo "Expected discovered spec doc missing: $path"
        exit 1
    fi

    if [[ ! "$path" =~ $docs_contract_pattern ]]; then
        echo "Policy docs_contract_pattern does not cover discovered spec doc: $path"
        exit 1
    fi
done

node - <<'EOF'
const fs = require('fs');

function fail(message) {
  console.error(`[check-docs] ERROR: ${message}`);
  process.exit(1);
}

const packageJson = JSON.parse(fs.readFileSync('package.json', 'utf8'));
const scripts = packageJson.scripts || {};
const policy = JSON.parse(fs.readFileSync('docs/process/policy.json', 'utf8'));
const runtime = JSON.parse(fs.readFileSync('.codex/runtime/subagent-runtime.json', 'utf8'));
const workflow = JSON.parse(fs.readFileSync('.codex/workflows/solidity-subagent-workflow.json', 'utf8'));
const taskBriefTemplate = fs.readFileSync('.codex/templates/task-brief.md', 'utf8');
const agentReportTemplate = fs.readFileSync('.codex/templates/agent-report.md', 'utf8');

if (policy.agents.workflow_index !== '.codex/workflows/solidity-subagent-workflow.json') {
  fail(`policy agents.workflow_index must point at .codex/workflows/solidity-subagent-workflow.json`);
}

if (runtime.workflow_index !== policy.agents.workflow_index) {
  fail(`runtime workflow_index must match policy agents.workflow_index`);
}

for (const key of ['task_brief_directory', 'agent_report_directory', 'task_brief_template', 'agent_report_template', 'agent_directory']) {
  if (String(policy.agents[key]) !== String(runtime.artifacts[key])) {
    fail(`runtime.artifacts.${key} must match policy.agents.${key}`);
  }
  if (String(policy.agents[key]) !== String(workflow.artifacts[key])) {
    fail(`workflow.artifacts.${key} must match policy.agents.${key}`);
  }
}

for (const key of ['main_session_role']) {
  if (String(policy.agents[key]) !== String(runtime.roles[key])) {
    fail(`runtime.roles.${key} must match policy.agents.${key}`);
  }
  if (String(policy.agents[key]) !== String(workflow.roles[key])) {
    fail(`workflow.roles.${key} must match policy.agents.${key}`);
  }
}

for (const key of ['default_roles', 'on_demand_roles']) {
  if (JSON.stringify(policy.agents[key]) !== JSON.stringify(runtime.roles[key])) {
    fail(`runtime.roles.${key} must match policy.agents.${key}`);
  }
  if (JSON.stringify(policy.agents[key]) !== JSON.stringify(workflow.roles[key])) {
    fail(`workflow.roles.${key} must match policy.agents.${key}`);
  }
}

for (const requiredField of ['- Change classification rationale:', '- Verifier profile:', '- Implementation owner:', '- Writer dispatch backend:', '- Required verifier commands:', '- Required artifacts:']) {
  if (!taskBriefTemplate.includes(requiredField)) {
    fail(`task brief template is missing required field ${requiredField}`);
  }
}

for (const requiredField of ['- Task Brief path:', '- Scope / ownership respected:']) {
  if (!agentReportTemplate.includes(requiredField)) {
    fail(`agent report template is missing required field ${requiredField}`);
  }
}

for (const scriptName of ['docs:check', 'process:selftest', 'quality:quick', 'quality:gate', 'classify:change', 'codex:review', 'stale-evidence:loop']) {
  if (typeof scripts[scriptName] !== 'string' || scripts[scriptName].trim() === '') {
    fail(`package.json is missing required npm script '${scriptName}'`);
  }
}
EOF

for role in "${required_role_names[@]}"; do
    if [ "$role" = "$main_session_role" ]; then
        continue
    fi
    manifest_path="${agent_directory}/${role}.toml"
    if [ ! -f "$manifest_path" ]; then
        echo "Expected role manifest missing: $manifest_path"
        exit 1
    fi
done

if [ ! -d "$agent_directory" ]; then
    echo "Expected agent directory missing: $agent_directory"
    exit 1
fi

mapfile -t agent_manifests < <(find "$agent_directory" -maxdepth 1 -type f -name '*.toml' | sort)

if [ "${#agent_manifests[@]}" -eq 0 ]; then
    echo "Expected at least one role manifest under $agent_directory"
    exit 1
fi

for toml_path in "${agent_manifests[@]}"; do
    md_path="${toml_path%.toml}.md"
    if [ ! -f "$md_path" ]; then
        echo "Expected runtime contract missing for manifest: $toml_path"
        exit 1
    fi
done

while IFS= read -r misplaced_brief; do
    if [ -n "$misplaced_brief" ]; then
        echo "[check-docs] ERROR: Task Brief must not live under ${plan_dir}: $misplaced_brief"
        exit 1
    fi
done < <(find_misplaced_artifacts '# Task Brief' "$plan_dir")

while IFS= read -r misplaced_report; do
    if [ -n "$misplaced_report" ]; then
        echo "[check-docs] ERROR: Agent Report must not live under ${plan_dir}: $misplaced_report"
        exit 1
    fi
done < <(find_misplaced_artifacts '# Agent Report' "$plan_dir")

echo "[check-docs] PASS"
