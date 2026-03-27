#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

mode="${QUALITY_GATE_MODE:-staged}"

read_policy_value() {
    local key="$1"
    local default_value="$2"
    local value

    if value="$(node ./script/process/read-process-config.js policy "$key" 2>/dev/null)"; then
        printf '%s' "$value"
        return
    fi

    printf '%s' "$default_value"
}

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

    git diff --cached --name-only --diff-filter=ACMRD
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

rule_map_path="$(node ./script/process/read-process-config.js rule-map __file__)"
rule_map_evidence_field="$(read_policy_value rule_map.evidence_field 'Existing tests exercised')"
field_owners_json="$(read_policy_value review_note.field_owners '{}')"
owner_prefixed_fields_json="$(read_policy_value review_note.owner_prefixed_source_fields '[]')"
solidity_required_fields_json="$(read_policy_value solidity_review_note.required_fields '[]')"
solidity_boolean_fields_json="$(read_policy_value solidity_review_note.boolean_fields '[]')"
task_brief_field="$(read_policy_value solidity_review_note.task_brief_field 'Task Brief path')"
agent_report_field="$(read_policy_value solidity_review_note.agent_report_field 'Agent Report path')"
implementation_owner_field="$(read_policy_value solidity_review_note.implementation_owner_field 'Implementation owner')"
writer_dispatch_confirmed_field="$(read_policy_value solidity_review_note.writer_dispatch_confirmed_field 'Writer dispatch confirmed')"
required_writer_patterns_json="$(read_policy_value agents.required_writer_for_patterns '{}')"
task_brief_directory="$(read_policy_value agents.task_brief_directory 'docs/briefs')"
agent_report_directory="$(read_policy_value agents.agent_report_directory 'docs/agent-reports')"
main_session_role="$(read_policy_value agents.main_session_role 'main-orchestrator')"
main_session_forbidden_patterns_json="$(read_policy_value agents.main_session_forbidden_write_patterns '[]')"

RULE_MAP_PATH="$rule_map_path" RULE_MAP_EVIDENCE_FIELD="$rule_map_evidence_field" REVIEW_FIELD_OWNERS="$field_owners_json" REVIEW_OWNER_PREFIXED_FIELDS="$owner_prefixed_fields_json" SOLIDITY_REQUIRED_FIELDS="$solidity_required_fields_json" SOLIDITY_BOOLEAN_FIELDS="$solidity_boolean_fields_json" TASK_BRIEF_FIELD="$task_brief_field" AGENT_REPORT_FIELD="$agent_report_field" IMPLEMENTATION_OWNER_FIELD="$implementation_owner_field" WRITER_DISPATCH_CONFIRMED_FIELD="$writer_dispatch_confirmed_field" REQUIRED_WRITER_PATTERNS="$required_writer_patterns_json" TASK_BRIEF_DIRECTORY="$task_brief_directory" AGENT_REPORT_DIRECTORY="$agent_report_directory" MAIN_SESSION_ROLE="$main_session_role" MAIN_SESSION_FORBIDDEN_PATTERNS="$main_session_forbidden_patterns_json" node - "$review_note" "$changed_files_tmp" <<'EOF'
const fs = require('fs');
const childProcess = require('child_process');
const path = require('path');

const [, , reviewNotePath, changedFilesPath] = process.argv;
const reviewNote = fs.readFileSync(reviewNotePath, 'utf8');
const evidenceField = process.env.RULE_MAP_EVIDENCE_FIELD || 'Existing tests exercised';
const fieldOwners = JSON.parse(process.env.REVIEW_FIELD_OWNERS || '{}');
const ownerPrefixedFields = JSON.parse(process.env.REVIEW_OWNER_PREFIXED_FIELDS || '[]');
const solidityRequiredFields = JSON.parse(process.env.SOLIDITY_REQUIRED_FIELDS || '[]');
const solidityBooleanFields = JSON.parse(process.env.SOLIDITY_BOOLEAN_FIELDS || '[]');
const requiredWriterPatterns = JSON.parse(process.env.REQUIRED_WRITER_PATTERNS || '{}');
const configuredTaskBriefDirectory = process.env.TASK_BRIEF_DIRECTORY || 'docs/briefs';
const configuredAgentReportDirectory = process.env.AGENT_REPORT_DIRECTORY || 'docs/agent-reports';
const mainSessionForbiddenPatterns = JSON.parse(process.env.MAIN_SESSION_FORBIDDEN_PATTERNS || '[]');
const taskBriefField = process.env.TASK_BRIEF_FIELD || 'Task Brief path';
const agentReportField = process.env.AGENT_REPORT_FIELD || 'Agent Report path';
const implementationOwnerField = process.env.IMPLEMENTATION_OWNER_FIELD || 'Implementation owner';
const writerDispatchConfirmedField = process.env.WRITER_DISPATCH_CONFIRMED_FIELD || 'Writer dispatch confirmed';
const mainSessionRole = process.env.MAIN_SESSION_ROLE || 'main-orchestrator';
const changedFiles = fs.readFileSync(changedFilesPath, 'utf8').split(/\r?\n/).filter(Boolean);
const evidenceRequirements = JSON.parse(
  childProcess.execFileSync(
    'node',
    ['./script/process/read-process-config.js', 'rule-map', 'triggered.evidence.requirements'],
    {
      cwd: process.cwd(),
      env: {
        ...process.env,
        PROCESS_CHANGED_FILES_FILE: changedFilesPath,
        PROCESS_RULE_MAP_FILE: process.env.RULE_MAP_PATH
      },
      encoding: 'utf8'
    }
  )
);

