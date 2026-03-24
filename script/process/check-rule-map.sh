#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <changed-files-list>"
    exit 1
fi

changed_files_list="$1"

if [ ! -f "$changed_files_list" ]; then
    echo "[check-rule-map] ERROR: changed files list not found: $changed_files_list"
    exit 1
fi

rule_map_path="$(node ./script/process/read-process-config.js rule-map __file__)"

PROCESS_CHANGED_FILES_FILE="$changed_files_list" PROCESS_RULE_MAP_FILE="$rule_map_path" node - <<'EOF'
const fs = require('fs');
const requirements = JSON.parse(
  require('child_process').execFileSync(
    'node',
    ['./script/process/read-process-config.js', 'rule-map', 'triggered.change.requirements'],
    {
      cwd: process.cwd(),
      env: process.env,
      encoding: 'utf8'
    }
  )
);
const failures = [];
const changedFiles = process.env.PROCESS_CHANGED_FILES_FILE
  ? fs.readFileSync(process.env.PROCESS_CHANGED_FILES_FILE, 'utf8').split(/\r?\n/).filter(Boolean)
  : [];

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

for (const requirement of requirements) {
  if (!evaluateMode(requirement.mode, requirement.tests, changedFiles)) {
    pushFailure(
      requirement.id,
      requirement.description || 'Rule requirement failed.',
      requirement.triggeredBy,
      requirement.mode,
      requirement.tests
    );
  }
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
