#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_dir="$(mktemp -d)"

cleanup() {
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

policy_file="$tmp_dir/policy.json"
review_file="$tmp_dir/review.md"
pr_file="$tmp_dir/pr.md"
passing_review_file="$tmp_dir/review-pass.md"
passing_pr_file="$tmp_dir/pr-pass.md"
legacy_review_file="$tmp_dir/legacy-review.md"

cat > "$policy_file" <<'EOF'
{
  "review_note": {
    "required_headings": ["## Scope", "## Impact", "## Custom"],
    "required_fields": ["Change summary", "Files reviewed", "Behavior change", "Ready to commit"],
    "boolean_fields": ["Behavior change", "Ready to commit"],
    "placeholder_values": ["", "yes/no"]
  },
  "pull_request": {
    "required_sections": ["## Summary", "## Custom"]
  },
  "quality_gate": {}
}
EOF

cat > "$review_file" <<'EOF'
# temp-review

## Scope
- Change summary: ok
- Files reviewed: ok

## Impact
- Behavior change: no
- ABI change: no
- Storage layout change: no
- Config change: no

## Findings
- High findings: none.
- Medium findings: none.
- Low findings: none.
- None: none.

## Simplification
- Candidate simplifications considered: none.
- Applied: none.
- Rejected (with reason): none.

## Docs
- Docs updated: none
- Why these docs: none.
- No-doc reason: none.

## Tests
- Tests updated: none
- Existing tests exercised: none.
- No-test-change reason: none.

## Verification
- Commands run: none.
- Results: none.

## Decision
- Ready to commit: yes
- Residual risks: none.
EOF

cat > "$pr_file" <<'EOF'
## Summary

Only summary.
EOF

set +e
review_output="$(PROCESS_POLICY_FILE="$policy_file" bash ./script/process/check-review-note.sh "$review_file" 2>&1)"
review_status=$?
pr_output="$(PROCESS_POLICY_FILE="$policy_file" bash ./script/process/check-pr-body.sh "$pr_file" 2>&1)"
pr_status=$?
set -e

if [ "$review_status" -eq 0 ]; then
    echo "Expected policy-driven review-note validation to fail when custom heading is missing"
    exit 1
fi

if ! printf '%s\n' "$review_output" | grep -q "Custom"; then
    echo "Expected review-note output to reference the missing custom heading"
    printf '%s\n' "$review_output"
    exit 1
fi

if [ "$pr_status" -eq 0 ]; then
    echo "Expected policy-driven PR body validation to fail when custom section is missing"
    exit 1
fi

if ! printf '%s\n' "$pr_output" | grep -q "Custom"; then
    echo "Expected PR body output to reference the missing custom section"
    printf '%s\n' "$pr_output"
    exit 1
fi

cat > "$passing_review_file" <<'EOF'
# temp-review

## Scope
- Change summary: ok
- Files reviewed: ok

## Impact
- Behavior change: no
- Ready to commit: yes

## Custom

custom section present.
EOF

cat > "$passing_pr_file" <<'EOF'
## Summary

Summary present.

## Custom

Custom section present.
EOF

PROCESS_POLICY_FILE="$policy_file" bash ./script/process/check-review-note.sh "$passing_review_file"
PROCESS_POLICY_FILE="$policy_file" bash ./script/process/check-pr-body.sh "$passing_pr_file"

cat > "$legacy_review_file" <<'EOF'
# legacy-review

## Scope
- Change summary: ok
- Files reviewed: ok

## Impact
- Behavior change: no
- ABI change: no
- Storage layout change: no
- Config change: no

## Findings
- High findings: none.
- Medium findings: none.
- Low findings: none.
- None: none.

## Simplification
- Candidate simplifications considered: none.
- Applied: none.
- Rejected (with reason): none.

## Docs
- Docs updated: none
- Why these docs: none.
- No-doc reason: none.

## Tests
- Tests updated: none
- Existing tests exercised: none.
- No-test-change reason: none.

## Verification
- Commands run: none.
- Results: none.

## Decision
- Ready to commit: yes
- Residual risks: none.
EOF

set +e
legacy_output="$(bash ./script/process/check-review-note.sh "$legacy_review_file" 2>&1)"
legacy_status=$?
set -e

if [ "$legacy_status" -eq 0 ]; then
    echo "Expected default review-note policy to reject legacy notes without security and gas evidence"
    exit 1
fi

if ! printf '%s\n' "$legacy_output" | grep -q "## Gas"; then
    echo "Expected default review-note policy failure output to reference the missing Gas section"
    printf '%s\n' "$legacy_output"
    exit 1
fi
