#!/usr/bin/env bash
# Generate a review package for a reviewer to read in one call, so the diff
# never has to be pasted through the main session's context.
#
# The package covers BASE -> working tree: every change since BASE — commits
# made since BASE, uncommitted edits, AND untracked new files. Untracked files
# are marked intent-to-add (git add -N) so they appear in the diff, then the
# index is restored on exit. `git reset -- <path>` touches ONLY the index,
# never the working tree, so file contents are never at risk.
#
# Usage: review-package.sh BASE [HEAD] [OUTFILE]
#   BASE = commit recorded before the implementer started (required, must be
#          an ancestor of HEAD)
#   HEAD = current HEAD, used only for the commit list and output filename;
#          defaults to HEAD.
# Default OUTFILE: <repo-root>/.harness/tmp/review-<base7>..<head7>.diff
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 3 ]; then
  echo "usage: review-package.sh BASE [HEAD] [OUTFILE]" >&2
  exit 2
fi

base=$1
head=${2:-HEAD}

git rev-parse --verify --quiet "$base" >/dev/null || { echo "bad BASE: $base" >&2; exit 2; }
git rev-parse --verify --quiet "$head" >/dev/null || { echo "bad HEAD: $head" >&2; exit 2; }

# BASE must be an ancestor of HEAD; a reversed range would produce a silently empty package.
if ! git merge-base --is-ancestor "$base" "$head"; then
  echo "bad range: BASE ($base) must be an ancestor of HEAD ($head)" >&2
  exit 2
fi

if [ "$#" -eq 3 ]; then
  out=$3
else
  root=$(git rev-parse --show-toplevel)
  out="$root/.harness/tmp/review-$(git rev-parse --short "$base")..$(git rev-parse --short "$head").diff"
fi

# git diff ignores untracked files. Mark them intent-to-add so new files appear
# in the package, and restore the index on exit so no -N markers remain.
_INTENT_ADDED=()
_restore_index() {
  if [ "${#_INTENT_ADDED[@]}" -gt 0 ]; then
    git reset --quiet -- "${_INTENT_ADDED[@]}" 2>/dev/null || true
  fi
}
trap _restore_index EXIT

# List untracked files; check exit code explicitly (process substitution would
# swallow a `git ls-files` failure under pipefail, silently dropping new files).
_untracked_list="$(git ls-files --others --exclude-standard)" || { echo "git ls-files failed" >&2; exit 1; }
_untracked=()
[ -n "$_untracked_list" ] && mapfile -t _untracked <<< "$_untracked_list"

if [ "${#_untracked[@]}" -gt 0 ]; then
  _INTENT_ADDED=("${_untracked[@]}")   # record BEFORE add, so trap can reset even if add fails partway
  git add -N -- "${_untracked[@]}"
fi

mkdir -p "$(dirname "$out")"

base7=$(git rev-parse --short "$base")
head7=$(git rev-parse --short "$head")
{
  echo "# Review package: ${base7} -> working tree (HEAD=${head7})"
  echo
  echo "## Commits since BASE (empty if all changes are uncommitted)"
  git log --oneline "${base}..${head}"
  echo
  echo "## Files changed (BASE -> working tree, includes untracked + uncommitted)"
  git diff --stat "$base"
  echo
  echo "## Diff (BASE -> working tree, -U10 context)"
  git diff -U10 "$base"
} > "$out"

_restore_index
trap - EXIT

commits=$(git rev-list --count "${base}..${head}")
echo "wrote ${out}: ${commits} commit(s) since BASE, $(wc -c < "$out" | tr -d ' ') bytes, ${#_untracked[@]} untracked file(s) included"
