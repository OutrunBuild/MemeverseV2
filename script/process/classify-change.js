#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

function usage() {
  console.error('Usage: classify-change.js [--field dot.path] [--lines]');
  process.exit(1);
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function readPolicyValue(document, keyPath, fallback) {
  if (!keyPath) return document;
  let value = document;
  for (const key of keyPath.split('.')) {
    if (key === '') continue;
    if (value == null || !Object.prototype.hasOwnProperty.call(value, key)) {
      return fallback;
    }
    value = value[key];
  }
  return value;
}

function runGit(args) {
  return execFileSync('git', args, { encoding: 'utf8' });
}

function gitRefExists(ref) {
  try {
    execFileSync('git', ['rev-parse', '--verify', ref], { stdio: 'ignore' });
    return true;
  } catch (error) {
    return false;
  }
}

function loadChangedFiles(mode) {
  if (process.env.QUALITY_GATE_FILE_LIST && fs.existsSync(process.env.QUALITY_GATE_FILE_LIST)) {
    return fs
      .readFileSync(process.env.QUALITY_GATE_FILE_LIST, 'utf8')
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean);
  }

  if (mode === 'ci') {
    if (process.env.GITHUB_BASE_REF) {
      return runGit(['diff', '--name-only', `origin/${process.env.GITHUB_BASE_REF}...HEAD`])
        .split(/\r?\n/)
        .map((line) => line.trim())
        .filter(Boolean);
    }

    if (gitRefExists('HEAD~1')) {
      return runGit(['diff', '--name-only', 'HEAD~1..HEAD'])
        .split(/\r?\n/)
        .map((line) => line.trim())
        .filter(Boolean);
    }

    return runGit(['ls-files'])
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean);
  }

  return runGit(['diff', '--cached', '--name-only', '--diff-filter=ACMRD'])
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
}

function loadPatch(mode, files) {
  if (process.env.CHANGE_CLASSIFIER_DIFF_FILE && fs.existsSync(process.env.CHANGE_CLASSIFIER_DIFF_FILE)) {
    return fs.readFileSync(process.env.CHANGE_CLASSIFIER_DIFF_FILE, 'utf8');
  }

  if (files.length === 0) return '';

  const fileArgs = ['--', ...files];

  if (mode === 'ci') {
    if (process.env.GITHUB_BASE_REF) {
      return runGit(['diff', '--unified=0', `origin/${process.env.GITHUB_BASE_REF}...HEAD`, ...fileArgs]);
    }

    if (gitRefExists('HEAD~1')) {
      return runGit(['diff', '--unified=0', 'HEAD~1..HEAD', ...fileArgs]);
    }

    if (gitRefExists('HEAD')) {
      return runGit(['diff', '--unified=0', 'HEAD', ...fileArgs]);
    }

    return '';
  }

  return runGit(['diff', '--cached', '--unified=0', ...fileArgs]);
}

function isCommentLine(line) {
  return (
    /^\/\//.test(line) ||
    /^\/\*/.test(line) ||
    /^\*/.test(line) ||
    /^\*\//.test(line) ||
    /^SPDX-License-Identifier:/i.test(line)
  );
}

function isPunctuationOnly(line) {
  return line.replace(/[{}\[\]();,]/g, '').trim() === '';
}

function isNonSemanticLine(line) {
  const trimmed = line.trim();
  if (trimmed === '') return true;
  if (isCommentLine(trimmed)) return true;
  if (isPunctuationOnly(trimmed)) return true;
  return false;
}

