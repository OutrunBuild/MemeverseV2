#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_suffix="$$"
tmp_brief="docs/task-briefs/zz-temp-brief-${tmp_suffix}.md"
tmp_report="docs/agent-reports/zz-temp-report-${tmp_suffix}.md"

cleanup() {
    rm -f "$tmp_brief" "$tmp_report"
}
trap cleanup EXIT

touch "$tmp_brief" "$tmp_report"

assert_ignored() {
    local path="$1"
    if ! git check-ignore "$path" >/dev/null; then
        echo "Expected $path to be ignored by .gitignore"
        exit 1
    fi
}

assert_not_ignored() {
    local path="$1"
    if git check-ignore "$path" >/dev/null; then
        echo "Expected $path to remain tracked/not ignored"
        exit 1
    fi
}

assert_ignored "$tmp_brief"
assert_ignored "$tmp_report"
assert_not_ignored "docs/task-briefs/README.md"
assert_not_ignored "docs/agent-reports/README.md"

echo "local doc artifact ignore selftest: PASS"
