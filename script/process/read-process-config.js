#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

function usage() {
  console.error('Usage: read-process-config.js <policy|rule-map> <dot.path> [--lines]');
  process.exit(1);
}

const [, , kind, keyPath, format] = process.argv;

if (!kind || !keyPath) {
  usage();
}

const fileByKind = {
  policy: process.env.PROCESS_POLICY_FILE || 'docs/process/policy.json',
  'rule-map': process.env.PROCESS_RULE_MAP_FILE || 'docs/process/rule-map.json'
};

const configPath = fileByKind[kind];
if (!configPath) {
  usage();
}

const absolutePath = path.resolve(configPath);
const document = JSON.parse(fs.readFileSync(absolutePath, 'utf8'));

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
