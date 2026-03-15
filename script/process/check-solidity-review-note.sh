#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

mode="${QUALITY_GATE_MODE:-staged}"

find_latest_review_note() {
    local review_dir
    review_dir="$(node ./script/process/read-process-config.js policy quality_gate.review_note_directory)"

    if [ ! -d "$review_dir" ]; then
        return 1
    fi

    find "$review_dir" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' ! -name 'TEMPLATE.md' -printf '%T@ %p\n' \
        | sort -nr \
        | head -n 1 \
        | cut -d' ' -f2-
}

load_changed_files_from_ci() {
    if [ -n "${QUALITY_GATE_FILE_LIST:-}" ] && [ -f "${QUALITY_GATE_FILE_LIST}" ]; then
        cat "${QUALITY_GATE_FILE_LIST}"
        return
    fi

    if [ -n "${GITHUB_BASE_REF:-}" ]; then
        if ! git rev-parse --verify "origin/${GITHUB_BASE_REF}" >/dev/null 2>&1; then
            git fetch --no-tags --prune origin "${GITHUB_BASE_REF}:${GITHUB_BASE_REF}"
            git branch --set-upstream-to "origin/${GITHUB_BASE_REF}" "${GITHUB_BASE_REF}" >/dev/null 2>&1 || true
        fi
        git diff --name-only "origin/${GITHUB_BASE_REF}...HEAD"
        return
    fi

    if git rev-parse --verify HEAD~1 >/dev/null 2>&1; then
        git diff --name-only HEAD~1..HEAD
        return
    fi

    git ls-files
}

load_changed_files() {
    if [ "$mode" = "ci" ]; then
        load_changed_files_from_ci
        return
    fi

    git diff --cached --name-only --diff-filter=ACMR
}

review_note="${QUALITY_GATE_REVIEW_NOTE:-}"

if [ -z "$review_note" ]; then
    review_note="$(find_latest_review_note || true)"
fi

if [ -z "$review_note" ] || [ ! -f "$review_note" ]; then
    echo "[check-solidity-review-note] ERROR: review note not found. Set QUALITY_GATE_REVIEW_NOTE or add one under the configured review note directory."
    exit 1
fi

bash ./script/process/check-review-note.sh "$review_note"

changed_files="$(load_changed_files)"

if [ -z "$changed_files" ]; then
    exit 0
fi

changed_files_tmp="$(mktemp)"
trap 'rm -f "$changed_files_tmp"' EXIT
printf '%s\n' "$changed_files" > "$changed_files_tmp"

node - "$review_note" "$changed_files_tmp" <<'EOF'
const fs = require('fs');
const path = require('path');

const [, , reviewNotePath, changedFilesPath] = process.argv;
const ruleMapPath = process.env.PROCESS_RULE_MAP_FILE || 'docs/process/rule-map.json';
const ruleMap = JSON.parse(fs.readFileSync(path.resolve(ruleMapPath), 'utf8'));
const changedFiles = fs.readFileSync(changedFilesPath, 'utf8').split(/\r?\n/).filter(Boolean);
const reviewNote = fs.readFileSync(reviewNotePath, 'utf8');

function extractField(document, field) {
  const prefix = `- ${field}:`;
  for (const line of document.split(/\r?\n/)) {
    if (line.startsWith(prefix)) {
      return line.slice(prefix.length).trim();
    }
  }
  return '';
}

function evaluateEvidence(mode, candidates, exercised) {
  if (mode === 'none') return true;
  if (candidates.length === 0) return true;
  if (mode === 'any') return candidates.some((candidate) => exercised.includes(candidate));
  if (mode === 'all') return candidates.every((candidate) => exercised.includes(candidate));
  throw new Error(`Unsupported evidence_requirement mode: ${mode}`);
}

function getTriggeredByV1(rule) {
  return changedFiles.filter((file) => file.startsWith(rule.path_prefix || ''));
}

function getTriggeredByV2(rule) {
  const triggerPaths = rule.triggers?.any_of || [];
  return triggerPaths.filter((candidate) => changedFiles.includes(candidate));
}

const exercised = extractField(reviewNote, 'Existing tests exercised');
const failures = [];
const version = ruleMap.version || 1;

for (const rule of ruleMap.rules || []) {
  const triggeredBy = version === 1 ? getTriggeredByV1(rule) : getTriggeredByV2(rule);
  if (triggeredBy.length === 0) continue;

  const mode = version === 1
    ? 'any'
    : rule.evidence_requirement?.mode || ruleMap.defaults?.evidence_requirement_mode || 'any';
  const tests = version === 1
    ? (rule.required_test_patterns || [])
    : (rule.evidence_requirement?.tests || []);

  if (!evaluateEvidence(mode, tests, exercised)) {
    failures.push(
      `${rule.id}: ${rule.description || 'Rule evidence requirement failed.'} Triggered by: ${triggeredBy.join(', ')} Missing review-note evidence for mode=${mode}. Expected: ${tests.join(', ')}`
    );
  }
}

if (failures.length > 0) {
  for (const failure of failures) {
    console.error(`[check-solidity-review-note] ERROR: ${failure}`);
  }
  process.exit(1);
}
EOF
