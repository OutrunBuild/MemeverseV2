#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tests=(
    "script/process/tests/check-docs.sh"
    "script/process/tests/check-local-doc-artifacts-ignore.sh"
    "script/process/tests/check-coverage.sh"
    "script/process/tests/check-gas-report.sh"
    "script/process/tests/check-natspec.sh"
    "script/process/tests/check-pr-body.sh"
    "script/process/tests/check-slither.sh"
    "script/process/tests/check-solidity-review-note.sh"
    "script/process/tests/ci-workflow.sh"
    "script/process/tests/install-repo-skill.sh"
    "script/process/tests/process-policy.sh"
    "script/process/tests/quality-quick.sh"
    "script/process/tests/quality-quick-coverage.sh"
    "script/process/tests/quality-gate-solidity-post-coding.sh"
    "script/process/tests/quality-gate-coverage.sh"
    "script/process/tests/rule-map-gate.sh"
)

for test_script in "${tests[@]}"; do
    echo "[process-selftest] running $test_script"
    bash "$test_script"
done

echo "[process-selftest] PASS"
