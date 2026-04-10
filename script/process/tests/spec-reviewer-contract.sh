#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

for path in \
    ".claude/agents/spec-reviewer.md" \
    ".claude/rules/spec-surface.md" \
    ".codex/agents/spec-reviewer.md" \
    ".codex/agents/spec-reviewer.toml"
do
    if [ ! -f "$path" ]; then
        echo "Expected spec-reviewer contract file missing: $path"
        exit 1
    fi
done

if ! grep -Fq '`spec-reviewer`' AGENTS.md; then
    echo "Expected AGENTS.md to mention spec-reviewer"
    exit 1
fi

if ! grep -Fq 'Phase 4 Spec Review' AGENTS.md; then
    echo "Expected AGENTS.md to define Phase 4 Spec Review"
    exit 1
fi

if ! grep -Fq 'docs/spec/**' AGENTS.md; then
    echo "Expected AGENTS.md to cover docs/spec/**"
    exit 1
fi

if ! grep -Fq 'docs/superpowers/specs/**' AGENTS.md; then
    echo "Expected AGENTS.md to cover docs/superpowers/specs/**"
    exit 1
fi

if ! grep -Fq 'writer 先产出 spec，再由 `spec-reviewer` 做 spec review' AGENTS.md; then
    echo "Expected AGENTS.md to describe spec-reviewer as the spec review step"
    exit 1
fi

if ! grep -Fq 'spec review evidence' docs/process/agents-detail.md; then
    echo "Expected docs/process/agents-detail.md to reference spec review evidence"
    exit 1
fi

if ! grep -Fq 'spec surface' docs/process/change-matrix.md; then
    echo "Expected docs/process/change-matrix.md to mention spec surface"
    exit 1
fi

echo "spec-reviewer-contract selftest: PASS"