function extractField(document, field) {
  const prefix = `- ${field}:`;
  for (const line of document.split(/\r?\n/)) {
    if (line.startsWith(prefix)) {
      return line.slice(prefix.length).trim();
    }
  }
  return '';
}

function evaluateEvidence(mode, candidates, evidenceValue) {
  if (mode === 'none') return true;
  if (candidates.length === 0) return true;
  if (mode === 'any') return candidates.some((candidate) => evidenceValue.includes(candidate));
  if (mode === 'all') return candidates.every((candidate) => evidenceValue.includes(candidate));
  throw new Error(`Unsupported evidence_requirement mode: ${mode}`);
}

if (fieldOwners == null || typeof fieldOwners !== 'object' || Array.isArray(fieldOwners)) {
  throw new Error('review_note.field_owners must be a JSON object');
}

if (!Array.isArray(ownerPrefixedFields)) {
  throw new Error('review_note.owner_prefixed_source_fields must be an array');
}

if (!Array.isArray(solidityRequiredFields)) {
  throw new Error('solidity_review_note.required_fields must be an array');
}

if (!Array.isArray(solidityBooleanFields)) {
  throw new Error('solidity_review_note.boolean_fields must be an array');
}

const failures = [];
const evidenceValue = extractField(reviewNote, evidenceField);
const optionalOwnerPrefixedFields = new Set(['Rule-map evidence source']);

for (const field of solidityRequiredFields) {
  const value = extractField(reviewNote, field).trim();
  if (value === '') {
    failures.push(`${field}: missing required Solidity review-note field.`);
    continue;
  }

  if (solidityBooleanFields.includes(field) && value !== 'yes' && value !== 'no') {
    failures.push(`${field}: must be 'yes' or 'no'.`);
  }
}

const taskBriefPath = extractField(reviewNote, taskBriefField).trim();
if (taskBriefPath !== '') {
  const resolvedTaskBriefPath = path.resolve(taskBriefPath);
  if (!fs.existsSync(resolvedTaskBriefPath)) {
    failures.push(`${taskBriefField}: '${taskBriefPath}' does not exist.`);
  } else {
    const resolvedTaskBriefDirectory = path.resolve(configuredTaskBriefDirectory);
    if (!(resolvedTaskBriefPath === resolvedTaskBriefDirectory || resolvedTaskBriefPath.startsWith(`${resolvedTaskBriefDirectory}${path.sep}`))) {
      failures.push(`${taskBriefField}: '${taskBriefPath}' must live under the configured brief directory '${configuredTaskBriefDirectory}'.`);
    }
  }
}

