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

discover_review_note() {
    local changed_files_file="$1"
    local src_sol_pattern="$2"
    shift 2
    local candidates=("$@")

    if [ "${#candidates[@]}" -eq 0 ]; then
        return 1
    fi

    SRC_SOL_PATTERN="$src_sol_pattern" node - "$changed_files_file" "${candidates[@]}" <<'EOF'
const fs = require('fs');

const [, , changedFilesPath, ...candidates] = process.argv;
const srcSolPattern = new RegExp(process.env.SRC_SOL_PATTERN || '^src/.*\\.sol$');
const changedSrcFiles = fs.readFileSync(changedFilesPath, 'utf8').split(/\r?\n/).filter((file) => srcSolPattern.test(file));

function extractField(document, field) {
  const prefix = `- ${field}:`;
  for (const line of document.split(/\r?\n/)) {
    if (line.startsWith(prefix)) {
      return line.slice(prefix.length).trim();
    }
  }
  return '';
}

function extractPathTokens(value) {
  const matches = value.match(/(?:^|[\s,;()[\]{}])((?:\/|(?:\.\.\/)+|\.\/)?[A-Za-z0-9._-]+(?:\/[A-Za-z0-9._-]+)+)(?=$|[\s,;()[\]{}:])/g) || [];
  return matches
    .map((entry) => entry.trim().replace(/^[\s,;()[\]{}]+/, '').replace(/[\s,;()[\]{}:]+$/, ''))
    .filter(Boolean);
}

const matching = candidates.filter((candidate) => {
  const document = fs.readFileSync(candidate, 'utf8');
  const reviewedTokens = new Set(extractPathTokens(extractField(document, 'Files reviewed')));
  return changedSrcFiles.every((changedFile) => reviewedTokens.has(changedFile));
});

if (matching.length === 1) {
  process.stdout.write(matching[0]);
  process.exit(0);
}

if (matching.length === 0) {
  console.error('[check-solidity-review-note] ERROR: review note discovery found no candidate whose Files reviewed field fully references the changed production Solidity path set. Set QUALITY_GATE_REVIEW_NOTE explicitly.');
  process.exit(2);
}

console.error(`[check-solidity-review-note] ERROR: review note discovery matched multiple candidates that each fully reference the changed production Solidity path set (${matching.join(', ')}). Set QUALITY_GATE_REVIEW_NOTE explicitly.`);
process.exit(2);
EOF
}

classification_json=""
codex_local_required_classifications_json='["prod-semantic","high-risk"]'
codex_local_force_env='FORCE_CODEX_REVIEW'

