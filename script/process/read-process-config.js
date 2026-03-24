#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

function usage() {
  console.error('Usage: read-process-config.js <policy|rule-map> <dot.path|__file__> [--lines]');
  process.exit(1);
}

const [, , kind, keyPath, format] = process.argv;

if (!kind || !keyPath) {
  usage();
}

const policyPath = process.env.PROCESS_POLICY_FILE || 'docs/process/policy.json';

function readJsonFile(filePath) {
  const absolutePath = path.resolve(filePath);
  return JSON.parse(fs.readFileSync(absolutePath, 'utf8'));
}

function resolveRuleMapPath() {
  if (process.env.PROCESS_RULE_MAP_FILE) {
    return process.env.PROCESS_RULE_MAP_FILE;
  }

  try {
    const policy = readJsonFile(policyPath);
    const configuredPath = policy?.rule_map?.path;
    if (typeof configuredPath === 'string' && configuredPath.trim() !== '') {
      return configuredPath;
    }
  } catch (error) {
    // Fall back to the repository default when policy is unavailable.
  }

  return 'docs/process/rule-map.json';
}

function loadChangedFiles() {
  if (process.env.PROCESS_CHANGED_FILES_FILE) {
    return fs.readFileSync(path.resolve(process.env.PROCESS_CHANGED_FILES_FILE), 'utf8')
      .split(/\r?\n/)
      .filter(Boolean);
  }

  return (process.env.PROCESS_CHANGED_FILES || '')
    .split(/\r?\n/)
    .filter(Boolean);
}

function getTriggeredRequirements(ruleMap, requirementType) {
  const changedFiles = loadChangedFiles();
  const version = ruleMap.version || 1;
  const requirementKey = requirementType === 'change' ? 'change_requirement' : 'evidence_requirement';
  const defaultModeKey = requirementType === 'change' ? 'change_requirement_mode' : 'evidence_requirement_mode';
  const fallbackMode = requirementType === 'change' ? 'none' : 'any';
  const requirements = [];

  for (const rule of Array.isArray(ruleMap.rules) ? ruleMap.rules : []) {
    let triggeredBy = [];
    let mode = fallbackMode;
    let tests = [];

    if (version === 1) {
      triggeredBy = changedFiles.filter((file) => file.startsWith(rule.path_prefix || ''));
      if (triggeredBy.length === 0) continue;
      mode = 'any';
      tests = Array.isArray(rule.required_test_patterns) ? rule.required_test_patterns : [];
    } else if (version === 2) {
      const triggerPaths = Array.isArray(rule.triggers?.any_of) ? rule.triggers.any_of : [];
      triggeredBy = triggerPaths.filter((candidate) => changedFiles.includes(candidate));
      if (triggeredBy.length === 0) continue;

      const requirement = rule[requirementKey] || {};
      mode = requirement.mode || ruleMap.defaults?.[defaultModeKey] || fallbackMode;
      tests = Array.isArray(requirement.tests) ? requirement.tests : [];
    } else {
      throw new Error(`Unsupported rule-map version: ${version}`);
    }

    requirements.push({
      id: rule.id,
      description: rule.description || '',
      triggeredBy,
      mode,
      tests
    });
  }

  return requirements;
}

function getTriggeredTests(ruleMap, requirementType) {
  const seen = new Set();
  const tests = [];

  for (const requirement of getTriggeredRequirements(ruleMap, requirementType)) {
    for (const test of requirement.tests) {
      if (seen.has(test)) continue;
      seen.add(test);
      tests.push(test);
    }
  }

  return tests;
}

const fileByKind = {
  policy: policyPath,
  'rule-map': resolveRuleMapPath()
};

const configPath = fileByKind[kind];
if (!configPath) {
  usage();
}

const absolutePath = path.resolve(configPath);
const document = JSON.parse(fs.readFileSync(absolutePath, 'utf8'));

if (keyPath === '__file__') {
  process.stdout.write(absolutePath);
  process.exit(0);
}

if (kind === 'rule-map' && keyPath === 'triggered.change.requirements') {
  process.stdout.write(JSON.stringify(getTriggeredRequirements(document, 'change')));
  process.exit(0);
}

if (kind === 'rule-map' && keyPath === 'triggered.evidence.requirements') {
  process.stdout.write(JSON.stringify(getTriggeredRequirements(document, 'evidence')));
  process.exit(0);
}

if (kind === 'rule-map' && keyPath === 'triggered.change.tests') {
  const tests = getTriggeredTests(document, 'change');
  if (format === '--lines') {
    for (const test of tests) {
      process.stdout.write(`${test}\n`);
    }
    process.exit(0);
  }
  process.stdout.write(JSON.stringify(tests));
  process.exit(0);
}

if (kind === 'rule-map' && keyPath === 'triggered.evidence.tests') {
  const tests = getTriggeredTests(document, 'evidence');
  if (format === '--lines') {
    for (const test of tests) {
      process.stdout.write(`${test}\n`);
    }
    process.exit(0);
  }
  process.stdout.write(JSON.stringify(tests));
  process.exit(0);
}

let value = document;
for (const key of keyPath.split('.')) {
  if (key === '') continue;
  if (value == null || !(key in value)) {
    console.error(`Missing config key '${keyPath}' in ${configPath}`);
    process.exit(1);
  }
  value = value[key];
}

if (format === '--lines') {
  if (!Array.isArray(value)) {
    console.error(`Config key '${keyPath}' in ${configPath} is not an array`);
    process.exit(1);
  }

  for (const entry of value) {
    process.stdout.write(String(entry));
    process.stdout.write('\n');
  }
  process.exit(0);
}

if (typeof value === 'object') {
  process.stdout.write(JSON.stringify(value));
  process.exit(0);
}

process.stdout.write(String(value));
