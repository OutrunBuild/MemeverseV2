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

codex_review_task_brief_token="$(read_policy_value verifier.codex_review.task_brief_token 'npm run codex:review')"
task_brief_directory="$(read_policy_value agents.task_brief_directory 'docs/task-briefs')"
agent_report_directory="$(read_policy_value agents.agent_report_directory 'docs/agent-reports')"

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
    shift
    local candidates=("$@")

    if [ "${#candidates[@]}" -eq 0 ]; then
        return 1
    fi

    node - "$changed_files_file" "${candidates[@]}" <<'EOF'
const fs = require('fs');

const [, , changedFilesPath, ...candidates] = process.argv;
const changedFiles = fs.readFileSync(changedFilesPath, 'utf8').split(/\r?\n/).filter(Boolean);
const changedSolidityFiles = changedFiles.filter((file) => /^(src|script|test)\/.*\.sol$/.test(file));
const changedProductionSolidityFiles = changedFiles.filter((file) => /^(src|script)\/.*\.sol$/.test(file));
const targetSolidityFiles = changedProductionSolidityFiles.length > 0 ? changedProductionSolidityFiles : changedSolidityFiles;

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
  const filesReviewed = extractField(document, 'Files reviewed');
  const reviewedTokens = new Set(extractPathTokens(filesReviewed));
  return targetSolidityFiles.some((changedFile) => reviewedTokens.has(changedFile));
});

if (matching.length === 1) {
  process.stdout.write(matching[0]);
  process.exit(0);
}

process.exit(1);
EOF
}

discover_spec_review_report() {
    local changed_files_file="$1"
    shift
    local candidates=("$@")

    if [ "${#candidates[@]}" -eq 0 ]; then
        return 1
    fi

    TASK_BRIEF_DIRECTORY="$task_brief_directory" node - "$changed_files_file" "${candidates[@]}" <<'EOF'
const fs = require('fs');

const [, , changedFilesPath, ...candidates] = process.argv;
const changedFiles = fs.readFileSync(changedFilesPath, 'utf8').split(/\r?\n/).filter(Boolean);
const taskBriefDirectory = process.env.TASK_BRIEF_DIRECTORY || 'docs/task-briefs';
const changedSpecFiles = changedFiles.filter((file) => /^(docs\/spec\/.*|docs\/superpowers\/specs\/.*)$/.test(file));
const changedSet = new Set(changedFiles);
const changedTaskBriefFiles = changedFiles.filter((file) => file.startsWith(`${taskBriefDirectory}/`) && fs.existsSync(file));

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

function isTruthy(value) {
  return /^(yes|true|1)$/i.test(String(value || '').trim());
}

const briefDeclaredSpecPaths = [];
for (const briefPath of changedTaskBriefFiles) {
  const brief = fs.readFileSync(briefPath, 'utf8');
  if (
    extractField(brief, 'Artifact type').trim() === 'spec'
    || isTruthy(extractField(brief, 'Spec review required'))
  ) {
    for (const artifactPath of extractPathTokens(extractField(brief, 'Spec artifact paths'))) {
      briefDeclaredSpecPaths.push(artifactPath);
    }
  }
}

const matching = candidates.filter((candidate) => {
  const document = fs.readFileSync(candidate, 'utf8');
  if (!document.startsWith('# Agent Report')) return false;
  if (extractField(document, 'Role').trim() !== 'spec-reviewer') return false;

  const taskBriefPath = extractField(document, 'Task Brief path');
  const taskBrief = taskBriefPath && fs.existsSync(taskBriefPath) ? fs.readFileSync(taskBriefPath, 'utf8') : '';
  const declaredSpecPaths = taskBrief && (
    extractField(taskBrief, 'Artifact type').trim() === 'spec'
    || isTruthy(extractField(taskBrief, 'Spec review required'))
  )
    ? extractPathTokens(extractField(taskBrief, 'Spec artifact paths'))
    : [];
  const filesReviewed = new Set(extractPathTokens(extractField(document, 'Files touched/reviewed')));
  const targetSpecFiles = [...new Set([
    ...changedSpecFiles,
    ...briefDeclaredSpecPaths,
    ...(changedSet.has(taskBriefPath) ? declaredSpecPaths : []),
    ...declaredSpecPaths.filter((artifactPath) => changedSet.has(artifactPath)),
    ...declaredSpecPaths.filter((artifactPath) => briefDeclaredSpecPaths.includes(artifactPath))
  ])];
  return targetSpecFiles.some((changedFile) => filesReviewed.has(changedFile));
});

if (matching.length > 0) {
  matching.sort((left, right) => fs.statSync(right).mtimeMs - fs.statSync(left).mtimeMs);
  process.stdout.write(matching[0]);
  process.exit(0);
}

process.exit(1);
EOF
}

