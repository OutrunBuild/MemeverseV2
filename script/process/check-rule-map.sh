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

if (failures.length > 0) {
  for (const failure of failures) {
    console.error(`[check-rule-map] ERROR: ${failure}`);
  }
  process.exit(1);
}
EOF
