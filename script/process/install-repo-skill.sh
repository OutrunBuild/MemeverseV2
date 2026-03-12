#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <skill-name>"
    exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

skill_name="$1"
source_dir="skills/$skill_name"
install_root="${SKILL_INSTALL_ROOT:-$HOME/.agents/skills}"
target_dir="$install_root/$skill_name"

if [ ! -d "$source_dir" ]; then
    echo "[install-repo-skill] ERROR: skill not found: $source_dir"
    exit 1
fi

mkdir -p "$install_root"
rm -rf "$target_dir"
cp -R "$source_dir" "$target_dir"

echo "[install-repo-skill] installed $skill_name to $target_dir"
