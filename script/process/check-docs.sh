#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

bash ./script/process/generate-docs.sh

if [ -d "docs/contracts/src" ]; then
    echo "Unexpected nested docs directory: docs/contracts/src"
    exit 1
fi

if [ ! -d "docs/contracts/common" ]; then
    echo "Expected docs directory missing: docs/contracts/common"
    exit 1
fi

if [ ! -f "docs/contracts/SUMMARY.md" ]; then
    echo "Expected docs summary missing: docs/contracts/SUMMARY.md"
    exit 1
fi

required_harness_support_files=(
    "AGENTS.md"
    "README.md"
    "docs/process/subagent-workflow.md"
    ".codex/templates/task-brief.md"
    ".codex/templates/agent-report.md"
    ".codex/agents/README.md"
)

required_role_names=(
    "main-orchestrator"
    "process-implementer"
    "solidity-implementer"
    "security-reviewer"
    "gas-reviewer"
    "security-test-writer"
    "solidity-explorer"
    "verifier"
)

for path in "${required_harness_support_files[@]}"; do
    if [ ! -f "$path" ]; then
        echo "Expected harness support file missing: $path"
        exit 1
    fi
done

for role in "${required_role_names[@]}"; do
    manifest_path=".codex/agents/${role}.toml"
    if [ ! -f "$manifest_path" ]; then
        echo "Expected role manifest missing: $manifest_path"
        exit 1
    fi
done

mapfile -t agent_manifests < <(find ".codex/agents" -maxdepth 1 -type f -name '*.toml' | sort)

if [ "${#agent_manifests[@]}" -eq 0 ]; then
    echo "Expected at least one role manifest under .codex/agents"
    exit 1
fi

for toml_path in "${agent_manifests[@]}"; do
    md_path="${toml_path%.toml}.md"
    if [ ! -f "$md_path" ]; then
        echo "Expected runtime contract missing for manifest: $toml_path"
        exit 1
    fi
done
