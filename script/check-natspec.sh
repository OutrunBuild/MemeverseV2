#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <solidity-file> [solidity-file ...]"
    exit 1
fi

node - "$@" <<'EOF'
const fs = require('fs');

const files = process.argv.slice(2);
const failures = [];

function splitTopLevel(value) {
  const parts = [];
  let current = '';
  let depth = 0;

  for (const char of value) {
    if (char === ',' && depth === 0) {
      parts.push(current.trim());
      current = '';
      continue;
    }

    if (char === '(' || char === '[') depth += 1;
    if (char === ')' || char === ']') depth -= 1;
    current += char;
  }

  if (current.trim() !== '') parts.push(current.trim());
  return parts;
}

function extractName(segment) {
  const cleaned = segment.trim().replace(/\s+/g, ' ');
  if (cleaned === '') return null;

  const match = cleaned.match(/([A-Za-z_][A-Za-z0-9_]*)$/);
  if (!match) return null;

  const candidate = match[1];
  if (['memory', 'calldata', 'storage', 'payable'].includes(candidate)) return null;
  return candidate;
}

function extractNatSpec(lines, startLine) {
  let index = startLine - 1;

  while (index >= 0 && lines[index].trim() === '') {
    index -= 1;
  }

  if (index < 0) return '';

  if (lines[index].trim().startsWith('///')) {
    const block = [];
    while (index >= 0 && lines[index].trim().startsWith('///')) {
      block.unshift(lines[index].trim());
      index -= 1;
    }
    return block.join('\n');
  }

  if (lines[index].includes('*/')) {
    const block = [];
    while (index >= 0) {
      block.unshift(lines[index].trim());
      if (lines[index].includes('/**')) break;
      index -= 1;
    }

    if (block[0] && block[0].includes('/**')) {
      return block.join('\n');
    }
  }

  return '';
}

function extractParenthesizedClause(signature, startIndex) {
  const openIndex = signature.indexOf('(', startIndex);
  if (openIndex === -1) return null;

  let depth = 0;
  for (let index = openIndex; index < signature.length; index += 1) {
    const char = signature[index];
    if (char === '(') depth += 1;
    if (char === ')') {
      depth -= 1;
      if (depth === 0) {
        return signature.slice(openIndex + 1, index);
      }
    }
  }

  return null;
}

function addFailure(file, name, message) {
  failures.push(`${file}: function ${name} ${message}`);
}

for (const file of files) {
  if (!file.endsWith('.sol')) {
    continue;
  }

  const content = fs.readFileSync(file, 'utf8');
  const lines = content.split(/\r?\n/);

  for (let lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
    if (!/\bfunction\b/.test(lines[lineIndex])) continue;

    const startLine = lineIndex;
    let signature = lines[lineIndex].trim();

    while (!/[;{]/.test(signature) && lineIndex + 1 < lines.length) {
      lineIndex += 1;
      signature += ` ${lines[lineIndex].trim()}`;
    }

    if (!/\b(public|external)\b/.test(signature)) continue;

    const nameMatch = signature.match(/\bfunction\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/);
    if (!nameMatch) continue;

    const name = nameMatch[1];
    const natSpec = extractNatSpec(lines, startLine);

    if (natSpec === '') {
      addFailure(file, name, 'is missing a NatSpec block');
      continue;
    }

    if (!/@notice\b/.test(natSpec)) addFailure(file, name, 'is missing @notice');
    if (!/@dev\b/.test(natSpec)) addFailure(file, name, 'is missing @dev');

    const paramsClause = extractParenthesizedClause(signature, signature.indexOf(`function ${name}`));
    if (paramsClause && paramsClause.trim() !== '') {
      for (const param of splitTopLevel(paramsClause.trim())) {
        const paramName = extractName(param);
        if (!paramName) continue;

        const paramPattern = new RegExp(`@param\\s+${paramName}(\\s|$)`);
        if (!paramPattern.test(natSpec)) {
          addFailure(file, name, `is missing @param ${paramName}`);
        }
      }
    }

    const returnsIndex = signature.indexOf('returns');
    const returnsClause = returnsIndex === -1 ? null : extractParenthesizedClause(signature, returnsIndex);
    if (returnsClause && returnsClause.trim() !== '' && !/@return\b/.test(natSpec)) {
      addFailure(file, name, 'is missing @return');
    }
  }
}

if (failures.length > 0) {
  for (const failure of failures) {
    console.error(failure);
  }
  process.exit(1);
}
EOF
