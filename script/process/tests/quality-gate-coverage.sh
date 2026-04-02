#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_dir="$(mktemp -d)"
policy_file="$tmp_dir/policy.json"
rule_map_file="$tmp_dir/rule-map.json"
fake_bin_dir="$tmp_dir/bin"
forge_log="$tmp_dir/forge.log"
npm_log="$tmp_dir/npm.log"
slither_log="$tmp_dir/slither.log"
review_dir="$tmp_dir/reviews"
review_file="$review_dir/2026-03-26-coverage-review.md"
src_file="src/CoverageGateTemp.sol"

cleanup() {
    rm -rf "$tmp_dir"
    git reset -- "$src_file" >/dev/null 2>&1 || true
    rm -f "$src_file"
}
trap cleanup EXIT

mkdir -p "$fake_bin_dir" "$review_dir"

cat > "$policy_file" <<EOF
{
  "review_note": {
    "required_headings": [
      "## Scope"
    ],
    "required_fields": [
      "Change summary",
      "Files reviewed",
      "Behavior change",
      "Ready to commit"
    ],
    "boolean_fields": [
      "Behavior change",
      "Ready to commit"
    ],
    "placeholder_values": [
      "",
      "yes/no"
    ],
    "field_owners": {},
    "owner_prefixed_source_fields": []
  },
  "pull_request": {
    "required_sections": []
  },
  "rule_map": {
    "path": "$rule_map_file",
    "evidence_field": "Existing tests exercised"
  },
  "quality_gate": {
    "swap_src_sol_pattern": "^src/swap/.*\\\\.sol$",
    "src_sol_pattern": "^src/.*\\\\.sol$",
    "test_tsol_pattern": "^test/.*\\\\.t\\\\.sol$",
    "test_sol_pattern": "^test/.*\\\\.sol$",
    "shell_pattern": "^(script/.*\\\\.sh|\\\\.githooks/.*)$",
    "process_surface_pattern": "^(AGENTS\\\\.md|docs/process/.*|\\\\.codex/.*|script/process/.*|\\\\.github/.*|\\\\.githooks/.*|README\\\\.md|docs/reviews/(README|TEMPLATE)\\\\.md|docs/task-briefs/README\\\\.md|docs/agent-reports/README\\\\.md|\\\\.solhint\\\\.json|\\\\.solhintignore)$",
    "process_js_pattern": "^script/process/.*\\\\.js$",
    "package_pattern": "^(package\\\\.json|package-lock\\\\.json)$",
    "docs_contract_pattern": "^(AGENTS\\\\.md|README\\\\.md|docs/process/.*|docs/reviews/(TEMPLATE|README)\\\\.md|docs/(ARCHITECTURE|GLOSSARY|TRACEABILITY|VERIFICATION)\\\\.md|docs/spec/.*|docs/adr/.*|\\\\.github/pull_request_template\\\\.md|\\\\.codex/.*)$",
    "process_selftest_patterns": [
      "^docs/process/.*$",
      "^\\\\.codex/.*$",
      "^script/process/.*$",
      "^package(-lock)?\\\\.json$"
    ],
    "process_default_roles": [
      "process-implementer",
      "verifier"
    ],
    "package_default_roles": [
      "process-implementer",
      "verifier"
    ],
    "docs_contract_default_roles": [
      "process-implementer",
      "verifier"
    ],
    "review_note_directory": "$review_dir",
    "slither_filter_paths": "lib|test|script|node_modules",
    "slither_exclude_detectors": "naming-convention,too-many-digits",
    "coverage": {
      "enabled": true,
      "report_file": "$tmp_dir/coverage/lcov.info",
      "exclude_tests": true,
      "ir_minimum": true,
      "only_changed_tiers": true,
      "fail_on_missing_data": true,
      "default_thresholds": {
        "line": 80,
        "function": 80,
        "branch": 70
      },
      "tiers": [
        { "path": "src", "line": 80, "function": 80, "branch": 70 }
      ]
    }
  }
}
EOF

cat > "$rule_map_file" <<'EOF'
{
  "version": 2,
  "defaults": {
    "change_requirement_mode": "none",
    "evidence_requirement_mode": "none"
  },
  "rules": [],
  "testing_gaps": []
}
EOF

cat > "$fake_bin_dir/forge" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${FORGE_LOG}"

if [ "${1:-}" = "snapshot" ]; then
    snapshot_output=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --snap)
                snapshot_output="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    if [ -n "$snapshot_output" ]; then
        cat > "$snapshot_output" <<'SNAPSHOT'
test:example() (gas: 12345)
SNAPSHOT
    fi
    exit 0
fi

if [ "${1:-}" = "coverage" ]; then
    report_output=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --report-file)
                report_output="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    mkdir -p "$(dirname "$report_output")"
    cat > "$report_output" <<'LCOV'
TN:
SF:src/CoverageGateTemp.sol
DA:10,1
DA:11,1
DA:12,1
DA:13,1
DA:14,1
DA:15,1
DA:16,1
DA:17,1
DA:18,1
DA:19,0
FN:10,foo
FN:18,bar
FNDA:1,foo
FNDA:1,bar
BRDA:10,0,0,1
BRDA:10,0,1,1
BRDA:18,1,0,1
BRDA:18,1,1,0
end_of_record
LCOV
    exit 0
fi

exit 0
EOF

cat > "$fake_bin_dir/npm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${NPM_LOG}"
exit 0
EOF

cat > "$fake_bin_dir/slither" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

json_output=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --json)
            json_output="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

printf '%s\n' "slither-called" >> "${SLITHER_LOG}"
cat > "$json_output" <<'JSON'
{"success":true,"results":{"detectors":[]}}
JSON
exit 0
EOF

chmod +x "$fake_bin_dir/forge" "$fake_bin_dir/npm" "$fake_bin_dir/slither"

cat > "$src_file" <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract CoverageGateTemp {
    /**
     * @notice Returns the provided value.
     * @dev Temporary source file used to exercise coverage gate integration.
     * @param value Value to return.
     * @return returnedValue The same value that was provided.
     */
    function echo(uint256 value) external pure returns (uint256 returnedValue) {
        return value;
    }
}
EOF

cat > "$review_file" <<'EOF'
# review-note

## Scope
- Change summary: coverage gate integration
- Files reviewed: src/CoverageGateTemp.sol
- Behavior change: no
- Ready to commit: yes
EOF

git add "$src_file"

PATH="$fake_bin_dir:$PATH" PROCESS_POLICY_FILE="$policy_file" QUALITY_GATE_REVIEW_NOTE="$review_file" FORGE_LOG="$forge_log" NPM_LOG="$npm_log" SLITHER_LOG="$slither_log" bash ./script/process/quality-gate.sh

if ! grep -q "^coverage --report lcov --report-file " "$forge_log"; then
    echo "Expected quality-gate to trigger forge coverage with lcov report"
    cat "$forge_log"
    exit 1
fi

if ! grep -q -- "--exclude-tests" "$forge_log"; then
    echo "Expected quality-gate coverage command to include --exclude-tests"
    cat "$forge_log"
    exit 1
fi

if ! grep -q -- "--ir-minimum" "$forge_log"; then
    echo "Expected quality-gate coverage command to include --ir-minimum"
    cat "$forge_log"
    exit 1
fi
