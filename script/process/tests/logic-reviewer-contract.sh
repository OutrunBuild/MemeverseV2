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

if ! grep -q 'logic-reviewer.*security-reviewer' AGENTS.md; then
    echo "Expected AGENTS.md to list logic-reviewer before specialist reviewers"
    exit 1
fi

if ! grep -q 'Phase 4' AGENTS.md; then
    echo "Expected AGENTS.md to define a Phase 4"
    exit 1
fi

echo "logic-reviewer-contract selftest: PASS"