validate_review_note() {
    local review_note="$1"
    local changed_files_tmp="$2"
    local src_sol_pattern="$3"
    local rule_map_path="$4"
    local rule_map_evidence_field="$5"
    local field_owners_json="$6"
    local owner_prefixed_fields_json="$7"
    local solidity_required_fields_json="$8"
    local solidity_boolean_fields_json="$9"
    local task_brief_field="${10}"
    local agent_report_field="${11}"
    local implementation_owner_field="${12}"
    local writer_dispatch_confirmed_field="${13}"
    local required_writer_patterns_json="${14}"
    local task_brief_directory="${15}"
    local agent_report_directory="${16}"
    local main_session_role="${17}"
    local main_session_forbidden_patterns_json="${18}"
    local review_note_files_field="${19}"
    local task_brief_semantic_dimensions_field="${20}"
    local task_brief_source_of_truth_field="${21}"
    local task_brief_external_sources_field="${22}"
    local task_brief_critical_assumptions_field="${23}"
    local task_brief_files_in_scope_field="${24}"
    local task_brief_default_writer_role_field="${25}"
    local task_brief_write_permissions_field="${26}"
    local semantic_dimensions_field="${27}"
    local source_of_truth_field="${28}"
    local external_facts_field="${29}"
    local semantic_alignment_summary_field="${30}"
    local codex_review_task_brief_token="${31}"
    local required_verifier_commands_field="${32}"
    local freshness_source_fields_json="${33}"
    local review_note_must_postdate_agent_report="${34}"
    local agent_report_must_postdate_changed_files="${35}"

    bash ./script/process/check-review-note.sh "$review_note"

    RULE_MAP_PATH="$rule_map_path" \
    RULE_MAP_EVIDENCE_FIELD="$rule_map_evidence_field" \
    SRC_SOL_PATTERN="$src_sol_pattern" \
    REVIEW_FIELD_OWNERS="$field_owners_json" \
    REVIEW_OWNER_PREFIXED_FIELDS="$owner_prefixed_fields_json" \
    SOLIDITY_REQUIRED_FIELDS="$solidity_required_fields_json" \
    SOLIDITY_BOOLEAN_FIELDS="$solidity_boolean_fields_json" \
    TASK_BRIEF_FIELD="$task_brief_field" \
    AGENT_REPORT_FIELD="$agent_report_field" \
    IMPLEMENTATION_OWNER_FIELD="$implementation_owner_field" \
    WRITER_DISPATCH_CONFIRMED_FIELD="$writer_dispatch_confirmed_field" \
    REQUIRED_WRITER_PATTERNS="$required_writer_patterns_json" \
    TASK_BRIEF_DIRECTORY="$task_brief_directory" \
    AGENT_REPORT_DIRECTORY="$agent_report_directory" \
    MAIN_SESSION_ROLE="$main_session_role" \
    MAIN_SESSION_FORBIDDEN_PATTERNS="$main_session_forbidden_patterns_json" \
    REVIEW_NOTE_FILES_FIELD="$review_note_files_field" \
    TASK_BRIEF_SEMANTIC_DIMENSIONS_FIELD="$task_brief_semantic_dimensions_field" \
    TASK_BRIEF_SOURCE_OF_TRUTH_FIELD="$task_brief_source_of_truth_field" \
    TASK_BRIEF_EXTERNAL_SOURCES_FIELD="$task_brief_external_sources_field" \
    TASK_BRIEF_CRITICAL_ASSUMPTIONS_FIELD="$task_brief_critical_assumptions_field" \
    TASK_BRIEF_FILES_IN_SCOPE_FIELD="$task_brief_files_in_scope_field" \
    TASK_BRIEF_DEFAULT_WRITER_ROLE_FIELD="$task_brief_default_writer_role_field" \
    TASK_BRIEF_WRITE_PERMISSIONS_FIELD="$task_brief_write_permissions_field" \
    SEMANTIC_DIMENSIONS_FIELD="$semantic_dimensions_field" \
    SOURCE_OF_TRUTH_FIELD="$source_of_truth_field" \
    EXTERNAL_FACTS_FIELD="$external_facts_field" \
    SEMANTIC_ALIGNMENT_SUMMARY_FIELD="$semantic_alignment_summary_field" \
    CODEX_REVIEW_TASK_BRIEF_TOKEN="$codex_review_task_brief_token" \
    REQUIRED_VERIFIER_COMMANDS_FIELD="$required_verifier_commands_field" \
    FRESHNESS_SOURCE_FIELDS="$freshness_source_fields_json" \
    REVIEW_NOTE_MUST_POSTDATE_AGENT_REPORT="$review_note_must_postdate_agent_report" \
    AGENT_REPORT_MUST_POSTDATE_CHANGED_FILES="$agent_report_must_postdate_changed_files" \
    CLASSIFICATION_RESULT="$classification_json" \
    CODEX_LOCAL_REQUIRED_CLASSIFICATIONS="$codex_local_required_classifications_json" \
    CODEX_LOCAL_FORCE_ENV="$codex_local_force_env" \
    node - "$review_note" "$changed_files_tmp" <<'EOF'
const fs = require('fs');
const childProcess = require('child_process');
const path = require('path');

const [, , reviewNotePath, changedFilesPath] = process.argv;
const reviewNote = fs.readFileSync(reviewNotePath, 'utf8');
const changedFiles = fs.readFileSync(changedFilesPath, 'utf8').split(/\r?\n/).filter(Boolean);
const srcSolPattern = new RegExp(process.env.SRC_SOL_PATTERN || '^src/.*\\.sol$');
const changedSrcFiles = changedFiles.filter((file) => srcSolPattern.test(file));
const evidenceField = process.env.RULE_MAP_EVIDENCE_FIELD || 'Existing tests exercised';
const fieldOwners = JSON.parse(process.env.REVIEW_FIELD_OWNERS || '{}');
const ownerPrefixedFields = JSON.parse(process.env.REVIEW_OWNER_PREFIXED_FIELDS || '[]');
const solidityRequiredFields = JSON.parse(process.env.SOLIDITY_REQUIRED_FIELDS || '[]');
const solidityBooleanFields = JSON.parse(process.env.SOLIDITY_BOOLEAN_FIELDS || '[]');
const requiredWriterPatterns = JSON.parse(process.env.REQUIRED_WRITER_PATTERNS || '{}');
const configuredTaskBriefDirectory = process.env.TASK_BRIEF_DIRECTORY || 'docs/task-briefs';
const configuredAgentReportDirectory = process.env.AGENT_REPORT_DIRECTORY || 'docs/agent-reports';
const mainSessionForbiddenPatterns = JSON.parse(process.env.MAIN_SESSION_FORBIDDEN_PATTERNS || '[]');
const freshnessSourceFields = JSON.parse(process.env.FRESHNESS_SOURCE_FIELDS || '[]');
const taskBriefField = process.env.TASK_BRIEF_FIELD || 'Task Brief path';
const agentReportField = process.env.AGENT_REPORT_FIELD || 'Agent Report path';
const implementationOwnerField = process.env.IMPLEMENTATION_OWNER_FIELD || 'Implementation owner';
const writerDispatchConfirmedField = process.env.WRITER_DISPATCH_CONFIRMED_FIELD || 'Writer dispatch confirmed';
const reviewNoteFilesField = process.env.REVIEW_NOTE_FILES_FIELD || 'Files reviewed';
const taskBriefSemanticDimensionsField = process.env.TASK_BRIEF_SEMANTIC_DIMENSIONS_FIELD || 'Semantic review dimensions';
const taskBriefSourceOfTruthField = process.env.TASK_BRIEF_SOURCE_OF_TRUTH_FIELD || 'Source-of-truth docs';
const taskBriefExternalSourcesField = process.env.TASK_BRIEF_EXTERNAL_SOURCES_FIELD || 'External sources required';
const taskBriefCriticalAssumptionsField = process.env.TASK_BRIEF_CRITICAL_ASSUMPTIONS_FIELD || 'Critical assumptions to prove or reject';
const taskBriefFilesInScopeField = process.env.TASK_BRIEF_FILES_IN_SCOPE_FIELD || 'Files in scope';
const taskBriefDefaultWriterRoleField = process.env.TASK_BRIEF_DEFAULT_WRITER_ROLE_FIELD || 'Default writer role';
const taskBriefWritePermissionsField = process.env.TASK_BRIEF_WRITE_PERMISSIONS_FIELD || 'Write permissions';
const semanticDimensionsField = process.env.SEMANTIC_DIMENSIONS_FIELD || 'Semantic dimensions reviewed';
const sourceOfTruthField = process.env.SOURCE_OF_TRUTH_FIELD || 'Source-of-truth docs checked';
const externalFactsField = process.env.EXTERNAL_FACTS_FIELD || 'External facts checked';
const semanticAlignmentSummaryField = process.env.SEMANTIC_ALIGNMENT_SUMMARY_FIELD || 'Semantic alignment summary';
const codexReviewTaskBriefToken = process.env.CODEX_REVIEW_TASK_BRIEF_TOKEN || 'npm run codex:review';
const requiredVerifierCommandsField = process.env.REQUIRED_VERIFIER_COMMANDS_FIELD || 'Required verifier commands';
const classificationResult = JSON.parse(process.env.CLASSIFICATION_RESULT || '{}');
const codexLocalRequiredClassifications = JSON.parse(process.env.CODEX_LOCAL_REQUIRED_CLASSIFICATIONS || '["prod-semantic","high-risk"]');
const codexLocalForceEnv = process.env.CODEX_LOCAL_FORCE_ENV || 'FORCE_CODEX_REVIEW';
const mainSessionRole = process.env.MAIN_SESSION_ROLE || 'main-orchestrator';
const reviewNoteMustPostdateAgentReport = process.env.REVIEW_NOTE_MUST_POSTDATE_AGENT_REPORT === 'true';
const agentReportMustPostdateChangedFiles = process.env.AGENT_REPORT_MUST_POSTDATE_CHANGED_FILES === 'true';
const optionalOwnerPrefixedFields = new Set(['Rule-map evidence source']);
const classifierClassification = classificationResult.classification || 'none';

function extractField(document, field) {
  const prefix = `- ${field}:`;
  for (const line of document.split(/\r?\n/)) {
    if (line.startsWith(prefix)) {
      return line.slice(prefix.length).trim();
    }
  }
  return '';
}

function splitFieldValues(value) {
  return value
    .split(/[;\n]/)
    .map((entry) => entry.trim())
    .filter(Boolean);
}

function normalizeComparable(value) {
  return value.trim().toLowerCase();
}

function isNoneLike(value) {
  const normalized = normalizeComparable(value);
  return normalized === '' || normalized === 'none' || normalized === 'n/a' || normalized === 'na';
}

function isTruthy(value) {
  return /^(1|true|yes|on)$/i.test(String(value || '').trim());
}

function includesEveryExpected(actualValue, expectedValue) {
  if (isNoneLike(expectedValue)) return true;

  const actualEntries = splitFieldValues(actualValue).map(normalizeComparable);
  const expectedEntries = splitFieldValues(expectedValue).map(normalizeComparable);
  return expectedEntries.every((entry) => actualEntries.includes(entry));
}

function extractPathTokens(value) {
  const matches = value.match(/(?:^|[\s,;()[\]{}])((?:\/|(?:\.\.\/)+|\.\/)?[A-Za-z0-9._-]+(?:\/[A-Za-z0-9._-]+)+)(?=$|[\s,;()[\]{}:])/g) || [];
  return matches
    .map((entry) => entry.trim().replace(/^[\s,;()[\]{}]+/, '').replace(/[\s,;()[\]{}:]+$/, ''))
    .filter(Boolean);
}

function referencesAllChangedSrcPaths(value) {
  const reviewedTokens = new Set(extractPathTokens(value));
  return changedSrcFiles.every((changedFile) => reviewedTokens.has(changedFile));
}

function ensureUnderDirectory(candidatePath, directoryPath) {
  const resolvedCandidate = path.resolve(candidatePath);
  const resolvedDirectory = path.resolve(directoryPath);
  return (
    resolvedCandidate === resolvedDirectory ||
    resolvedCandidate.startsWith(`${resolvedDirectory}${path.sep}`)
  );
}

function parseOwnerPrefixedEntries(value) {
  return value
    .split(',')
    .map((entry) => entry.trim())
    .filter(Boolean)
    .map((entry) => {
      const separatorIndex = entry.indexOf(':');
      return {
        entry,
        owner: separatorIndex > -1 ? entry.slice(0, separatorIndex).trim() : '',
        source: separatorIndex > -1 ? entry.slice(separatorIndex + 1).trim() : '',
      };
    });
}

function evaluateEvidence(mode, candidates, evidenceValue) {
  if (mode === 'none') return true;
  if (candidates.length === 0) return true;
  if (mode === 'any') return candidates.some((candidate) => evidenceValue.includes(candidate));
  if (mode === 'all') return candidates.every((candidate) => evidenceValue.includes(candidate));
  throw new Error(`Unsupported evidence_requirement mode: ${mode}`);
}

function fileMtimeMs(filePath) {
  return fs.statSync(filePath).mtimeMs;
}

function gatherEvidenceRequirements() {
  try {
    return JSON.parse(
      childProcess.execFileSync(
        'node',
        ['./script/process/read-process-config.js', 'rule-map', 'triggered.evidence.requirements'],
        {
          cwd: process.cwd(),
          env: {
            ...process.env,
            PROCESS_CHANGED_FILES_FILE: changedFilesPath,
            PROCESS_RULE_MAP_FILE: process.env.RULE_MAP_PATH,
          },
          encoding: 'utf8',
        }
      )
    );
  } catch (error) {
    return [];
  }
}

const evidenceRequirements = gatherEvidenceRequirements();
const failures = [];

if (changedSrcFiles.length === 0) {
  process.exit(0);
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
if (!Array.isArray(freshnessSourceFields)) {
  throw new Error('solidity_review_note.freshness_source_fields must be an array');
}

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

const reviewNoteFiles = extractField(reviewNote, reviewNoteFilesField).trim();
if (!referencesAllChangedSrcPaths(reviewNoteFiles)) {
  failures.push(
    `${reviewNoteFilesField}: review note must reference the full changed production Solidity path set: ${changedSrcFiles.join(', ')}`
  );
}

const taskBriefPath = extractField(reviewNote, taskBriefField).trim();
let taskBrief = '';
if (taskBriefPath !== '') {
  const resolvedTaskBriefPath = path.resolve(taskBriefPath);
  if (!fs.existsSync(resolvedTaskBriefPath)) {
    failures.push(`${taskBriefField}: '${taskBriefPath}' does not exist.`);
  } else if (!ensureUnderDirectory(resolvedTaskBriefPath, configuredTaskBriefDirectory)) {
    failures.push(
      `${taskBriefField}: '${taskBriefPath}' must live under the configured task-brief directory '${configuredTaskBriefDirectory}'.`
    );
  } else {
    taskBrief = fs.readFileSync(resolvedTaskBriefPath, 'utf8');
    const taskBriefFilesInScope = extractField(taskBrief, taskBriefFilesInScopeField).trim();
    if (!referencesAllChangedSrcPaths(taskBriefFilesInScope)) {
      failures.push(
        `${taskBriefFilesInScopeField}: task brief must include the full changed production Solidity path set: ${changedSrcFiles.join(', ')}`
      );
    }

    const taskBriefWritePermissions = extractField(taskBrief, taskBriefWritePermissionsField).trim();
    if (!referencesAllChangedSrcPaths(taskBriefWritePermissions)) {
      failures.push(
        `${taskBriefWritePermissionsField}: task brief must include the full changed production Solidity path set: ${changedSrcFiles.join(', ')}`
      );
    }

    const taskBriefDefaultWriterRole = extractField(taskBrief, taskBriefDefaultWriterRoleField).trim();
    if (taskBriefDefaultWriterRole === '') {
      failures.push(`${taskBriefDefaultWriterRoleField}: task brief field must not be blank.`);
    }

    const requiredVerifierCommands = extractField(taskBrief, requiredVerifierCommandsField).trim();
    const localCodexReviewRequired =
      (Array.isArray(codexLocalRequiredClassifications) && codexLocalRequiredClassifications.includes(classifierClassification)) ||
      isTruthy(process.env[codexLocalForceEnv]);
    if (localCodexReviewRequired && !requiredVerifierCommands.includes(codexReviewTaskBriefToken)) {
      failures.push(
        `${requiredVerifierCommandsField}: must include '${codexReviewTaskBriefToken}' for Solidity changes.`
      );
    }

    const expectedSemanticDimensions = extractField(taskBrief, taskBriefSemanticDimensionsField).trim();
    const actualSemanticDimensions = extractField(reviewNote, semanticDimensionsField).trim();
    if (!includesEveryExpected(actualSemanticDimensions, expectedSemanticDimensions)) {
      failures.push(
        `${semanticDimensionsField}: does not cover task brief ${taskBriefSemanticDimensionsField} '${expectedSemanticDimensions}'.`
      );
    }

    const expectedSourceDocs = extractField(taskBrief, taskBriefSourceOfTruthField).trim();
    const actualSourceDocs = extractField(reviewNote, sourceOfTruthField).trim();
    if (!includesEveryExpected(actualSourceDocs, expectedSourceDocs)) {
      failures.push(
        `${sourceOfTruthField}: does not cover task brief ${taskBriefSourceOfTruthField} '${expectedSourceDocs}'.`
      );
    }

    const expectedExternalSources = extractField(taskBrief, taskBriefExternalSourcesField).trim();
    const actualExternalFacts = extractField(reviewNote, externalFactsField).trim();
    if (!includesEveryExpected(actualExternalFacts, expectedExternalSources)) {
      failures.push(
        `${externalFactsField}: does not cover task brief ${taskBriefExternalSourcesField} '${expectedExternalSources}'.`
      );
    }

    const expectedAssumptions = extractField(taskBrief, taskBriefCriticalAssumptionsField).trim();
    const semanticAlignmentSummary = extractField(reviewNote, semanticAlignmentSummaryField).trim();
    if (!includesEveryExpected(semanticAlignmentSummary, expectedAssumptions)) {
      failures.push(
        `${taskBriefCriticalAssumptionsField}: review note ${semanticAlignmentSummaryField} does not cover '${expectedAssumptions}'.`
      );
    }
  }
}

const implementationOwner = extractField(reviewNote, implementationOwnerField).trim();
const writerDispatchConfirmed = extractField(reviewNote, writerDispatchConfirmedField).trim();
if (writerDispatchConfirmed !== '' && writerDispatchConfirmed !== 'yes') {
  failures.push(`${writerDispatchConfirmedField}: must be 'yes' for Solidity changes.`);
}

const matchedRequiredOwners = new Set();
for (const changedFile of changedFiles) {
  for (const [pattern, owner] of Object.entries(requiredWriterPatterns)) {
    if (new RegExp(pattern).test(changedFile)) {
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
    failures.push(`${implementationOwnerField}: '${mainSessionRole}' is forbidden for the current Solidity write paths.`);
    break;
  }
}

const agentReportPath = extractField(reviewNote, agentReportField).trim();
let agentReportMtime = null;
if (agentReportPath !== '') {
  const resolvedAgentReportPath = path.resolve(agentReportPath);
  if (!fs.existsSync(resolvedAgentReportPath)) {
    failures.push(`${agentReportField}: '${agentReportPath}' does not exist.`);
  } else if (!ensureUnderDirectory(resolvedAgentReportPath, configuredAgentReportDirectory)) {
    failures.push(
      `${agentReportField}: '${agentReportPath}' must live under the configured agent-report directory '${configuredAgentReportDirectory}'.`
    );
  } else {
    const agentReport = fs.readFileSync(resolvedAgentReportPath, 'utf8');
    const agentReportRole = extractField(agentReport, 'Role').trim();
    const agentReportFiles = extractField(agentReport, 'Files touched/reviewed').trim();
    agentReportMtime = fileMtimeMs(resolvedAgentReportPath);

    if (agentReportRole === '') {
      failures.push(`${agentReportField}: missing '- Role:' in agent report.`);
    } else if (implementationOwner !== '' && agentReportRole !== implementationOwner) {
      failures.push(
        `${agentReportField}: agent report role '${agentReportRole}' does not match ${implementationOwnerField} '${implementationOwner}'.`
      );
    }

    if (agentReportFiles === '') {
      failures.push(`${agentReportField}: missing '- Files touched/reviewed:' in agent report.`);
    } else if (!referencesAllChangedSrcPaths(agentReportFiles)) {
      failures.push(
        `${agentReportField}: agent report must reference the full changed production Solidity path set: ${changedSrcFiles.join(', ')}`
      );
    }

    if (agentReportMustPostdateChangedFiles) {
      for (const changedSrcFile of changedSrcFiles) {
        if (!fs.existsSync(changedSrcFile)) continue;
        if (agentReportMtime <= fileMtimeMs(changedSrcFile)) {
          failures.push(
            `${agentReportField}: stale evidence. Agent Report must postdate changed production Solidity file '${changedSrcFile}'.`
          );
          break;
        }
      }
    }

    if (reviewNoteMustPostdateAgentReport) {
      const reviewNoteMtime = fileMtimeMs(reviewNotePath);
      if (reviewNoteMtime <= agentReportMtime) {
        failures.push(
          `${agentReportField}: stale evidence. Review note must postdate the current writer Agent Report.`
        );
      }
    }
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

  if (isNoneLike(value)) continue;

  const rawAllowedOwners = fieldOwners?.[field];
  if (rawAllowedOwners !== undefined && typeof rawAllowedOwners !== 'string') {
    throw new Error(`review_note.field_owners['${field}'] must be a pipe-delimited string`);
  }

  const allowedOwners = typeof rawAllowedOwners === 'string'
    ? rawAllowedOwners.split('|').map((owner) => owner.trim()).filter(Boolean)
    : [];

  for (const parsedEntry of parseOwnerPrefixedEntries(value)) {
    if (parsedEntry.owner === '' || parsedEntry.source === '') {
      failures.push(`${field}: '${parsedEntry.entry}' must use '<owner>:<source>' format.`);
      continue;
    }

    if (allowedOwners.length > 0 && !allowedOwners.includes(parsedEntry.owner)) {
      failures.push(
        `${field}: owner '${parsedEntry.owner}' is not allowed. Expected one of: ${allowedOwners.join(', ')}`
      );
    }

    if (
      agentReportMtime != null &&
      freshnessSourceFields.includes(field) &&
      fs.existsSync(parsedEntry.source) &&
      fs.statSync(parsedEntry.source).isFile() &&
      fileMtimeMs(parsedEntry.source) <= agentReportMtime
    ) {
      failures.push(
        `${field}: stale evidence. '${parsedEntry.source}' predates the current writer Agent Report.`
      );
    }
  }
}

const evidenceValue = extractField(reviewNote, evidenceField);
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
}

changed_files="$(load_changed_files)"
if [ -z "$changed_files" ]; then
    exit 0
fi

changed_files_tmp="$(mktemp)"
trap 'rm -f "$changed_files_tmp"' EXIT
printf '%s\n' "$changed_files" > "$changed_files_tmp"
classification_json="$(QUALITY_GATE_MODE="$mode" QUALITY_GATE_FILE_LIST="$changed_files_tmp" CHANGE_CLASSIFIER_FORCE="${CHANGE_CLASSIFIER_FORCE:-}" CHANGE_CLASSIFIER_DIFF_FILE="${CHANGE_CLASSIFIER_DIFF_FILE:-}" node ./script/process/classify-change.js)"

src_sol_pattern="$(read_policy_value quality_gate.src_sol_pattern '^src/.*\.sol$')"
script_sol_pattern="$(read_policy_value quality_gate.script_sol_pattern '^script/.*\.sol$')"
if ! node - "$changed_files_tmp" "$src_sol_pattern" "$script_sol_pattern" <<'EOF'
const fs = require('fs');
const [changedFilesPath, srcPatternText, scriptPatternText] = process.argv.slice(2);
const srcPattern = new RegExp(srcPatternText);
const scriptPattern = new RegExp(scriptPatternText);
const changedFiles = fs.readFileSync(changedFilesPath, 'utf8').split(/\r?\n/).filter(Boolean);
process.exit(changedFiles.some((file) => srcPattern.test(file) || scriptPattern.test(file)) ? 0 : 1);
EOF
then
    exit 0
fi

review_dir="$(read_policy_value quality_gate.review_note_directory 'docs/reviews')"
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
task_brief_directory="$(read_policy_value agents.task_brief_directory 'docs/task-briefs')"
agent_report_directory="$(read_policy_value agents.agent_report_directory 'docs/agent-reports')"
main_session_role="$(read_policy_value agents.main_session_role 'main-orchestrator')"
main_session_forbidden_patterns_json="$(read_policy_value agents.main_session_forbidden_write_patterns '[]')"
review_note_files_field="$(read_policy_value review_note.files_field 'Files reviewed')"
task_brief_semantic_dimensions_field="$(read_policy_value solidity_review_note.task_brief_semantic_dimensions_field 'Semantic review dimensions')"
task_brief_source_of_truth_field="$(read_policy_value solidity_review_note.task_brief_source_of_truth_field 'Source-of-truth docs')"
task_brief_external_sources_field="$(read_policy_value solidity_review_note.task_brief_external_sources_field 'External sources required')"
task_brief_critical_assumptions_field="$(read_policy_value solidity_review_note.task_brief_critical_assumptions_field 'Critical assumptions to prove or reject')"
task_brief_files_in_scope_field="$(read_policy_value solidity_review_note.task_brief_files_in_scope_field 'Files in scope')"
task_brief_default_writer_role_field="$(read_policy_value solidity_review_note.task_brief_default_writer_role_field 'Default writer role')"
task_brief_write_permissions_field="$(read_policy_value solidity_review_note.task_brief_write_permissions_field 'Write permissions')"
semantic_dimensions_field="$(read_policy_value solidity_review_note.semantic_dimensions_field 'Semantic dimensions reviewed')"
source_of_truth_field="$(read_policy_value solidity_review_note.source_of_truth_field 'Source-of-truth docs checked')"
external_facts_field="$(read_policy_value solidity_review_note.external_facts_field 'External facts checked')"
semantic_alignment_summary_field="$(read_policy_value solidity_review_note.semantic_alignment_summary_field 'Semantic alignment summary')"
required_verifier_commands_field="$(read_policy_value task_brief.required_verifier_commands_field 'Required verifier commands')"
codex_review_task_brief_token="$(read_policy_value verifier.codex_review.task_brief_token 'npm run codex:review')"
codex_local_required_classifications_json="$(read_policy_value verifier.local_codex_review.required_classifications '["prod-semantic","high-risk"]')"
codex_local_force_env="$(read_policy_value verifier.local_codex_review.force_env 'FORCE_CODEX_REVIEW')"
freshness_source_fields_json="$(read_policy_value solidity_review_note.freshness_source_fields '[]')"
if [ "$freshness_source_fields_json" = '[]' ]; then
    freshness_source_fields_json='["Logic evidence source","Security evidence source","Gas evidence source","Verification evidence source"]'
fi
review_note_must_postdate_agent_report="$(read_policy_value solidity_review_note.review_note_must_postdate_agent_report true)"
agent_report_must_postdate_changed_files="$(read_policy_value solidity_review_note.agent_report_must_postdate_changed_files true)"

review_note="${QUALITY_GATE_REVIEW_NOTE:-}"

if [ -n "$review_note" ]; then
    if [ ! -f "$review_note" ]; then
        echo "[check-solidity-review-note] ERROR: review note not found. Set QUALITY_GATE_REVIEW_NOTE or add one under the configured review note directory."
        exit 1
    fi

    validate_review_note \
        "$review_note" \
        "$changed_files_tmp" \
        "$src_sol_pattern" \
        "$rule_map_path" \
        "$rule_map_evidence_field" \
        "$field_owners_json" \
        "$owner_prefixed_fields_json" \
        "$solidity_required_fields_json" \
        "$solidity_boolean_fields_json" \
        "$task_brief_field" \
        "$agent_report_field" \
        "$implementation_owner_field" \
        "$writer_dispatch_confirmed_field" \
        "$required_writer_patterns_json" \
        "$task_brief_directory" \
        "$agent_report_directory" \
        "$main_session_role" \
        "$main_session_forbidden_patterns_json" \
        "$review_note_files_field" \
        "$task_brief_semantic_dimensions_field" \
        "$task_brief_source_of_truth_field" \
        "$task_brief_external_sources_field" \
        "$task_brief_critical_assumptions_field" \
        "$task_brief_files_in_scope_field" \
        "$task_brief_default_writer_role_field" \
        "$task_brief_write_permissions_field" \
        "$semantic_dimensions_field" \
        "$source_of_truth_field" \
        "$external_facts_field" \
        "$semantic_alignment_summary_field" \
        "$codex_review_task_brief_token" \
        "$required_verifier_commands_field" \
        "$freshness_source_fields_json" \
        "$review_note_must_postdate_agent_report" \
        "$agent_report_must_postdate_changed_files"
    exit 0
fi

if [ ! -d "$review_dir" ]; then
    echo "[check-solidity-review-note] ERROR: review note not found. Set QUALITY_GATE_REVIEW_NOTE or add one under the configured review note directory."
    exit 1
fi

mapfile -t review_notes < <(
    find "$review_dir" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' ! -name 'TEMPLATE.md' -printf '%T@ %p\n' \
        | sort -nr \
        | cut -d' ' -f2-
)

if [ "${#review_notes[@]}" -eq 0 ]; then
    echo "[check-solidity-review-note] ERROR: review note not found. Set QUALITY_GATE_REVIEW_NOTE or add one under the configured review note directory."
    exit 1
fi

review_note="$(discover_review_note "$changed_files_tmp" "$src_sol_pattern" "${review_notes[@]}" || true)"
if [ -z "$review_note" ] || [ ! -f "$review_note" ]; then
    echo "[check-solidity-review-note] ERROR: review note not found. Set QUALITY_GATE_REVIEW_NOTE or add one under the configured review note directory."
    exit 1
fi

validate_review_note \
    "$review_note" \
    "$changed_files_tmp" \
    "$src_sol_pattern" \
    "$rule_map_path" \
    "$rule_map_evidence_field" \
    "$field_owners_json" \
    "$owner_prefixed_fields_json" \
    "$solidity_required_fields_json" \
    "$solidity_boolean_fields_json" \
    "$task_brief_field" \
    "$agent_report_field" \
    "$implementation_owner_field" \
    "$writer_dispatch_confirmed_field" \
    "$required_writer_patterns_json" \
    "$task_brief_directory" \
    "$agent_report_directory" \
    "$main_session_role" \
    "$main_session_forbidden_patterns_json" \
    "$review_note_files_field" \
    "$task_brief_semantic_dimensions_field" \
    "$task_brief_source_of_truth_field" \
    "$task_brief_external_sources_field" \
    "$task_brief_critical_assumptions_field" \
    "$task_brief_files_in_scope_field" \
    "$task_brief_default_writer_role_field" \
    "$task_brief_write_permissions_field" \
    "$semantic_dimensions_field" \
    "$source_of_truth_field" \
    "$external_facts_field" \
    "$semantic_alignment_summary_field" \
    "$codex_review_task_brief_token" \
    "$required_verifier_commands_field" \
    "$freshness_source_fields_json" \
    "$review_note_must_postdate_agent_report" \
    "$agent_report_must_postdate_changed_files"