function parsePatch(patch, solidityFiles, highRiskTokenPatterns) {
  const trackedFiles = new Set(solidityFiles);
  const analysis = new Map();

  function ensureFile(filePath) {
    if (!analysis.has(filePath)) {
      analysis.set(filePath, {
        semantic: false,
        semanticLines: [],
        tokenHits: new Set(),
      });
    }
    return analysis.get(filePath);
  }

  for (const filePath of solidityFiles) {
    ensureFile(filePath);
  }

  let currentFile = null;
  for (const rawLine of patch.split(/\r?\n/)) {
    if (rawLine.startsWith('diff --git ')) {
      const match = /^diff --git a\/(.+?) b\/(.+)$/.exec(rawLine);
      currentFile = match ? match[2] : null;
      continue;
    }

    if (rawLine.startsWith('+++ b/')) {
      currentFile = rawLine.slice('+++ b/'.length).trim();
      continue;
    }

    if (!currentFile || !trackedFiles.has(currentFile)) continue;
    if (rawLine.startsWith('+++') || rawLine.startsWith('---') || rawLine.startsWith('@@')) continue;
    if (!(rawLine.startsWith('+') || rawLine.startsWith('-'))) continue;

    const content = rawLine.slice(1).trim();
    if (isNonSemanticLine(content)) continue;

    const fileEntry = ensureFile(currentFile);
    fileEntry.semantic = true;
    fileEntry.semanticLines.push(content);

    for (const pattern of highRiskTokenPatterns) {
      const regex = new RegExp(pattern, 'i');
      if (regex.test(content)) {
        fileEntry.tokenHits.add(pattern);
      }
    }
  }

  return analysis;
}

function summarizeRationale({ classification, semanticSrcFiles, semanticTestFiles, highRiskReasons, srcFiles, testFiles }) {
  if (classification === 'none') return 'no Solidity files changed';
  if (classification === 'non-semantic') {
    return `all changed Solidity lines in ${[...srcFiles, ...testFiles].join(', ')} were comment-only, whitespace-only, or punctuation-only`;
  }
  if (classification === 'test-semantic') {
    return `semantic changes were limited to test Solidity files: ${semanticTestFiles.join(', ')}`;
  }
  if (classification === 'prod-semantic') {
    return `semantic changes touched production Solidity files: ${semanticSrcFiles.join(', ')}`;
  }
  if (classification === 'high-risk') {
    return `semantic production changes triggered high-risk heuristics: ${highRiskReasons.join('; ')}`;
  }
  return 'classification unavailable';
}

const args = process.argv.slice(2);
let fieldPath = '';
let outputLines = false;

for (let index = 0; index < args.length; index += 1) {
  const arg = args[index];
  if (arg === '--field') {
    fieldPath = args[index + 1] || '';
    index += 1;
    continue;
  }
  if (arg === '--lines') {
    outputLines = true;
    continue;
  }
  if (arg === '--json') {
    continue;
  }
  usage();
}

const repoRoot = runGit(['rev-parse', '--show-toplevel']).trim();
process.chdir(repoRoot);

const mode = process.env.QUALITY_GATE_MODE || 'staged';
const policyPath = path.resolve(process.env.PROCESS_POLICY_FILE || 'docs/process/policy.json');
const policy = readJson(policyPath);
const classifierConfig = readPolicyValue(policy, 'change_classifier', {});
const qualityGateConfig = readPolicyValue(policy, 'quality_gate', {});

const srcPattern = new RegExp(readPolicyValue(qualityGateConfig, 'src_sol_pattern', '^src/.*\\.sol$'));
const scriptPattern = new RegExp(readPolicyValue(qualityGateConfig, 'script_sol_pattern', '^script/.*\\.sol$'));
const testTsolPattern = new RegExp(readPolicyValue(qualityGateConfig, 'test_tsol_pattern', '^test/.*\\.t\\.sol$'));
const testSolPattern = new RegExp(readPolicyValue(qualityGateConfig, 'test_sol_pattern', '^test/.*\\.sol$'));
const highRiskPathPatterns = readPolicyValue(classifierConfig, 'high_risk_path_patterns', []);
const highRiskTokenPatterns = readPolicyValue(classifierConfig, 'high_risk_token_patterns', []);
const roleMatrix = readPolicyValue(classifierConfig, 'role_matrix', {});

