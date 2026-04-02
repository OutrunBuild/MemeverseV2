#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

for path in \
    ".codex/agents/logic-reviewer.toml" \
    ".codex/agents/logic-reviewer.md"
do
    if [ ! -f "$path" ]; then
        echo "Expected logic-reviewer contract file missing: $path"
        exit 1
    fi
done

if ! grep -q '`logic-reviewer`' AGENTS.md; then
    echo "Expected AGENTS.md to mention logic-reviewer"
    exit 1
fi

if ! grep -q '`solidity-implementer` -> `logic-reviewer` -> `security-reviewer` -> `gas-reviewer`' AGENTS.md; then
    echo "Expected AGENTS.md required review order to place logic-reviewer after implementation and before specialist review"
    exit 1
fi

if ! grep -q '### Phase 4: Logic Review' docs/process/subagent-workflow.md; then
    echo "Expected subagent workflow to define a dedicated Logic Review phase"
    exit 1
fi

echo "logic-reviewer-contract selftest: PASS"
