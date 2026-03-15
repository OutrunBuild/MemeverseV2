#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_dir="$(mktemp -d)"
install_root="$tmp_dir/skills-root"
source_root="$tmp_dir/source-skills"

cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

set +e
usage_output="$(bash ./script/process/tools/install-repo-skill.sh 2>&1)"
usage_status=$?
set -e

if [ "$usage_status" -eq 0 ]; then
    echo "Expected install-repo-skill to fail without a skill name"
    exit 1
fi

if ! printf '%s\n' "$usage_output" | grep -q "Usage:"; then
    echo "Expected usage output when no skill name is provided"
    printf '%s\n' "$usage_output"
    exit 1
fi

set +e
missing_output="$(SKILL_INSTALL_ROOT="$install_root" bash ./script/process/tools/install-repo-skill.sh missing-skill 2>&1)"
missing_status=$?
set -e

if [ "$missing_status" -eq 0 ]; then
    echo "Expected install-repo-skill to fail for a missing skill"
    exit 1
fi

if ! printf '%s\n' "$missing_output" | grep -q "skill not found"; then
    echo "Expected missing skill output"
    printf '%s\n' "$missing_output"
    exit 1
fi

mkdir -p "$source_root/solidity-post-coding-flow/agents"
cat <<'EOF' > "$source_root/solidity-post-coding-flow/SKILL.md"
---
name: solidity-post-coding-flow
description: test fixture
---
EOF

cat <<'EOF' > "$source_root/solidity-post-coding-flow/agents/openai.yaml"
model: gpt-test
EOF

SKILL_INSTALL_ROOT="$install_root" \
SKILL_SOURCE_ROOTS="$source_root" \
    bash ./script/process/tools/install-repo-skill.sh solidity-post-coding-flow

installed_skill_dir="$install_root/solidity-post-coding-flow"

if [ ! -f "$installed_skill_dir/SKILL.md" ]; then
    echo "Expected installed skill to include SKILL.md"
    exit 1
fi

if [ ! -f "$installed_skill_dir/agents/openai.yaml" ]; then
    echo "Expected installed skill to include agents/openai.yaml"
    exit 1
fi

if ! grep -q "name: solidity-post-coding-flow" "$installed_skill_dir/SKILL.md"; then
    echo "Expected installed SKILL.md to match source skill"
    exit 1
fi
