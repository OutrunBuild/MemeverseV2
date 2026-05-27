#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
script_root="$(cd "$script_dir/../.." && pwd -P)"

case "$script_root" in
    */.worktrees/*)
        canonical_root="${script_root%%/.worktrees/*}"
        ;;
    *)
        canonical_root="$script_root"
        ;;
esac

current_root="$(git rev-parse --show-toplevel)"
canonical_lib="$canonical_root/lib"
current_lib="$current_root/lib"

if [ "$current_root" = "$canonical_root" ]; then
    echo "canonical worktree: lib already local"
    exit 0
fi

case "$current_root" in
    "$canonical_root"/.worktrees/*)
        ;;
    *)
        echo "blocked: current worktree is not under $canonical_root/.worktrees"
        exit 1
        ;;
esac

expected_dependencies=(
    forge-std
    openzeppelin-contracts-upgradeable
    openzeppelin-foundry-upgrades
    devtools
    LayerZero-v2
    solidity-bytes-utils
    flexible-voting
    solmate
    v4-core
    v4-periphery
    v4-hooks-public
)

for dependency in "${expected_dependencies[@]}"; do
    if [ ! -d "$canonical_lib/$dependency" ]; then
        echo "blocked: missing $canonical_lib/$dependency; prepare canonical dependencies first"
        exit 1
    fi
done

dependency_status="$(git -C "$current_root" status --short -- .gitmodules lib)"
if [ -n "$dependency_status" ]; then
    echo "blocked: dependency paths are dirty in this worktree"
    exit 1
fi

if [ -L "$current_lib" ]; then
    linked_target="$(readlink "$current_lib")"
    if [ "$linked_target" = "$canonical_lib" ]; then
        echo "worktree lib already linked"
        exit 0
    fi

    echo "blocked: existing lib symlink points to $linked_target"
    exit 1
fi

if [ -e "$current_lib" ]; then
    has_real_content=0
    while IFS= read -r -d '' entry; do
        if [ -f "$entry" ] || [ -L "$entry" ]; then
            has_real_content=1
            break
        fi

        if [ -d "$entry" ] && find "$entry" -mindepth 1 -print -quit | grep -q .; then
            has_real_content=1
            break
        fi
    done < <(find "$current_lib" -mindepth 1 -maxdepth 1 -print0)

    if [ "$has_real_content" -ne 0 ]; then
        echo "blocked: existing lib is non-empty; not deleting automatically"
        exit 1
    fi

    rm -rf "$current_lib"
fi

ln -s "$canonical_lib" "$current_lib"
echo "linked worktree lib to canonical lib"
