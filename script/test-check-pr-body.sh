#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_dir="$(mktemp -d)"

cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

missing_file="$tmp_dir/missing-sections.md"
passing_file="$tmp_dir/passing-sections.md"

cat > "$missing_file" <<'EOF'
## Summary

Short summary.

## Impact

Behavior change: no
EOF

cat > "$passing_file" <<'EOF'
## Summary

Short summary.

## Impact

Behavior change: no

## Docs

None.

## Tests

None.

## Verification

None.

## Risks

None.
EOF

set +e
missing_output="$(bash ./script/check-pr-body.sh "$missing_file" 2>&1)"
missing_status=$?
set -e

if [ "$missing_status" -eq 0 ]; then
    echo "Expected missing PR sections fixture to fail"
    exit 1
fi

if ! printf '%s\n' "$missing_output" | grep -q "missing required sections"; then
    echo "Expected missing PR section failure output"
    printf '%s\n' "$missing_output"
    exit 1
fi

bash ./script/check-pr-body.sh "$passing_file"
