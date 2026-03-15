#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <skill-name>"
    exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

skill_name="$1"
install_root="${SKILL_INSTALL_ROOT:-$HOME/.agents/skills}"
target_dir="$install_root/$skill_name"
source_roots="${SKILL_SOURCE_ROOTS:-skills:$HOME/.agents/skills}"
source_dir=""

IFS=':' read -r -a source_root_list <<< "$source_roots"
for root in "${source_root_list[@]}"; do
    [ -z "$root" ] && continue

    if [[ "$root" != /* ]]; then
        candidate="$repo_root/$root/$skill_name"
    else
        candidate="$root/$skill_name"
    fi

    if [ -d "$candidate" ]; then
        source_dir="$candidate"
        break
    fi
done

if [ -z "$source_dir" ]; then
    echo "[install-repo-skill] ERROR: skill not found: $skill_name"
    echo "[install-repo-skill] INFO: searched roots: $source_roots"
    exit 1
fi

mkdir -p "$install_root"
rm -rf "$target_dir"
cp -R "$source_dir" "$target_dir"

echo "[install-repo-skill] installed $skill_name to $target_dir"