changed_files="$(load_changed_files)"

if [ -z "$changed_files" ]; then
    echo "[stale-evidence-loop] no changed files detected."
    exit 0
fi

changed_files_tmp="$(mktemp)"
metadata_tmp="$(mktemp)"
trap 'rm -f "$changed_files_tmp" "$metadata_tmp"' EXIT
printf '%s\n' "$changed_files" > "$changed_files_tmp"

spec_review_report="${QUALITY_GATE_SPEC_REVIEWER_REPORT:-}"
if [ -z "$spec_review_report" ] && [ -d "$agent_report_directory" ]; then
    mapfile -t spec_review_candidates < <(find "$agent_report_directory" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' ! -name 'TEMPLATE.md' | sort)
    spec_review_report="$(discover_spec_review_report "$changed_files_tmp" "${spec_review_candidates[@]}" || true)"
fi
if [ -n "$spec_review_report" ]; then
    if [ ! -f "$spec_review_report" ]; then
        echo "[stale-evidence-loop] ERROR: spec-reviewer Agent Report not found. Set QUALITY_GATE_SPEC_REVIEWER_REPORT to a valid report path." >&2
        exit 1
    fi

    spec_surface_pattern="$(read_policy_value quality_gate.spec_surface_pattern '^(docs/spec/.*|docs/superpowers/specs/.*)$')"
    follow_up_dir="${FOLLOW_UP_BRIEF_OUTPUT_DIR:-$(read_policy_value agents.task_brief_directory 'docs/task-briefs')}"
    agent_report_directory="$(read_policy_value agents.agent_report_directory 'docs/agent-reports')"
    spec_output_file="$(mktemp)"
    mkdir -p "$follow_up_dir"

    set +e
    FOLLOW_UP_DIR="$follow_up_dir" \
    REMEDIATION_METADATA_FILE="$metadata_tmp" \
    REMEDIATION_LOOP_DATE="${REMEDIATION_LOOP_DATE:-$(date +%F)}" \
    AGENT_REPORT_DIRECTORY="$agent_report_directory" \
    SPEC_SURFACE_PATTERN="$spec_surface_pattern" \
    node - "$spec_review_report" "$changed_files_tmp" >"$spec_output_file" 2>&1 <<'EOF'
const fs = require('fs');
const path = require('path');

const [, , specReviewReportPath, changedFilesPath] = process.argv;
const specReviewReport = fs.readFileSync(specReviewReportPath, 'utf8');
const changedFiles = fs.readFileSync(changedFilesPath, 'utf8').split(/\r?\n/).filter(Boolean);
const followUpDir = process.env.FOLLOW_UP_DIR;
const metadataFile = process.env.REMEDIATION_METADATA_FILE;
const loopDate = process.env.REMEDIATION_LOOP_DATE || new Date().toISOString().slice(0, 10);
const agentReportDirectory = path.resolve(process.env.AGENT_REPORT_DIRECTORY || 'docs/agent-reports');
const specSurfacePattern = new RegExp(process.env.SPEC_SURFACE_PATTERN || '^(docs/spec/.*|docs/superpowers/specs/.*)$');

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

function dedupe(items) {
  const seen = new Set();
  return items.filter((item) => {
    if (!item || seen.has(item)) return false;
    seen.add(item);
    return true;
  });
}

function resolveUniqueOutput(basePath) {
  if (!fs.existsSync(basePath)) return basePath;
  const ext = path.extname(basePath);
  const stem = basePath.slice(0, -ext.length);
  let counter = 2;
  while (true) {
    const candidate = `${stem}-${counter}${ext}`;
    if (!fs.existsSync(candidate)) return candidate;
    counter += 1;
  }
}

function findLatestReport(directory, role, taskBriefPath) {
  if (!fs.existsSync(directory)) return '';

  const candidates = fs
    .readdirSync(directory)
    .filter((entry) => entry.endsWith('.md') && entry !== 'README.md' && entry !== 'TEMPLATE.md')
    .map((entry) => path.join(directory, entry))
    .filter((candidate) => {
      const document = fs.readFileSync(candidate, 'utf8');
      return extractField(document, 'Role').trim() === role && extractField(document, 'Task Brief path').trim() === taskBriefPath;
    });

  if (candidates.length === 0) return '';
  candidates.sort((left, right) => fs.statSync(right).mtimeMs - fs.statSync(left).mtimeMs);
  return candidates[0];
}

const taskBriefPath = extractField(specReviewReport, 'Task Brief path');
const implementationOwner = extractField(specReviewReport, 'Implementation owner') || 'process-implementer';
const reportMtime = fs.statSync(specReviewReportPath).mtimeMs;
const taskBrief = taskBriefPath && fs.existsSync(taskBriefPath) ? fs.readFileSync(taskBriefPath, 'utf8') : '';
const defaultWriterRole = extractField(taskBrief, 'Default writer role') || implementationOwner;
const declaredSpecFiles = dedupe(extractPathTokens(extractField(taskBrief, 'Spec artifact paths')));
const specFiles = dedupe([
  ...changedFiles.filter((file) => specSurfacePattern.test(file)),
  ...declaredSpecFiles
]);
const specArtifactPaths = extractField(taskBrief, 'Spec artifact paths') || specFiles.join(', ');
const artifactType = extractField(taskBrief, 'Artifact type') || 'spec';
const specReviewRequired = extractField(taskBrief, 'Spec review required') || 'yes';
const changeClassification = extractField(taskBrief, 'Change classification') || 'non-semantic';
const requiredVerifierCommands = extractField(taskBrief, 'Required verifier commands') || 'npm run docs:check; npm run process:selftest';
const sourceOfTruthDocs = extractField(taskBrief, 'Source-of-truth docs') || 'none';
const externalSources = extractField(taskBrief, 'External sources required') || 'none';
const criticalAssumptions = extractField(taskBrief, 'Critical assumptions to prove or reject') || 'none';
const requiredOutputFields = extractField(taskBrief, 'Required output fields') || 'none';
const reviewNoteImpact = extractField(taskBrief, 'Review note impact') || 'no';
const specFilesReviewed = extractPathTokens(extractField(specReviewReport, 'Files touched/reviewed'));
const writerReportPath = findLatestReport(agentReportDirectory, defaultWriterRole, taskBriefPath);
const staleLines = [];

if (extractField(specReviewReport, 'Role').trim() !== 'spec-reviewer') {
  staleLines.push('spec-reviewer Agent Report must be written by spec-reviewer');
}

if (!taskBriefPath || !fs.existsSync(taskBriefPath)) {
  staleLines.push('spec-reviewer Agent Report must reference a valid Task Brief path');
}

if (specFiles.length === 0) {
  staleLines.push('spec surface changed files were not detected');
}

if (!specFiles.every((file) => specFilesReviewed.includes(file))) {
  staleLines.push('spec-reviewer Agent Report must cover the current spec scope');
}

if (artifactType !== 'spec') {
  staleLines.push('Task Brief artifact type must be spec');
}

if (!/^(yes|true|1)$/i.test(String(specReviewRequired).trim())) {
  staleLines.push('Spec review required must be yes');
}

for (const specFile of specFiles) {
  if (fs.existsSync(specFile) && fs.statSync(specFile).mtimeMs >= reportMtime) {
    staleLines.push(`spec-reviewer Agent Report must postdate spec artifact '${specFile}'`);
  }
}

if (writerReportPath) {
  if (fs.statSync(writerReportPath).mtimeMs >= reportMtime) {
    staleLines.push('spec-reviewer Agent Report must postdate the current writer Agent Report');
  }
} else {
  staleLines.push('current writer Agent Report not found for spec surface');
}

if (staleLines.length === 0) {
  process.exit(0);
}

const requiredRerunRoles = dedupe([defaultWriterRole, 'spec-reviewer', 'verifier']);
const dispatchOrder = dedupe([defaultWriterRole, 'spec-reviewer', 'verifier']);
const outputPath = resolveUniqueOutput(path.join(followUpDir, `${loopDate}-${path.basename(taskBriefPath || 'spec-task-brief', path.extname(taskBriefPath || '.md'))}-stale-evidence-remediation.md`));

const followUpLines = [
  '# Follow-up Brief',
  '',
  '- Goal: Regenerate fresh reviewer and verifier evidence after stale evidence was detected for the current spec scope.',
  `- Change classification: ${changeClassification}`,
  `- Artifact type: ${artifactType}`,
  '- Spec review required: yes',
  `- Spec artifact paths: ${specArtifactPaths}`,
  `- Files in scope: ${specFiles.join(', ')}`,
  `- Known facts: parent task brief: ${taskBriefPath || '(missing)'}; parent spec-reviewer Agent Report: ${specReviewReportPath}${writerReportPath ? `; parent writer Agent Report: ${writerReportPath}` : ''}`,
  '- Open questions / assumptions: none',
  `- Risks to check: ${staleLines.join('; ')}`,
  `- Acceptance checks: rerun ${defaultWriterRole} -> spec-reviewer -> verifier against the latest spec scope`,
  '- Required artifacts: Task Brief, Agent Report, spec-reviewer Agent Report, verifier evidence',
  `- Parent Task Brief path: ${taskBriefPath || '(missing)'}`,
  `- Parent Agent Report path: ${writerReportPath || '(missing)'}`,
  `- Trigger review note: ${specReviewReportPath}`,
  `- Trigger stale findings: ${staleLines.join(' | ')}`,
  `- Required rerun roles: ${requiredRerunRoles.join(', ')}`,
  `- Dispatch order: ${dispatchOrder.join(' -> ')}`,
  '- If blocked: stop and return the spec freshness blocker',
  '',
  '> Carry-over fields from the parent brief',
  '',
  `- Default writer role: ${defaultWriterRole}`,
  `- Implementation owner: ${defaultWriterRole}`,
  `- Write permissions: ${specFiles.join(', ')}`,
  '- Writer dispatch backend: native-codex-subagents',
  `- Writer dispatch target: .codex/agents/${defaultWriterRole}.toml`,
  `- Writer dispatch scope: ${specFiles.join(', ')}`,
  '- Non-goals: reuse stale spec-reviewer evidence',
  `- Required verifier commands: ${requiredVerifierCommands}`,
  '- Review note required: no',
  `- Semantic review dimensions: ${extractField(taskBrief, 'Semantic review dimensions') || 'none'}`,
  `- Source-of-truth docs: ${sourceOfTruthDocs}`,
  `- External sources required: ${externalSources}`,
  `- Critical assumptions to prove or reject: ${criticalAssumptions}`,
  `- Required output fields: ${requiredOutputFields}`,
  `- Review note impact: ${reviewNoteImpact}`,
  '- Generated by: script/process/run-stale-evidence-loop.sh'
];

fs.writeFileSync(outputPath, `${followUpLines.join('\n')}\n`);
fs.writeFileSync(
  metadataFile,
  JSON.stringify(
    {
      follow_up_brief_path: outputPath,
      parent_task_brief_path: taskBriefPath,
      parent_agent_report_path: writerReportPath || '',
      review_note_path: specReviewReportPath,
      required_rerun_roles: requiredRerunRoles,
      dispatch_order: dispatchOrder,
      stale_findings: staleLines
    },
    null,
    2
  ) + '\n'
);

console.log(`[stale-evidence-loop] stale evidence detected.`);
console.log(`[stale-evidence-loop] follow-up brief written: ${outputPath}`);
console.log(`[stale-evidence-loop] parent task brief: ${taskBriefPath || '(missing)'}`);
console.log(`[stale-evidence-loop] parent agent report: ${writerReportPath || '(missing)'}`);
console.log(`[stale-evidence-loop] trigger review note: ${specReviewReportPath}`);
console.log(`[stale-evidence-loop] re-dispatch order: ${dispatchOrder.join(' -> ')}`);
if (staleLines.length > 0) {
  console.log(`[stale-evidence-loop] stale findings: ${staleLines.join(' | ')}`);
}
process.exit(2);
EOF
    spec_status=$?
    set -e
    spec_output="$(cat "$spec_output_file")"
    rm -f "$spec_output_file"

    if [ "$spec_status" -eq 0 ]; then
        echo "[stale-evidence-loop] no stale evidence detected."
        exit 0
    fi

    if [ "$spec_status" -ne 2 ]; then
        printf '%s\n' "$spec_output" >&2
        exit "$spec_status"
    fi

    printf '%s\n' "$spec_output"
    exit 2
fi

review_note="${QUALITY_GATE_REVIEW_NOTE:-}"
if [ -z "$review_note" ]; then
    review_dir="$(read_policy_value quality_gate.review_note_directory 'docs/reviews')"
    if [ -d "$review_dir" ]; then
        mapfile -t review_candidates < <(find "$review_dir" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' ! -name 'TEMPLATE.md' | sort)
        review_note="$(discover_review_note "$changed_files_tmp" "${review_candidates[@]}" || true)"
    fi
fi

if [ -z "$review_note" ] || [ ! -f "$review_note" ]; then
    echo "[stale-evidence-loop] ERROR: review note not found. Set QUALITY_GATE_REVIEW_NOTE or provide a discoverable review note." >&2
    exit 1
fi

set +e
check_output="$(QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST="$changed_files_tmp" QUALITY_GATE_REVIEW_NOTE="$review_note" bash ./script/process/check-solidity-review-note.sh 2>&1)"
check_status=$?
set -e

if [ "$check_status" -eq 0 ]; then
    echo "[stale-evidence-loop] no stale evidence detected."
    exit 0
fi

if ! printf '%s\n' "$check_output" | grep -qi "stale"; then
    printf '%s\n' "$check_output" >&2
    exit "$check_status"
fi

follow_up_dir="${FOLLOW_UP_BRIEF_OUTPUT_DIR:-$(read_policy_value agents.task_brief_directory 'docs/task-briefs')}"
mkdir -p "$follow_up_dir"

FOLLOW_UP_DIR="$follow_up_dir" REMEDIATION_METADATA_FILE="$metadata_tmp" REMEDIATION_LOOP_DATE="${REMEDIATION_LOOP_DATE:-$(date +%F)}" CHECK_OUTPUT="$check_output" CODEX_REVIEW_TASK_BRIEF_TOKEN="$codex_review_task_brief_token" node - "$review_note" "$changed_files_tmp" <<'EOF'
const fs = require('fs');
const path = require('path');

const [, , reviewNotePath, changedFilesPath] = process.argv;
const reviewNote = fs.readFileSync(reviewNotePath, 'utf8');
const changedFiles = fs.readFileSync(changedFilesPath, 'utf8').split(/\r?\n/).filter(Boolean);
const outputDir = process.env.FOLLOW_UP_DIR;
const metadataFile = process.env.REMEDIATION_METADATA_FILE;
const loopDate = process.env.REMEDIATION_LOOP_DATE;
const checkOutput = process.env.CHECK_OUTPUT || '';
const codexReviewTaskBriefToken = process.env.CODEX_REVIEW_TASK_BRIEF_TOKEN || 'npm run codex:review';

function extractField(document, field) {
  const prefix = `- ${field}:`;
  const lines = document.split(/\r?\n/);
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    if (!line.startsWith(prefix)) continue;

    let value = line.slice(prefix.length).trim();
    for (let cursor = index + 1; cursor < lines.length; cursor += 1) {
      const next = lines[cursor];
      if (/^- [^:]+:/.test(next)) break;
      if (next.startsWith('  ') || next === '') {
        value += `\n${next}`;
        continue;
      }
      break;
    }
    return value.trim();
  }
  return '';
}

function extractPathTokens(value) {
  const matches = value.match(/(?:^|[\s,;()[\]{}])((?:\/|(?:\.\.\/)+|\.\/)?[A-Za-z0-9._-]+(?:\/[A-Za-z0-9._-]+)+)(?=$|[\s,;()[\]{}:])/g) || [];
  return matches
    .map((entry) => entry.trim().replace(/^[\s,;()[\]{}]+/, '').replace(/[\s,;()[\]{}:]+$/, ''))
    .filter(Boolean);
}

function isNoneLike(value) {
  return /^(none|n\/a|na|not applicable)$/i.test(value.trim());
}

function tokenizeField(value) {
  if (!value || isNoneLike(value)) return [];
  return value.split(/[;,]/).map((entry) => entry.trim()).filter(Boolean);
}

function dedupe(items) {
  const seen = new Set();
  return items.filter((item) => {
    if (!item || seen.has(item)) return false;
    seen.add(item);
    return true;
  });
}

function slugify(value) {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .replace(/-+/g, '-');
}

function resolveUniqueOutput(basePath) {
  if (!fs.existsSync(basePath)) return basePath;
  const ext = path.extname(basePath);
  const stem = basePath.slice(0, -ext.length);
  let counter = 2;
  while (true) {
    const candidate = `${stem}-${counter}${ext}`;
    if (!fs.existsSync(candidate)) return candidate;
    counter += 1;
  }
}

const taskBriefPath = extractField(reviewNote, 'Task Brief path');
const agentReportPath = extractField(reviewNote, 'Agent Report path');
const implementationOwner = extractField(reviewNote, 'Implementation owner') || 'solidity-implementer';
if (!taskBriefPath || !fs.existsSync(taskBriefPath)) {
  throw new Error(`Task Brief path missing or not found: ${taskBriefPath || '(empty)'}`);
}
if (!agentReportPath || !fs.existsSync(agentReportPath)) {
  throw new Error(`Agent Report path missing or not found: ${agentReportPath || '(empty)'}`);
}

const taskBrief = fs.readFileSync(taskBriefPath, 'utf8');
const agentReport = fs.readFileSync(agentReportPath, 'utf8');
const changedSolidityFiles = changedFiles.filter((file) => /^(src|script|test)\/.*\.sol$/.test(file));
const changedProductionSolidityFiles = changedFiles.filter((file) => /^(src|script)\/.*\.sol$/.test(file));
const targetSolidityFiles = changedProductionSolidityFiles.length > 0 ? changedProductionSolidityFiles : changedSolidityFiles;

const originalRequiredRoles = tokenizeField(extractField(taskBrief, 'Required roles'));
const originalOptionalRoles = extractField(taskBrief, 'Optional roles') || 'none';
const defaultWriterRole = extractField(taskBrief, 'Default writer role') || implementationOwner;
const filesInScope = extractField(taskBrief, 'Files in scope') || targetSolidityFiles.join(', ');
const writePermissions = extractField(taskBrief, 'Write permissions') || filesInScope;
const dispatchBackend = extractField(taskBrief, 'Writer dispatch backend') || 'native-codex-subagents';
const dispatchTarget = extractField(taskBrief, 'Writer dispatch target') || `.codex/agents/${defaultWriterRole}.toml`;
const dispatchScope = extractField(taskBrief, 'Writer dispatch scope') || filesInScope;
const requiredVerifierCommands = extractField(taskBrief, 'Required verifier commands') || 'npm run codex:review';
const requiresCodexReview = String(requiredVerifierCommands).toLowerCase().includes(codexReviewTaskBriefToken.toLowerCase());
const originalRequiredArtifacts = extractField(taskBrief, 'Required artifacts') || 'Task Brief, Agent Report, review note';
const reviewNoteRequired = extractField(taskBrief, 'Review note required') || (changedProductionSolidityFiles.length > 0 ? 'yes' : 'no');
const semanticDimensions = extractField(taskBrief, 'Semantic review dimensions') || 'none';
const sourceOfTruthDocs = extractField(taskBrief, 'Source-of-truth docs') || 'none';
const externalSources = extractField(taskBrief, 'External sources required') || 'none';
const criticalAssumptions = extractField(taskBrief, 'Critical assumptions to prove or reject') || 'none';
const requiredOutputFields = extractField(taskBrief, 'Required output fields') || 'none';
const reviewNoteImpact = extractField(taskBrief, 'Review note impact') || 'no';
const originalAcceptanceChecks = extractField(taskBrief, 'Acceptance checks') || 'none';
const originalNonGoals = extractField(taskBrief, 'Non-goals') || 'none';
const originalChangeClassification = extractField(taskBrief, 'Change classification') || 'follow-up-remediation';
const originalKnownFacts = extractField(taskBrief, 'Known facts') || 'none';
const originalOpenQuestions = extractField(taskBrief, 'Open questions / assumptions') || 'none';
const originalOutOfScope = extractField(taskBrief, 'Out of scope') || originalNonGoals || 'none';
const originalIfBlocked = extractField(taskBrief, 'If blocked') || 'stop and return the blocking finding';
const priorFindings = extractField(agentReport, 'Findings') || 'none';
const priorFollowUp = extractField(agentReport, 'Required follow-up') || 'none';
const staleLines = checkOutput
  .split(/\r?\n/)
  .map((line) => line.trim())
  .filter((line) => /stale/i.test(line))
  .map((line) => line.replace(/^\[check-solidity-review-note\]\s*ERROR:\s*/i, ''));

const requiredRerunRoles = (() => {
  const baseline = [implementationOwner, 'verifier'];
  for (const role of originalRequiredRoles) baseline.push(role);
  return dedupe(baseline);
})();

const downstreamReviewerRoles = requiredRerunRoles.filter((role) => role !== implementationOwner && role !== 'verifier');
const dispatchOrder = dedupe([
  implementationOwner,
  ...downstreamReviewerRoles,
  ...(requiresCodexReview ? ['codex review'] : []),
  'verifier'
]);

const risksToCheckParts = dedupe([
  'stale reviewer/verifier evidence must be regenerated against the latest writer Agent Report',
  ...staleLines,
  isNoneLike(priorFollowUp) ? '' : priorFollowUp,
  isNoneLike(priorFindings) ? '' : priorFindings
]);

const reviewerRerunLabel = downstreamReviewerRoles.length > 0
  ? `rerun ${downstreamReviewerRoles.join('/')} against the latest writer Agent Report`
  : 'regenerate fresh verifier evidence against the latest writer Agent Report';

const acceptanceCheckParts = dedupe([
  isNoneLike(originalAcceptanceChecks) ? '' : originalAcceptanceChecks,
  'regenerate the writer Agent Report after the current remediation pass',
  reviewerRerunLabel,
  requiresCodexReview ? 'rerun npm run codex:review after the reviewer pass' : '',
  'rerun verifier and clear stale evidence findings from check-solidity-review-note.sh'
]);

const nonGoalParts = dedupe([
  isNoneLike(originalNonGoals) ? '' : originalNonGoals,
  'reuse stale reviewer/verifier evidence',
  'expand scope beyond the stale-evidence remediation paths without a new brief'
]);

const knownFactParts = dedupe([
  isNoneLike(originalKnownFacts) ? '' : originalKnownFacts,
  `parent task brief: ${taskBriefPath}`,
  `parent agent report: ${agentReportPath}`,
  `trigger review note: ${reviewNotePath}`
]);

const openQuestionParts = dedupe([
  isNoneLike(originalOpenQuestions) ? '' : originalOpenQuestions,
  'none'
]).filter((item, index, items) => !(item === 'none' && items.length > 1));

const requiredArtifactParts = dedupe([
  ...tokenizeField(originalRequiredArtifacts),
  downstreamReviewerRoles.length > 0 ? `fresh ${downstreamReviewerRoles.join('/')} and verifier evidence` : 'fresh verifier evidence'
]);

const baseSlug = slugify(path.basename(taskBriefPath, path.extname(taskBriefPath))) || 'task-brief';
const outputPath = resolveUniqueOutput(path.join(outputDir, `${loopDate}-${baseSlug}-stale-evidence-remediation.md`));

const lines = [
  '# Follow-up Brief',
  '',
  '- Goal: Regenerate fresh reviewer and verifier evidence after stale evidence was detected for the current Solidity scope.',
  `- Change classification: ${originalChangeClassification}`,
  `- Files in scope: ${filesInScope}`,
  `- Out of scope: ${originalOutOfScope}`,
  `- Known facts: ${knownFactParts.length > 0 ? knownFactParts.join('; ') : 'none'}`,
  `- Open questions / assumptions: ${openQuestionParts.length > 0 ? openQuestionParts.join('; ') : 'none'}`,
  `- Risks to check: ${risksToCheckParts.length > 0 ? risksToCheckParts.join('; ') : 'stale reviewer/verifier evidence must be regenerated against the latest writer Agent Report'}`,
  `- Acceptance checks: ${acceptanceCheckParts.length > 0 ? acceptanceCheckParts.join('; ') : 'rerun reviewer and verifier evidence against the latest writer Agent Report'}`,
  `- Required artifacts: ${requiredArtifactParts.length > 0 ? requiredArtifactParts.join(', ') : 'Task Brief, Agent Report, review note, fresh reviewer/verifier evidence'}`,
  `- Parent Task Brief path: ${taskBriefPath}`,
  `- Parent Agent Report path: ${agentReportPath}`,
  `- Trigger review note: ${reviewNotePath}`,
  `- Trigger stale findings: ${staleLines.length > 0 ? staleLines.join(' | ') : 'stale reviewer/verifier evidence detected by check-solidity-review-note.sh'}`,
  `- Required rerun roles: ${requiredRerunRoles.join(', ')}`,
  `- Dispatch order: ${dispatchOrder.join(' -> ')}`,
  `- If blocked: ${originalIfBlocked}`,
  '',
  '> Carry-over fields from the parent brief',
  '',
  `- Optional roles: ${originalOptionalRoles}`,
  `- Default writer role: ${defaultWriterRole}`,
  `- Implementation owner: ${implementationOwner}`,
  `- Write permissions: ${writePermissions}`,
  `- Writer dispatch backend: ${dispatchBackend}`,
  `- Writer dispatch target: ${dispatchTarget}`,
  `- Writer dispatch scope: ${dispatchScope}`,
  `- Non-goals: ${nonGoalParts.length > 0 ? nonGoalParts.join('; ') : 'reuse stale reviewer/verifier evidence'}`,
  `- Required verifier commands: ${requiredVerifierCommands}`,
  `- Review note required: ${reviewNoteRequired}`,
  `- Semantic review dimensions: ${semanticDimensions}`,
  `- Source-of-truth docs: ${sourceOfTruthDocs}`,
  `- External sources required: ${externalSources}`,
  `- Critical assumptions to prove or reject: ${criticalAssumptions}`,
  `- Required output fields: ${requiredOutputFields}`,
  `- Review note impact: ${reviewNoteImpact}`,
  '- Generated by: script/process/run-stale-evidence-loop.sh'
];

fs.writeFileSync(outputPath, `${lines.join('\n')}\n`);
fs.writeFileSync(
  metadataFile,
  JSON.stringify(
    {
      follow_up_brief_path: outputPath,
      parent_task_brief_path: taskBriefPath,
      parent_agent_report_path: agentReportPath,
      review_note_path: reviewNotePath,
      required_rerun_roles: requiredRerunRoles,
      dispatch_order: dispatchOrder,
      stale_findings: staleLines
    },
    null,
    2
  ) + '\n'
);
EOF
node - "$metadata_tmp" <<'EOF'
const fs = require('fs');

const metadata = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
console.log(`[stale-evidence-loop] stale evidence detected.`);
console.log(`[stale-evidence-loop] follow-up brief written: ${metadata.follow_up_brief_path}`);
console.log(`[stale-evidence-loop] parent task brief: ${metadata.parent_task_brief_path}`);
console.log(`[stale-evidence-loop] parent agent report: ${metadata.parent_agent_report_path}`);
console.log(`[stale-evidence-loop] trigger review note: ${metadata.review_note_path}`);
console.log(`[stale-evidence-loop] re-dispatch order: ${metadata.dispatch_order.join(' -> ')}`);
if (metadata.stale_findings.length > 0) {
  console.log(`[stale-evidence-loop] stale findings: ${metadata.stale_findings.join(' | ')}`);
}
EOF

exit 2
