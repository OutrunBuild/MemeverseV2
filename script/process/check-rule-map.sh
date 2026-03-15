#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <changed-files-list>"
    exit 1
fi

changed_files_list="$1"

if [ ! -f "$changed_files_list" ]; then
    echo "[check-rule-map] ERROR: changed files list not found: $changed_files_list"
    exit 1
fi

node - "$changed_files_list" <<'EOF'
const fs = require('fs');
const path = require('path');

const [, , changedFilesPath] = process.argv;
const ruleMapPath = process.env.PROCESS_RULE_MAP_FILE || 'docs/process/rule-map.json';
const ruleMap = JSON.parse(fs.readFileSync(path.resolve(ruleMapPath), 'utf8'));
const changedFiles = fs.readFileSync(changedFilesPath, 'utf8').split(/\r?\n/).filter(Boolean);
const failures = [];

function evaluateMode(mode, candidates, files) {
  if (mode === 'none') return true;
  if (mode === 'any') return candidates.some((candidate) => files.includes(candidate));
  if (mode === 'all') return candidates.every((candidate) => files.includes(candidate));
  throw new Error(`Unsupported change_requirement mode: ${mode}`);
}

function pushFailure(ruleId, description, triggeredBy, mode, tests) {
  failures.push(
    `${ruleId}: ${description} Triggered by: ${triggeredBy.join(', ')} Missing changed test evidence for mode=${mode}. Expected: ${tests.join(', ')}`
  );
}

const version = ruleMap.version || 1;

if (version === 1) {
  for (const rule of ruleMap.rules || []) {
    const applies = changedFiles.some((file) => file.startsWith(rule.path_prefix));
    if (!applies) continue;

    const matched = (rule.required_test_patterns || []).some((pattern) => changedFiles.includes(pattern));
    if (!matched) {
      failures.push(
        `${rule.id}: ${rule.description} Expected one of: ${(rule.required_test_patterns || []).join(', ')}`
      );
    }
  }
} else if (version === 2) {
  for (const rule of ruleMap.rules || []) {
    const triggerPaths = rule.triggers?.any_of || [];
    const triggeredBy = triggerPaths.filter((candidate) => changedFiles.includes(candidate));
    if (triggeredBy.length === 0) continue;

    const changeRequirement = rule.change_requirement || {};
    const mode = changeRequirement.mode || ruleMap.defaults?.change_requirement_mode || 'none';
    const tests = changeRequirement.tests || [];

    if (!evaluateMode(mode, tests, changedFiles)) {
      pushFailure(rule.id, rule.description || 'Rule requirement failed.', triggeredBy, mode, tests);
    }
  }
} else {
  throw new Error(`Unsupported rule-map version: ${version}`);
}

if (failures.length > 0) {
  for (const failure of failures) {
    console.error(`[check-rule-map] ERROR: ${failure}`);
  }
}

if (failures.length > 0) {
  process.exit(1);
}
EOF
