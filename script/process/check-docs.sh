#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

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

task_brief_template="$(read_policy_value agents.task_brief_template '.codex/templates/task-brief.md')"
agent_report_template="$(read_policy_value agents.agent_report_template '.codex/templates/agent-report.md')"
agent_directory="$(read_policy_value agents.agent_directory '.codex/agents')"
main_session_role="$(read_policy_value agents.main_session_role 'main-orchestrator')"
docs_contract_pattern="$(read_policy_value quality_gate.docs_contract_pattern '^(AGENTS\\.md|README\\.md|docs/process/.*|docs/reviews/(TEMPLATE|README)\\.md|\\.github/pull_request_template\\.md|\\.codex/.*)$')"
generated_docs_root="$(read_policy_value quality_gate.generated_docs_root 'docs/contracts')"
generated_docs_summary="$(read_policy_value quality_gate.generated_docs_summary "${generated_docs_root}/SUMMARY.md")"
generated_docs_unexpected_nested_src="$(read_policy_value quality_gate.generated_docs_unexpected_nested_src "${generated_docs_root}/src")"

load_role_array agents.default_roles default_roles
load_role_array agents.on_demand_roles on_demand_roles

bash ./script/process/generate-docs.sh

if [ ! -d "$generated_docs_root" ]; then
    echo "Expected generated docs root missing: $generated_docs_root"
    exit 1
fi

if [ -d "$generated_docs_unexpected_nested_src" ]; then
    echo "Unexpected nested docs directory: $generated_docs_unexpected_nested_src"
    exit 1
fi

if [ ! -f "$generated_docs_summary" ]; then
    echo "Expected docs summary missing: $generated_docs_summary"
    exit 1
fi

mapfile -t generated_docs_markdown_files < <(find "$generated_docs_root" -type f -name '*.md' ! -path "$generated_docs_summary" | sort)

if [ "${#generated_docs_markdown_files[@]}" -eq 0 ]; then
    echo "Expected generated markdown docs under $generated_docs_root (excluding summary)"
    exit 1
fi

required_harness_support_files=(
    "AGENTS.md"
    "README.md"
    "docs/process/subagent-workflow.md"
    "docs/reviews/README.md"
    "docs/reviews/TEMPLATE.md"
    "$task_brief_template"
    "$agent_report_template"
    "$agent_directory/README.md"
)

required_product_truth_support_files=(
    "docs/ARCHITECTURE.md"
    "docs/GLOSSARY.md"
    "docs/TRACEABILITY.md"
    "docs/VERIFICATION.md"
    "docs/adr/0001-universalvault-style-harness-migration.md"
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

for path in "${required_product_truth_support_files[@]}"; do
    if [ ! -f "$path" ]; then
        echo "Expected product-truth support doc missing: $path"
        exit 1
    fi
done

for path in "${required_product_truth_core_docs[@]}"; do
    if [ ! -f "$path" ]; then
        echo "Expected product-truth core doc missing: $path"
        exit 1
    fi
done

for path in "${discovered_spec_docs[@]}"; do
    if [ ! -f "$path" ]; then
        echo "Expected discovered spec doc missing: $path"
        exit 1
    fi
done

for role in "${required_role_names[@]}"; do
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