const implementationOwner = extractField(reviewNote, implementationOwnerField).trim();
const agentReportPath = extractField(reviewNote, agentReportField).trim();
if (agentReportPath !== '') {
  const resolvedAgentReportPath = path.resolve(agentReportPath);
  const resolvedAgentReportDirectory = path.resolve(configuredAgentReportDirectory);
  if (!fs.existsSync(resolvedAgentReportPath)) {
    failures.push(`${agentReportField}: '${agentReportPath}' does not exist.`);
  } else if (!(resolvedAgentReportPath === resolvedAgentReportDirectory || resolvedAgentReportPath.startsWith(`${resolvedAgentReportDirectory}${path.sep}`))) {
    failures.push(`${agentReportField}: '${agentReportPath}' must live under the configured agent-report directory '${configuredAgentReportDirectory}'.`);
  } else {
    const agentReport = fs.readFileSync(resolvedAgentReportPath, 'utf8');
    const agentReportRole = extractField(agentReport, 'Role').trim();
    const agentReportFiles = extractField(agentReport, 'Files touched/reviewed').trim();

    if (agentReportRole === '') {
      failures.push(`${agentReportField}: missing '- Role:' in agent report.`);
    } else if (implementationOwner !== '' && agentReportRole !== implementationOwner) {
      failures.push(
        `${agentReportField}: agent report role '${agentReportRole}' does not match ${implementationOwnerField} '${implementationOwner}'.`
      );
    }

    if (agentReportFiles === '') {
      failures.push(`${agentReportField}: missing '- Files touched/reviewed:' in agent report.`);
    } else if (!changedFiles.some((changedFile) => agentReportFiles.includes(changedFile))) {
      failures.push(`${agentReportField}: agent report files do not reference any changed Solidity path.`);
    }
  }
}

const writerDispatchConfirmed = extractField(reviewNote, writerDispatchConfirmedField).trim();

if (writerDispatchConfirmed !== '' && writerDispatchConfirmed !== 'yes') {
  failures.push(`${writerDispatchConfirmedField}: must be 'yes' for Solidity changes.`);
}

const matchedRequiredOwners = new Set();
for (const changedFile of changedFiles) {
  for (const [pattern, owner] of Object.entries(requiredWriterPatterns)) {
    const regex = new RegExp(pattern);
    if (regex.test(changedFile)) {
      matchedRequiredOwners.add(owner);
    }
  }
}

if (matchedRequiredOwners.size > 0 && implementationOwner !== '' && !matchedRequiredOwners.has(implementationOwner)) {
  failures.push(
    `${implementationOwnerField}: '${implementationOwner}' does not match required writer role(s): ${Array.from(matchedRequiredOwners).join(', ')}`
  );
}

for (const pattern of mainSessionForbiddenPatterns) {
  const regex = new RegExp(pattern);
  if (changedFiles.some((changedFile) => regex.test(changedFile)) && implementationOwner === mainSessionRole) {
    failures.push(
      `${implementationOwnerField}: '${mainSessionRole}' is forbidden for the current Solidity write paths.`
    );
    break;
  }
}

for (const field of ownerPrefixedFields) {
  if (typeof field !== 'string' || field.trim() === '') {
    throw new Error('review_note.owner_prefixed_source_fields entries must be non-empty strings');
  }

  const value = extractField(reviewNote, field).trim();
  if (value === '') {
    if (!optionalOwnerPrefixedFields.has(field)) {
      failures.push(`${field}: missing required evidence source.`);
    }
    continue;
  }

  const normalized = value.toLowerCase();
  if (normalized === 'none' || normalized === 'n/a' || normalized === 'na') continue;

  const rawAllowedOwners = fieldOwners?.[field];
  if (rawAllowedOwners !== undefined && typeof rawAllowedOwners !== 'string') {
    throw new Error(`review_note.field_owners['${field}'] must be a pipe-delimited string`);
  }

  const allowedOwners = typeof rawAllowedOwners === 'string'
    ? rawAllowedOwners.split('|').map((owner) => owner.trim()).filter(Boolean)
    : [];

  const entries = value.split(',').map((entry) => entry.trim()).filter(Boolean);
  for (const entry of entries) {
    const separatorIndex = entry.indexOf(':');
    if (separatorIndex <= 0 || separatorIndex >= entry.length - 1) {
      failures.push(
        `${field}: '${entry}' must use '<owner>:<source>' format.`
      );
      continue;
    }

    const owner = entry.slice(0, separatorIndex).trim();
    const source = entry.slice(separatorIndex + 1).trim();
    if (owner === '' || source === '') {
      failures.push(
        `${field}: '${entry}' must include both owner and source after ':'.`
      );
      continue;
    }

    if (allowedOwners.length > 0 && !allowedOwners.includes(owner)) {
      failures.push(
        `${field}: owner '${owner}' is not allowed. Expected one of: ${allowedOwners.join(', ')}`
      );
    }
  }
} 

for (const requirement of evidenceRequirements) {
  if (!evaluateEvidence(requirement.mode, requirement.tests, evidenceValue)) {
    failures.push(
      `${requirement.id}: ${requirement.description || 'Rule evidence requirement failed.'} Triggered by: ${requirement.triggeredBy.join(', ')} Missing review-note evidence in '${evidenceField}' for mode=${requirement.mode}. Expected: ${requirement.tests.join(', ')}`
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