const changedFiles = loadChangedFiles(mode);
const changedSolidityFiles = changedFiles.filter((file) => srcPattern.test(file) || scriptPattern.test(file) || testTsolPattern.test(file) || testSolPattern.test(file));
const productionSolidityFiles = changedSolidityFiles.filter((file) => srcPattern.test(file) || scriptPattern.test(file));
const testSolidityFiles = changedSolidityFiles.filter((file) => !srcPattern.test(file) && !scriptPattern.test(file) && (testTsolPattern.test(file) || testSolPattern.test(file)));
const patch = loadPatch(mode, changedSolidityFiles);
const patchAnalysis = parsePatch(patch, changedSolidityFiles, highRiskTokenPatterns);

const semanticSrcFiles = productionSolidityFiles.filter((file) => patchAnalysis.get(file)?.semantic);
const semanticTestFiles = testSolidityFiles.filter((file) => patchAnalysis.get(file)?.semantic);
const nonSemanticSrcFiles = productionSolidityFiles.filter((file) => !patchAnalysis.get(file)?.semantic);
const nonSemanticTestFiles = testSolidityFiles.filter((file) => !patchAnalysis.get(file)?.semantic);

const highRiskReasons = [];
for (const file of semanticSrcFiles) {
  for (const pattern of highRiskPathPatterns) {
    if (new RegExp(pattern).test(file)) {
      highRiskReasons.push(`path:${file}~/${pattern}/`);
    }
  }

  const fileEntry = patchAnalysis.get(file);
  if (fileEntry) {
    for (const tokenPattern of fileEntry.tokenHits) {
      highRiskReasons.push(`token:${file}~/${tokenPattern}/`);
    }
  }
}

const forcedClassification = process.env.CHANGE_CLASSIFIER_FORCE || '';
let classification = 'none';
if (forcedClassification) {
  classification = forcedClassification;
} else if (changedSolidityFiles.length === 0) {
  classification = 'none';
} else if (semanticSrcFiles.length > 0) {
  classification = highRiskReasons.length > 0 ? 'high-risk' : 'prod-semantic';
} else if (semanticTestFiles.length > 0) {
  classification = 'test-semantic';
} else {
  classification = 'non-semantic';
}

const matrixEntry = roleMatrix[classification] || {
  required_roles: [],
  optional_roles: [],
  verifier_profile: 'none',
};

const reviewNoteRequired = productionSolidityFiles.length > 0 ? 'yes' : 'no';
const result = {
  classification,
  rationale: forcedClassification
    ? `forced by CHANGE_CLASSIFIER_FORCE=${forcedClassification}`
    : summarizeRationale({
        classification,
        semanticSrcFiles,
        semanticTestFiles,
        highRiskReasons,
        srcFiles: productionSolidityFiles,
        testFiles: testSolidityFiles,
      }),
  verifier_profile: matrixEntry.verifier_profile || 'none',
  required_roles: matrixEntry.required_roles || [],
  optional_roles: matrixEntry.optional_roles || [],
  review_note_required: reviewNoteRequired,
  has_src_solidity: productionSolidityFiles.length > 0,
  has_test_solidity: testSolidityFiles.length > 0,
  semantic_src_files: semanticSrcFiles,
  semantic_test_files: semanticTestFiles,
  non_semantic_src_files: nonSemanticSrcFiles,
  non_semantic_test_files: nonSemanticTestFiles,
  high_risk_reasons: Array.from(new Set(highRiskReasons)),
  changed_solidity_files: changedSolidityFiles,
};

let outputValue = result;
if (fieldPath) {
  outputValue = readPolicyValue(result, fieldPath, undefined);
  if (outputValue === undefined) {
    console.error(`Missing classifier field '${fieldPath}'`);
    process.exit(1);
  }
}

if (outputLines) {
  if (!Array.isArray(outputValue)) {
    console.error(`Classifier field '${fieldPath}' is not an array`);
    process.exit(1);
  }
  for (const entry of outputValue) {
    process.stdout.write(String(entry));
    process.stdout.write('\n');
  }
  process.exit(0);
}

if (typeof outputValue === 'object') {
  process.stdout.write(JSON.stringify(outputValue));
  process.exit(0);
}

process.stdout.write(String(outputValue));
