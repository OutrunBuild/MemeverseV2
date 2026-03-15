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
legacy_file="$tmp_dir/legacy-sections.md"
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

## Security

Security review summary: none.

## Simplification

Applied: none.

## Gas

Gas snapshot/result: unchanged.
EOF

cat > "$legacy_file" <<'EOF'
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
missing_output="$(bash ./script/process/check-pr-body.sh "$missing_file" 2>&1)"
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

set +e
legacy_output="$(bash ./script/process/check-pr-body.sh "$legacy_file" 2>&1)"
legacy_status=$?
set -e

if [ "$legacy_status" -eq 0 ]; then
    echo "Expected default PR policy to reject bodies without security, simplification, and gas sections"
    exit 1
fi

if ! printf '%s\n' "$legacy_output" | grep -q "## Security"; then
    echo "Expected PR policy failure output to reference missing security section"
    printf '%s\n' "$legacy_output"
    exit 1
fi

bash ./script/process/check-pr-body.sh "$passing_file"
